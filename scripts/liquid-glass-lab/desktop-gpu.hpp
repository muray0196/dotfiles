#pragma once
#include <GLES3/gl3.h>
#include <GLES2/gl2ext.h>
#include <EGL/egl.h>
#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <stdexcept>
#include <string>
#include <vector>
#include "desktop-shaders.hpp"

namespace GlassGPU {
struct Rect { double x, y, w, h; double opacity = 1; };

// Preserve the compositor's GL state, including sampler objects and split FBOs.
struct State {
  GLint program, vao, drawFB, readFB, active, unpackBuffer, viewport[4], scissor[4];
  GLint srcRGB, dstRGB, srcAlpha, dstAlpha, eqRGB, eqAlpha;
  std::array<GLint, 2> textures, samplers;
  GLboolean mask[4];
  const std::array<GLenum, 5> caps{GL_BLEND, GL_SCISSOR_TEST, GL_DEPTH_TEST, GL_STENCIL_TEST, GL_CULL_FACE};
  std::array<GLboolean, 5> enabled;
  State() {
    glGetIntegerv(GL_CURRENT_PROGRAM, &program); glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &vao);
    glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &drawFB); glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &readFB);
    glGetIntegerv(GL_ACTIVE_TEXTURE, &active); glGetIntegerv(GL_VIEWPORT, viewport); glGetIntegerv(GL_SCISSOR_BOX, scissor);
    glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING, &unpackBuffer); glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
    glGetIntegerv(GL_BLEND_SRC_RGB, &srcRGB); glGetIntegerv(GL_BLEND_DST_RGB, &dstRGB);
    glGetIntegerv(GL_BLEND_SRC_ALPHA, &srcAlpha); glGetIntegerv(GL_BLEND_DST_ALPHA, &dstAlpha);
    glGetIntegerv(GL_BLEND_EQUATION_RGB, &eqRGB); glGetIntegerv(GL_BLEND_EQUATION_ALPHA, &eqAlpha);
    glGetBooleanv(GL_COLOR_WRITEMASK, mask);
    for (unsigned i = 0; i < caps.size(); ++i) { enabled[i] = glIsEnabled(caps[i]); glDisable(caps[i]); }
    for (unsigned i = 0; i < 2; ++i) {
      glActiveTexture(GL_TEXTURE0 + i); glGetIntegerv(GL_TEXTURE_BINDING_2D, &textures[i]);
      glGetIntegerv(GL_SAMPLER_BINDING, &samplers[i]); glBindSampler(i, 0);
    }
    glColorMask(true, true, true, true);
  }
  ~State() {
    for (unsigned i = 0; i < 2; ++i) {
      glActiveTexture(GL_TEXTURE0 + i); glBindTexture(GL_TEXTURE_2D, textures[i]); glBindSampler(i, samplers[i]);
    }
    glActiveTexture(active); glUseProgram(program); glBindVertexArray(vao);
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER, unpackBuffer);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, drawFB); glBindFramebuffer(GL_READ_FRAMEBUFFER, readFB);
    glViewport(viewport[0], viewport[1], viewport[2], viewport[3]); glScissor(scissor[0], scissor[1], scissor[2], scissor[3]);
    glBlendFuncSeparate(srcRGB, dstRGB, srcAlpha, dstAlpha); glBlendEquationSeparate(eqRGB, eqAlpha);
    glColorMask(mask[0], mask[1], mask[2], mask[3]);
    for (unsigned i = 0; i < caps.size(); ++i) { if (enabled[i]) glEnable(caps[i]); else glDisable(caps[i]); }
  }
};

inline GLuint program(const char* fragment) {
  const char* vertex = R"GLSL(#version 300 es
precision highp float;
out vec2 qt_TexCoord0;
void main() {
  vec2 uv = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));
  qt_TexCoord0 = uv;
  gl_Position = vec4(uv * 2.0 - 1.0, 0.0, 1.0);
})GLSL";
  GLuint result = glCreateProgram();
  for (auto [type, source] : {std::pair{GL_VERTEX_SHADER, vertex}, std::pair{GL_FRAGMENT_SHADER, fragment}}) {
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &source, nullptr); glCompileShader(shader);
    GLint ok; glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (!ok) {
      char log[4096]{}; glGetShaderInfoLog(shader, sizeof(log), nullptr, log);
      glDeleteShader(shader); glDeleteProgram(result); throw std::runtime_error(log);
    }
    glAttachShader(result, shader); glDeleteShader(shader);
  }
  glLinkProgram(result);
  GLint ok; glGetProgramiv(result, GL_LINK_STATUS, &ok);
  if (!ok) {
    char log[4096]{}; glGetProgramInfoLog(result, sizeof(log), nullptr, log);
    glDeleteProgram(result); throw std::runtime_error(log);
  }
  return result;
}

