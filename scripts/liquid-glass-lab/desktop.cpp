// Independent compositor backend for explicitly named Quickshell surfaces.
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <hyprland/src/managers/SessionLockManager.hpp>
#include <hyprland/src/Compositor.hpp>
#include <hyprland/protocols/wlr-layer-shell-unstable-v1.hpp>
#include <map>
#include <sstream>
#include "desktop-gpu.hpp"
#include "desktop-tints.hpp"

namespace {
CHyprSignalListener beforeRender, stage, monitorRemoved;
std::map<MONITORID, GlassGPU::Renderer> renderers;
std::map<MONITORID, CBox> previous;
double presence = 1;
std::string clarity = "soft";
size_t tintIndex = 0;
std::string failure;

bool supported(PHLMONITOR monitor) {
  if (!monitor || monitor->isMirror() || monitor->m_transform != WL_OUTPUT_TRANSFORM_NORMAL ||
      g_pSessionLockManager->isSessionLocked()) return false;
  const auto tf = monitor->workBufferImageDescription()->value().transferFunction;
  return tf == NColorManagement::CM_TRANSFER_FUNCTION_SRGB || tf == NColorManagement::CM_TRANSFER_FUNCTION_GAMMA22;
}

std::vector<GlassGPU::Rect> bodies(PHLMONITOR monitor) {
  std::vector<GlassGPU::Rect> result;
  if (!supported(monitor)) return result;
  for (const auto& ref : monitor->m_layerSurfaceLayers[ZWLR_LAYER_SHELL_V1_LAYER_TOP]) {
    auto layer = ref.lock();
    if (!layer || !layer->m_mapped || !layer->visible() || layer->m_namespace != "liquid-glass-v1") continue;
    auto box = layer->geometricBox(Desktop::View::IGeometric::GEOMETRIC_CURRENT);
    box.translate(-monitor->m_position);
    if (box.w > 72 && box.h > 72 && result.size() < 16)
      result.push_back({box.x + 28, box.y + 28, box.w - 56, box.h - 56,
                        layer->alpha()[Desktop::View::LS_ALPHA_FADE]->value()});
  }
  return result;
}

CBox region(const std::vector<GlassGPU::Rect>& items, PHLMONITOR monitor) {
  if (items.empty()) return {};
  double x = 1e9, y = 1e9, r = -1e9, b = -1e9;
  // Includes the entire refracted ray footprint, both blur passes, reflection
  // samples, and the shadow. Only actual output edges clamp the source.
  constexpr double margin = 220;
  for (const auto& item : items) {
    x = std::min(x, item.x - margin); y = std::min(y, item.y - margin);
    r = std::max(r, item.x + item.w + margin); b = std::max(b, item.y + item.h + margin);
  }
  const double s = monitor->m_scale;
  x = std::max(0.0, std::floor(x * s)); y = std::max(0.0, std::floor(y * s));
  r = std::min(monitor->m_transformedSize.x, std::ceil(r * s));
  b = std::min(monitor->m_transformedSize.y, std::ceil(b * s));
  return {x, y, std::max(0.0, r - x), std::max(0.0, b - y)};
}

void damageAll() {
  for (const auto& monitor : State::monitorState()->monitors()) g_pHyprRenderer->damageMonitor(monitor);
}

class GlassPass final : public IPassElement {
  PHLMONITOR monitor;
  std::vector<GlassGPU::Rect> items;
  CBox capture;
public:
  GlassPass(PHLMONITOR m, std::vector<GlassGPU::Rect> b) : monitor(m), items(std::move(b)), capture(region(items, m)) {}
  // Declare a backdrop dependency so occlusion cannot remove source pixels.
  bool needsLiveBlur() override { return true; }
  bool needsPrecomputeBlur() override { return false; }
  const char* passName() override { return "independent-liquid-glass"; }
  ePassElementType type() override { return EK_CUSTOM; }
  std::optional<CBox> boundingBox() override { return capture.copy().scale(1.0 / monitor->m_scale); }
  std::vector<UP<IPassElement>> draw() override {
    if (capture.empty() || !failure.empty()) return {};
    try {
      renderers[monitor->m_id].render({capture.x, capture.y, capture.w, capture.h}, items, monitor->m_scale, presence, clarity == "soft",
                                     clarity == "diffused", GlassTints::presets[tintIndex].color,
                                     monitor->m_size.x, monitor->m_size.y);
    } catch (const std::exception& e) {
      failure = e.what();
      Log::logger->log(Log::ERR, "Liquid Glass disabled: {}", failure);
    }
    return {};
  }
};

std::string status() {
  uint64_t frames = 0, samples = 0;
  double cpu = 0, gpu = 0, gpuMax = 0;
  float sourceAnisotropy = 0, maxAnisotropy = 0;
  for (const auto& [id, renderer] : renderers) {
    frames += renderer.frames; samples += renderer.samples; cpu += renderer.cpuTotal;
    gpu += renderer.gpuTotal; gpuMax = std::max(gpuMax, renderer.gpuMax);
    if (renderer.frames) {
      sourceAnisotropy = sourceAnisotropy ? std::min(sourceAnisotropy, renderer.appliedAnisotropy) : renderer.appliedAnisotropy;
      maxAnisotropy = maxAnisotropy ? std::min(maxAnisotropy, renderer.maxAnisotropy) : renderer.maxAnisotropy;
    }
  }
  std::ostringstream out;
  out << "{\"frames\":" << frames << ",\"gpu_samples\":" << samples
      << ",\"cpu_submit_ms\":" << (frames ? cpu / frames : 0)
      << ",\"gpu_ms\":" << (samples ? gpu / samples : 0) << ",\"gpu_max_ms\":" << gpuMax
      << ",\"failed\":" << (!failure.empty() ? "true" : "false") << ",\"presence\":" << presence
      << ",\"source_anisotropy\":" << (sourceAnisotropy ? sourceAnisotropy : 1)
      << ",\"max_anisotropy\":" << (maxAnisotropy ? maxAnisotropy : 1)
      << ",\"clarity\":\"" << clarity << "\",\"tint\":\"" << GlassTints::presets[tintIndex].name << "\"}";
  return out.str();
}
}

