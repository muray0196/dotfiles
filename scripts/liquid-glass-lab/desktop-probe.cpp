// Diagnostic only: two bounded framebuffer reads in a disposable nested compositor.
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <GLES3/gl3.h>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <unistd.h>

namespace {
CHyprSignalListener listener;
std::filesystem::path output;
bool capturedBefore = false;
bool capturedAfter = false;

class Capture final : public IPassElement {
  bool after;

public:
  explicit Capture(bool afterLayers) : after(afterLayers) {}
  bool needsLiveBlur() override { return false; }
  bool needsPrecomputeBlur() override { return false; }
  bool undiscardable() override { return true; }
  bool disableSimplification() override { return true; }
  const char* passName() override { return "liquid-glass-order-probe"; }
  ePassElementType type() override { return EK_CUSTOM; }

  std::vector<UP<IPassElement>> draw() override {
    bool& done = after ? capturedAfter : capturedBefore;
    if (done)
      return {};
    const auto fb = g_pHyprRenderer->m_renderData.currentFB;
    if (!fb)
      return {};
    const int width = fb->m_size.x, height = fb->m_size.y;
    if (width < 1 || height < 1 || width > 4096 || height > 4096)
      return {};

    // Restore every pixel-pack setting changed by this probe. Hyprland's
    // intermediate target has an inverted projection: its first row is the
    // logical top. This probe is restricted to an untransformed nested output.
    GLint alignment, buffer, rowLength, skipRows, skipPixels, readFB, drawFB;
    glGetIntegerv(GL_PACK_ALIGNMENT, &alignment);
    glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &buffer);
    glGetIntegerv(GL_PACK_ROW_LENGTH, &rowLength);
    glGetIntegerv(GL_PACK_SKIP_ROWS, &skipRows);
    glGetIntegerv(GL_PACK_SKIP_PIXELS, &skipPixels);
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &readFB);
    glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &drawFB);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, drawFB);
    glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glPixelStorei(GL_PACK_ROW_LENGTH, 0);
    glPixelStorei(GL_PACK_SKIP_ROWS, 0);
    glPixelStorei(GL_PACK_SKIP_PIXELS, 0);
    std::vector<unsigned char> pixels(width * height * 4);
    glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, pixels.data());
    glPixelStorei(GL_PACK_ALIGNMENT, alignment);
    glPixelStorei(GL_PACK_ROW_LENGTH, rowLength);
    glPixelStorei(GL_PACK_SKIP_ROWS, skipRows);
    glPixelStorei(GL_PACK_SKIP_PIXELS, skipPixels);
    glBindBuffer(GL_PIXEL_PACK_BUFFER, buffer);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, readFB);

    const auto target = output / (after ? "after.ppm" : "before.ppm");
    const auto pending = target.string() + ".pending";
    std::ofstream file(pending, std::ios::binary);
    file << "P6\n" << width << " " << height << "\n255\n";
    for (int y = 0; y < height; ++y)
      for (int x = 0; x < width; ++x)
        file.write(reinterpret_cast<const char*>(&pixels[(y * width + x) * 4]), 3);
    file.close();
    if (file) {
      std::filesystem::rename(pending, target);
      done = true;
    }
    return {};
  }
};
}

APICALL EXPORT std::string PLUGIN_API_VERSION() { return HYPRLAND_API_VERSION; }

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE) {
  const char* expectedPid = std::getenv("LIQUID_GLASS_PROBE_PID");
  const char* directory = std::getenv("LIQUID_GLASS_PROBE_OUTPUT");
  const char* seat = std::getenv("LIBSEAT_BACKEND");
  if (!expectedPid || std::to_string(getpid()) != expectedPid || !directory || !seat ||
      std::string(seat) != "liquid-glass-probe-disabled")
    throw std::runtime_error("This diagnostic is restricted to its disposable nested compositor");
  if (std::string(__hyprland_api_get_hash()) != __hyprland_api_get_client_hash())
    throw std::runtime_error("Hyprland plugin ABI mismatch");
  if (g_pHyprRenderer->type() != Render::IHyprRenderer::RT_GL)
    throw std::runtime_error("The diagnostic requires the OpenGL renderer");
  output = directory;
  listener = Event::bus()->m_events.render.stage.listen([](eRenderStage stage) {
    if (stage == RENDER_POST_WINDOWS && !capturedBefore)
      g_pHyprRenderer->m_renderPass.add(makeUnique<Capture>(false));
    else if (stage == RENDER_LAST_MOMENT && !capturedAfter)
      g_pHyprRenderer->m_renderPass.add(makeUnique<Capture>(true));
  });
  return {"liquid-glass-order-probe", "Independent pre-layer framebuffer diagnostic", "dotfiles", "0.1"};
}

APICALL EXPORT void PLUGIN_EXIT() { listener.reset(); }