struct Target {
  GLuint texture = 0, fbo = 0;
  int width = 0, height = 0;
  GLenum format = GL_RGBA8;
  void allocate(int w, int h, GLenum storage = GL_RGBA8) {
    if (width == w && height == h && format == storage) return;
    if (!texture) { glGenTextures(1, &texture); glGenFramebuffers(1, &fbo); }
    width = w; height = h; format = storage;
    glBindTexture(GL_TEXTURE_2D, texture);
    glTexImage2D(GL_TEXTURE_2D, 0, storage, w, h, 0, GL_RGBA,
                 storage == GL_RGBA16F ? GL_HALF_FLOAT : GL_UNSIGNED_BYTE, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, fbo);
    glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0);
    if (glCheckFramebufferStatus(GL_DRAW_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
      throw std::runtime_error("Liquid Glass framebuffer is incomplete");
  }
  void mipmaps() {
    glBindTexture(GL_TEXTURE_2D, texture); glGenerateMipmap(GL_TEXTURE_2D);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
  }
  void release() {
    glDeleteTextures(1, &texture); glDeleteFramebuffers(1, &fbo);
    texture = fbo = 0; width = height = 0;
  }
};

struct BlurRegion { int x, y, w, h; };

inline std::vector<BlurRegion> analysisRegions(Rect capture, const std::vector<Rect>& bodies,
                                             double scale, int width, int height, int verticalHalo) {
  std::vector<BlurRegion> regions;
  for (const auto& b : bodies) {
    const double x = std::lround((b.x - 28) * scale), y = std::lround((b.y - 28) * scale);
    const double w = std::lround((b.w + 56) * scale), h = std::lround((b.h + 56) * scale);
    // Ambient lighting reads the unrefracted position. Include bilinear support
    // and raster rounding; the horizontal pass also supplies vertical taps.
    int left = std::max(0, int(std::floor((x + 28 * scale - capture.x) * width / capture.w)) - 2);
    int top = std::max(0, int(std::floor((y + 28 * scale - capture.y) * height / capture.h)) - 2 - verticalHalo);
    int right = std::min(width, int(std::ceil((x + w - 28 * scale - capture.x) * width / capture.w)) + 2);
    int bottom = std::min(height, int(std::ceil((y + h - 28 * scale - capture.y) * height / capture.h)) + 2 + verticalHalo);
    if (right > left && bottom > top) regions.push_back({left, top, right - left, bottom - top});
  }
  // Coalesce overlapping footprints so adjoining panels do not repeat work.
  for (size_t i = 0; i < regions.size(); ++i) {
    for (size_t j = i + 1; j < regions.size();) {
      auto& a = regions[i]; const auto b = regions[j];
      if (a.x <= b.x + b.w && b.x <= a.x + a.w && a.y <= b.y + b.h && b.y <= a.y + a.h) {
        int right = std::max(a.x + a.w, b.x + b.w), bottom = std::max(a.y + a.h, b.y + b.h);
        a.x = std::min(a.x, b.x); a.y = std::min(a.y, b.y); a.w = right - a.x; a.h = bottom - a.y;
        regions.erase(regions.begin() + j); j = i + 1;
      } else ++j;
    }
  }
  return regions;
}

struct Renderer {
  GLuint glass = 0, blur = 0, vao = 0;
  GLuint linearHorizontal = 0, linearVertical = 0, pairedVertical = 0;
  Target sharp, horizontal, soft;
  std::array<GLuint, 8> queries{};
  std::array<bool, 8> pending{};
  PFNGLGETQUERYOBJECTUI64VEXTPROC queryResult = nullptr;
  unsigned queryIndex = 0;
  uint64_t frames = 0, samples = 0;
  double cpuTotal = 0, gpuTotal = 0, gpuMax = 0;
  float sharpAnisotropy = 4, maxAnisotropy = 1, appliedAnisotropy = 1;

