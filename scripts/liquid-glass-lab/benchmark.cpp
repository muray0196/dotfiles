// Offscreen measurement of the actual desktop renderer, on an explicit EGL device.
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <QImage>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPainter>
#include <QFont>
#include <QGuiApplication>
#include <iostream>
#include <thread>
#include "desktop-gpu.hpp"

int main(int argc, char** argv) {
  QGuiApplication app(argc, argv);
  if (argc == 4 && std::string(argv[1]) == "compare") {
    QImage a(argv[2]), b(argv[3]);
    if (a.isNull() || b.isNull()) return 2;
    b = b.scaled(a.size(), Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
    double total = 0, squared = 0, edgeSquared = 0, edgeCount = 0;
    int maximum = 0; uint64_t changed = 0;
    for (int y = 0; y < a.height(); ++y) for (int x = 0; x < a.width(); ++x) {
      bool edge = false;
      for (auto rect : {GlassGPU::Rect{100, 160, 520, 420}, {710, 240, 200, 200}, {650, 530, 280, 110}}) {
        double radius = std::min(56.0, std::min(rect.w, rect.h) / 2);
        double qx = std::abs((x + .5) * 1024 / a.width() - rect.x - rect.w / 2) - rect.w / 2 + radius;
        double qy = std::abs(768 - (y + .5) * 768 / a.height() - rect.y - rect.h / 2) - rect.h / 2 + radius;
        double distance = std::hypot(std::max(qx, 0.0), std::max(qy, 0.0)) + std::min(std::max(qx, qy), 0.0) - radius;
        edge |= distance < -2 && distance > -48;
      }
      const auto p = a.pixelColor(x, y), q = b.pixelColor(x, y);
      for (int delta : {abs(p.red() - q.red()), abs(p.green() - q.green()), abs(p.blue() - q.blue())}) {
        total += delta; squared += delta * delta; maximum = std::max(maximum, delta); changed += delta != 0;
        if (edge) { edgeSquared += delta * delta; ++edgeCount; }
      }
    }
    const double count = a.width() * a.height() * 3.0;
    std::cout << QJsonDocument(QJsonObject{{"mae", total / count}, {"rmse", std::sqrt(squared / count)},
                                         {"max", maximum}, {"changed_fraction", changed / count},
                                         {"edge_rmse", std::sqrt(edgeSquared / edgeCount)}})
                     .toJson(QJsonDocument::Compact).constData() << '\n';
    return 0;
  }
  if (argc != 9 && argc != 10) {
    std::cerr << "Usage: benchmark DEVICE IMAGE_OR_grid OUTPUT SCALE CLARITY ANISOTROPY FRAMES HZ [motion|animate]\n";
    return 2;
  }
  try {
    const int frames = std::stoi(argv[7]);
    const double scale = std::stod(argv[4]), hz = std::stod(argv[8]);
    const float anisotropy = std::stof(argv[6]);
    if (frames < 1 || frames > 10000 || scale < 1 || scale > 4 || hz < 0 || hz > 240 || anisotropy < 1)
      throw std::runtime_error("Invalid benchmark parameters");
    const std::string clarity = argv[5];
    const std::string movement = argc == 10 ? argv[9] : "still";
    if (movement != "still" && movement != "motion" && movement != "animate")
      throw std::runtime_error("Invalid motion mode");
    const bool motion = movement != "still", saveFrames = movement == "motion";
    if (clarity != "clear" && clarity != "soft" && clarity != "diffused")
      throw std::runtime_error("Invalid clarity");
    auto devices = reinterpret_cast<PFNEGLQUERYDEVICESEXTPROC>(eglGetProcAddress("eglQueryDevicesEXT"));
    auto deviceString = reinterpret_cast<PFNEGLQUERYDEVICESTRINGEXTPROC>(eglGetProcAddress("eglQueryDeviceStringEXT"));
    auto platform = reinterpret_cast<PFNEGLGETPLATFORMDISPLAYEXTPROC>(eglGetProcAddress("eglGetPlatformDisplayEXT"));
    if (!devices || !deviceString || !platform) throw std::runtime_error("EGL device selection unavailable");
    EGLDeviceEXT list[16]; EGLint count = 0;
    if (!devices(16, list, &count)) throw std::runtime_error("EGL device enumeration failed");
    EGLDisplay display = EGL_NO_DISPLAY;
    for (int i = 0; i < count; ++i) {
      const char* node = deviceString(list[i], EGL_DRM_RENDER_NODE_FILE_EXT);
      if (node && std::string(node) == argv[1]) display = platform(EGL_PLATFORM_DEVICE_EXT, list[i], nullptr);
    }
    if (display == EGL_NO_DISPLAY || !eglInitialize(display, nullptr, nullptr))
      throw std::runtime_error("Requested GPU is unavailable; refusing another device");
    eglBindAPI(EGL_OPENGL_ES_API);
    const EGLint attributes[] = {EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
                                EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_NONE};
    EGLConfig config; EGLint configs;
    if (!eglChooseConfig(display, attributes, &config, 1, &configs) || !configs)
      throw std::runtime_error("No GLES3 EGL config");
    const EGLint contextAttributes[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
    EGLContext context = eglCreateContext(display, config, EGL_NO_CONTEXT, contextAttributes);
    const EGLint surfaceAttributes[] = {EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE};
    EGLSurface surface = eglCreatePbufferSurface(display, config, surfaceAttributes);
    if (!eglMakeCurrent(display, surface, surface, context)) throw std::runtime_error("EGL make-current failed");
    const std::string extensions(reinterpret_cast<const char*>(glGetString(GL_EXTENSIONS)));
    if (!extensions.contains("GL_EXT_disjoint_timer_query")) throw std::runtime_error("GPU timers unavailable");
    auto queryResult = reinterpret_cast<PFNGLGETQUERYOBJECTUI64VEXTPROC>(eglGetProcAddress("glGetQueryObjectui64vEXT"));
    if (!queryResult) throw std::runtime_error("GPU timer entry point unavailable");
    if (anisotropy > 1 && !extensions.contains("GL_EXT_texture_filter_anisotropic"))
      throw std::runtime_error("Anisotropic filtering unavailable");
    GLfloat maxAnisotropy = 1;
    if (extensions.contains("GL_EXT_texture_filter_anisotropic"))
      glGetFloatv(GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT, &maxAnisotropy);
    if (anisotropy > maxAnisotropy) throw std::runtime_error("Requested anisotropy exceeds GPU support");

    const int w = std::lround(1024 * scale), h = std::lround(768 * scale);
    QImage source(1024, 768, QImage::Format_RGBA8888);
    const QString input = argv[2];
    if (input == "grid") {
      source.fill(QColor(32, 38, 48));
      QPainter painter(&source);
      for (int y = 0; y < 768; y += 4)
        for (int x = 0; x < 1024; x += 4)
          painter.fillRect(x, y, 4, 4, ((x + y) / 4) % 2 ? QColor(215, 220, 230) : QColor(35, 42, 55));
      painter.fillRect(80, 190, 860, 80, QColor(240, 242, 248));
      painter.setPen(QColor(18, 25, 38)); painter.setFont(QFont("DejaVu Sans", 16));
      painter.drawText(95, 222, "Liquid Glass — fine type / 0123456789 / curved edges");
      painter.drawText(95, 250, "Full resolution · bilinear + trilinear · texture footprint");
    } else {
      QImage image(input);
      if (image.isNull()) throw std::runtime_error("Cannot load source image");
      source = image.scaled(1024, 768, Qt::IgnoreAspectRatio, Qt::SmoothTransformation).convertToFormat(QImage::Format_RGBA8888);
    }
    source = source.scaled(w, h, Qt::IgnoreAspectRatio, Qt::SmoothTransformation).flipped(Qt::Vertical);
    GlassGPU::Target background, screen;
    background.allocate(w, h); screen.allocate(w, h);
    glBindTexture(GL_TEXTURE_2D, background.texture);
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, source.constBits());
    GlassGPU::Renderer renderer;
    renderer.sharpAnisotropy = anisotropy;
    renderer.initialize();
    // Use an external query per pass, excluding fixture reset, readback and waits.
    if (renderer.queryResult) glDeleteQueries(renderer.queries.size(), renderer.queries.data());
    renderer.queryResult = nullptr;
    const std::vector<GlassGPU::Rect> bodies{{100, 160, 520, 420}, {710, 240, 200, 200}, {650, 530, 280, 110}};
    GLuint copy = GlassGPU::program(R"GLSL(#version 300 es
precision highp float;
in vec2 qt_TexCoord0;
out vec4 fragColor;
uniform sampler2D source;
uniform float phase;
void main() { fragColor = texture(source, qt_TexCoord0 + vec2(phase, 0.0)); }
)GLSL");
    float phase = 0;
    auto reset = [&] {
      glDisable(GL_BLEND); glDisable(GL_SCISSOR_TEST);
      glBindFramebuffer(GL_READ_FRAMEBUFFER, background.fbo);
      glBindFramebuffer(GL_DRAW_FRAMEBUFFER, screen.fbo);
      if (motion) {
        glViewport(0, 0, w, h); glBindVertexArray(renderer.vao); glUseProgram(copy);
        renderer.texture(copy, "source", background.texture, 0); renderer.one(copy, "phase", phase);
        glDrawArrays(GL_TRIANGLES, 0, 3);
      } else glBlitFramebuffer(0, 0, w, h, 0, 0, w, h, GL_COLOR_BUFFER_BIT, GL_NEAREST);
    };
    auto draw = [&] { renderer.render({0, 0, double(w), double(h)}, bodies, scale, 1,
                                     clarity == "soft", clarity == "diffused", {}, 1024, 768); };
    for (int i = 0; i < 48; ++i) { reset(); draw(); }
    glFinish();
    GLint disjoint; glGetIntegerv(GL_GPU_DISJOINT_EXT, &disjoint);
    std::vector<GLuint> queries(frames); glGenQueries(frames, queries.data());
    const double cpuBefore = renderer.cpuTotal;
    auto start = std::chrono::steady_clock::now();
    for (int i = 0; i < frames; ++i) {
      phase = float(i) * .25f / w;
      reset(); glBeginQuery(GL_TIME_ELAPSED_EXT, queries[i]); draw(); glEndQuery(GL_TIME_ELAPSED_EXT);
      if (saveFrames) {
        QImage shot(w, h, QImage::Format_RGBA8888);
        glBindFramebuffer(GL_READ_FRAMEBUFFER, screen.fbo);
        glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, shot.bits());
        if (!shot.flipped(Qt::Vertical).save(QString("%1-%2.png").arg(argv[3]).arg(i, 4, 10, QChar('0'))))
          throw std::runtime_error("Motion frame write failed");
      }
      if (hz > 0) {
        glFlush();
        std::this_thread::sleep_until(start + std::chrono::duration<double>((i + 1) / hz));
      }
    }
    glFinish();
    const double elapsed = std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
    glGetIntegerv(GL_GPU_DISJOINT_EXT, &disjoint);
    if (disjoint) throw std::runtime_error("Disjoint GPU timer sample; rerun measurement");
    std::vector<double> times;
    double total = 0;
    for (auto query : queries) {
      GLuint64 ns; queryResult(query, GL_QUERY_RESULT, &ns);
      times.push_back(ns / 1e6); total += times.back();
    }
    std::sort(times.begin(), times.end());
    QImage result(w, h, QImage::Format_RGBA8888);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, screen.fbo);
    glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, result.bits());
    if (!result.flipped(Qt::Vertical).save(QString(argv[3]) + ".png")) throw std::runtime_error("PNG write failed");
    if (glGetError() != GL_NO_ERROR) throw std::runtime_error("OpenGL error during benchmark");
    QJsonObject report{{"renderer", reinterpret_cast<const char*>(glGetString(GL_RENDERER))},
                       {"version", reinterpret_cast<const char*>(glGetString(GL_VERSION))}, {"device", argv[1]},
                       {"clarity", argv[5]}, {"scale", scale}, {"anisotropy", anisotropy},
                       {"max_anisotropy", maxAnisotropy}, {"applied_anisotropy", renderer.appliedAnisotropy},
                       {"frames", frames}, {"hz", hz}, {"motion", motion}, {"capture_frames", saveFrames},
                       {"elapsed_seconds", elapsed}, {"gpu_mean_ms", total / frames},
                       {"gpu_median_ms", times[times.size() / 2]}, {"gpu_p95_ms", times[std::min(times.size() - 1, times.size() * 95 / 100)]},
                       {"cpu_submit_ms", (renderer.cpuTotal - cpuBefore) / frames}};
    std::cout << QJsonDocument(report).toJson(QJsonDocument::Compact).constData() << '\n';
    glDeleteQueries(frames, queries.data()); glDeleteProgram(copy);
    renderer.release(); background.release(); screen.release();
    eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroySurface(display, surface); eglDestroyContext(display, context); eglTerminate(display);
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n'; return 1;
  }
}