APICALL EXPORT std::string PLUGIN_API_VERSION() { return HYPRLAND_API_VERSION; }
APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
  if (std::string(__hyprland_api_get_hash()) != __hyprland_api_get_client_hash())
    throw std::runtime_error("Liquid Glass requires matching Hyprland development headers");
  if (g_pHyprRenderer->type() != Render::IHyprRenderer::RT_GL)
    throw std::runtime_error("Liquid Glass requires OpenGL");
  presence = 1;
  clarity = "soft";
  tintIndex = 0;
  failure.clear();
  beforeRender = Event::bus()->m_events.render.pre.listen([](PHLMONITOR monitor) {
    auto area = region(bodies(monitor), monitor);
    if (previous.contains(monitor->m_id)) monitor->m_damage.damage(previous[monitor->m_id]);
    if (!area.empty()) monitor->m_damage.damage(area);
    previous[monitor->m_id] = area;
    // This callback only runs for an already scheduled frame. Updating the ring
    // directly does not schedule another frame and therefore does not spin idle.
  });
  stage = Event::bus()->m_events.render.stage.listen([](eRenderStage where) {
    if (where != RENDER_POST_WINDOWS || !failure.empty()) return;
    auto monitor = g_pHyprRenderer->m_renderData.pMonitor.lock();
    auto items = bodies(monitor);
    if (!items.empty()) g_pHyprRenderer->m_renderPass.add(makeUnique<GlassPass>(monitor, std::move(items)));
  });
  monitorRemoved = Event::bus()->m_events.monitor.removed.listen([](PHLMONITOR monitor) {
    if (auto found = renderers.find(monitor->m_id); found != renderers.end()) {
      g_pHyprRenderer->glBackend()->makeEGLCurrent();
      found->second.release(); renderers.erase(found);
    }
    previous.erase(monitor->m_id);
  });
  HyprlandAPI::registerHyprCtlCommand(handle, {"liquidglass", false, [](eHyprCtlOutputFormat, std::string request) {
    std::istringstream input(request);
    std::string name, operation, extra;
    input >> name;
    if (!(input >> operation)) return status();
    if (operation == "clarity") {
      std::string value;
      if (!(input >> value) || (input >> extra) || (value != "clear" && value != "soft" && value != "diffused"))
        return std::string("error: expected liquidglass clarity <clear|soft|diffused>");
      clarity = value;
      damageAll(); return status();
    }
    if (operation == "tint") {
      std::string value;
      if ((input >> value) && !(input >> extra)) {
        for (size_t i = 0; i < GlassTints::presets.size(); ++i) {
          if (value != GlassTints::presets[i].name) continue;
          tintIndex = i;
          damageAll(); return status();
        }
      }
      return std::string("error: expected liquidglass tint <") + GlassTints::options + ">";
    }
    double number;
    if (operation != "presence" || !(input >> number) || (input >> extra) || !std::isfinite(number) || number < 0 || number > 1)
      return std::string("error: expected liquidglass presence <0..1>, clarity <clear|soft|diffused>, or tint <preset>");
    presence = number; damageAll(); return status();
  }});
  damageAll();
  return {"independent-liquid-glass", "GPU backdrop material for liquid-glass-v1 Quickshell surfaces", "dotfiles", "0.1"};
}
APICALL EXPORT void PLUGIN_EXIT() {
  beforeRender.reset(); stage.reset(); monitorRemoved.reset();
  // The last frame's pass may outlive draw(). Destroy our virtual objects while
  // their code is still mapped, before Hyprland calls dlclose().
  g_pHyprRenderer->m_renderPass.removeAllOfType("independent-liquid-glass");
  g_pHyprRenderer->glBackend()->makeEGLCurrent();
  for (auto& [id, renderer] : renderers) renderer.release();
  renderers.clear(); previous.clear(); damageAll();
}