  void initialize() {
    if (glass) return;
    glass = program(IndependentGlassShaders::materialSource);
    blur = program(IndependentGlassShaders::blurSource); glGenVertexArrays(1, &vao);
    std::string extensions(reinterpret_cast<const char*>(glGetString(GL_EXTENSIONS)));
    if (extensions.contains("GL_EXT_color_buffer_half_float") || extensions.contains("GL_EXT_color_buffer_float")) {
      linearHorizontal = program(IndependentGlassShaders::linearHorizontalSource);
      linearVertical = program(IndependentGlassShaders::linearVerticalSource);
      pairedVertical = program(IndependentGlassShaders::pairedVerticalSource);
    }
    if (extensions.contains("GL_EXT_texture_filter_anisotropic"))
      glGetFloatv(GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT, &maxAnisotropy);
    if (extensions.contains("GL_EXT_disjoint_timer_query")) {
      queryResult = reinterpret_cast<PFNGLGETQUERYOBJECTUI64VEXTPROC>(eglGetProcAddress("glGetQueryObjectui64vEXT"));
      if (queryResult) glGenQueries(queries.size(), queries.data());
    }
  }
  void release() {
    sharp.release(); horizontal.release(); soft.release();
    glDeleteProgram(glass); glDeleteProgram(blur); glDeleteVertexArrays(1, &vao);
    glDeleteProgram(linearHorizontal); glDeleteProgram(linearVertical); glDeleteProgram(pairedVertical);
    if (queryResult) glDeleteQueries(queries.size(), queries.data());
    glass = blur = vao = 0;
    linearHorizontal = linearVertical = pairedVertical = 0;
    maxAnisotropy = appliedAnisotropy = 1;
  }
  void texture(GLuint prog, const char* name, GLuint tex, int unit) {
    glActiveTexture(GL_TEXTURE0 + unit); glBindTexture(GL_TEXTURE_2D, tex);
    glUniform1i(glGetUniformLocation(prog, name), unit);
  }
  void one(GLuint p, const char* n, float v) { glUniform1f(glGetUniformLocation(p, n), v); }
  void two(GLuint p, const char* n, float x, float y) { glUniform2f(glGetUniformLocation(p, n), x, y); }

  void render(Rect capture, const std::vector<Rect>& bodies, double scale, double presence, bool soften, bool diffuse, const std::array<float, 4>& tint, double sceneWidth, double sceneHeight) {
    auto start = std::chrono::steady_clock::now();
    State state;
    initialize(); glBindVertexArray(vao);
    bool timed = false;
    if (queryResult) {
      if (pending[queryIndex]) {
        GLuint available; glGetQueryObjectuiv(queries[queryIndex], GL_QUERY_RESULT_AVAILABLE, &available);
        if (available) {
          GLuint64 ns; queryResult(queries[queryIndex], GL_QUERY_RESULT, &ns);
          GLint disjoint; glGetIntegerv(GL_GPU_DISJOINT_EXT, &disjoint);
          if (!disjoint) { double ms = ns / 1e6; gpuTotal += ms; gpuMax = std::max(gpuMax, ms); ++samples; }
          pending[queryIndex] = false;
        }
      }
      if (!pending[queryIndex]) { glBeginQuery(GL_TIME_ELAPSED_EXT, queries[queryIndex]); timed = true; }
    }
    struct QueryEnd {
      bool active;
      bool* pending;
      void finish() { if (active) { glEndQuery(GL_TIME_ELAPSED_EXT); *pending = true; active = false; } }
      ~QueryEnd() { finish(); }
    } queryEnd{timed, &pending[queryIndex]};
    int w = capture.w, h = capture.h;
    const bool linearBlur = diffuse && linearHorizontal;
    sharp.allocate(w, h);
    horizontal.allocate((w + 1) / 2, (h + 1) / 2, linearBlur ? GL_RGBA16F : GL_RGBA8);
    soft.allocate((w + 1) / 2, (h + 1) / 2);
    // Ordered GPU copy from this frame's already composed windows. No CPU pixels,
    // output screencopy, exported DMA buffer, or cross-process synchronization.
    glBindFramebuffer(GL_READ_FRAMEBUFFER, state.drawFB);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, sharp.fbo);
    glBlitFramebuffer(capture.x, capture.y, capture.x + w, capture.y + h, 0, 0, w, h, GL_COLOR_BUFFER_BIT, GL_NEAREST);
    glActiveTexture(GL_TEXTURE0); sharp.mipmaps();
    // Clear's approved AF4 source filter. Keep other clarity modes and the
    // broad analysis texture isotropic; unsupported hardware stays at AF1.
    const float anisotropy = !soften && !diffuse ? std::min(sharpAnisotropy, maxAnisotropy) : 1;
    if (anisotropy != appliedAnisotropy) {
      glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAX_ANISOTROPY_EXT, anisotropy);
      appliedAnisotropy = anisotropy;
    }
    const bool lightingOnly = !diffuse;
    auto drawAnalysis = [&](int verticalHalo) {
      if (!lightingOnly) { glDrawArrays(GL_TRIANGLES, 0, 3); return; }
      const auto regions = analysisRegions(capture, bodies, scale, soft.width, soft.height, verticalHalo);
      glEnable(GL_SCISSOR_TEST);
      for (const auto& r : regions) { glScissor(r.x, r.y, r.w, r.h); glDrawArrays(GL_TRIANGLES, 0, 3); }
      glDisable(GL_SCISSOR_TEST);
    };
    // Diffused keeps the intermediate in linear half-float precision, avoiding
    // an 8-bit rounding step and repeated transfer-function conversions.
    const GLuint hBlur = linearBlur ? linearHorizontal : blur;
    // At other scales the kernel taps are not adjacent texels: keep all 21.
    const GLuint vBlur = linearBlur ? (scale == 1 ? pairedVertical : linearVertical) : blur;
    glUseProgram(hBlur); one(hBlur, "qt_Opacity", 1);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, horizontal.fbo); glViewport(0, 0, horizontal.width, horizontal.height);
    texture(hBlur, "source", sharp.texture, 0); two(hBlur, "stepUV", scale / horizontal.width, 0);
    drawAnalysis(int(std::ceil(10 * scale)) + 2);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, soft.fbo); glViewport(0, 0, soft.width, soft.height);
    glUseProgram(vBlur); one(vBlur, "qt_Opacity", 1);
    texture(vBlur, "source", horizontal.texture, 0); two(vBlur, "stepUV", 0, scale / soft.height);
    drawAnalysis(0);
    if (lightingOnly) {
      // Clear and Soft use the soft buffer only for affine ambient lighting.
      // Its half-resolution source is magnified, so it never uses mip levels.
      glBindTexture(GL_TEXTURE_2D, soft.texture);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    } else soft.mipmaps();
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, state.drawFB); glUseProgram(glass);
    texture(glass, "backdrop", sharp.texture, 0); texture(glass, "softenedBackdrop", soft.texture, 1);
    two(glass, "backdropSize", w / scale, h / scale);
    one(glass, "qt_Opacity", 1); one(glass, "padding", 28); one(glass, "magnification", 0);
    one(glass, "diagnostic", 0); two(glass, "lightDirection", -.6, -.8);
    double reach = std::hypot(sceneWidth, sceneHeight) / 2;
    two(glass, "lightPosition", sceneWidth / 2 - .6 * reach - capture.x / scale,
        sceneHeight / 2 - .8 * reach - capture.y / scale);
    glEnable(GL_BLEND); glBlendEquation(GL_FUNC_ADD); glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
    for (const auto& b : bodies) {
      double strength = presence * b.opacity;
      double shorter = std::min(b.w, b.h), radius = std::min(56.0, shorter / 2);
      double t = std::clamp((shorter - 96) / 324, 0.0, 1.0), size = t * t * (3 - 2 * t);
      const int x = std::lround((b.x - 28) * scale), y = std::lround((b.y - 28) * scale);
      const int width = std::lround((b.w + 56) * scale), height = std::lround((b.h + 56) * scale);
      glViewport(x, y, width, height);
      // Match sample coordinates to the actual physical raster at fractional
      // scale, so zero-strength material is an exact identity even off-grid.
      two(glass, "bodySize", width / scale - 56, height / scale - 56);
      glUniform4f(glGetUniformLocation(glass, "sampleRect"), (x - capture.x) / scale,
                  (y - capture.y) / scale, width / scale, height / scale);
      one(glass, "cornerRadius", radius); one(glass, "edgeWidth", radius * (.38 + .44 * size));
      one(glass, "surfaceHeight", radius * (.5 + .18 * size)); one(glass, "thickness", radius * (.6 + 1.4 * size));
      one(glass, "crownHeight", shorter * .055 * size);
      // Soft uses the restrained local filter; Diffused uses only broad blur.
      // The broad analysis blur and averaged-color rim wash remain excluded.
      one(glass, "transmissionRoughness", soften ? .008 * strength : 0);
      one(glass, "interiorFiltering", 1);
      one(glass, "softness", 0); one(glass, "edgeSoftness", 0);
      one(glass, "lighting", strength); one(glass, "ambientReflection", 0);
      one(glass, "adaptation", 0); one(glass, "refraction", strength);
      one(glass, "diffusion", diffuse ? strength : 0);
      glUniform4f(glGetUniformLocation(glass, "tint"), tint[0], tint[1], tint[2], tint[3] * strength);
      one(glass, "shadowStrength", (.08 + .1 * size) * strength);
      glDrawArrays(GL_TRIANGLES, 0, 3);
    }
    queryEnd.finish();
    queryIndex = (queryIndex + 1) % queries.size();
    ++frames; cpuTotal += std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
  }
};
}
