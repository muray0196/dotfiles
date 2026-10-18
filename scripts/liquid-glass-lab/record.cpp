#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QImage>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QQuickItem>
#include <QQuickView>
#include <QTest>
#include <iostream>
#include <stdexcept>

// Render a bounded, repeatable motion cycle through the actual shader.
// This is an offline visual artifact, not a frame-pacing benchmark.
int main(int argc, char** argv) {
  QGuiApplication app(argc, argv);
  if (argc != 4) return 2;
  const QDir output(QString::fromLocal8Bit(argv[1]));
  const int pattern = QString::fromLocal8Bit(argv[2]).toInt();
  const QString name = QString::fromLocal8Bit(argv[3]);
  const QString stem = name + "-motion";
  try {
    QQuickView view;
    view.setTitle("Liquid Glass — recording motion study");
    view.setMinimumSize(QSize(1120, 760));
    view.setMaximumSize(QSize(1120, 760));
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    view.setSource(QUrl::fromLocalFile(output.filePath("Scene.qml")));
    if (view.status() == QQuickView::Error) throw std::runtime_error("QML load failed");
    auto* scene = view.rootObject();
    scene->setProperty("animated", false);
    scene->setProperty("pattern", pattern);
    scene->setProperty("phase", 0.0);
    view.show();
    if (!QTest::qWaitForWindowExposed(&view, 5000)) throw std::runtime_error("window not exposed");
    QTest::qWait(300);

    QProcess encoder;
    encoder.setProgram("ffmpeg");
    encoder.setArguments({"-hide_banner", "-loglevel", "error", "-y",
                         "-f", "rawvideo", "-pixel_format", "rgb24", "-video_size", "1120x760",
                         "-framerate", "30", "-i", "pipe:0", "-an", "-c:v", "libx264",
                         "-crf", "18", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
                         output.filePath(stem + ".mp4")});
    encoder.start();
    if (!encoder.waitForStarted()) throw std::runtime_error("ffmpeg not available");
    for (int frame = 0; frame < 180; ++frame) {
      scene->setProperty("phase", frame / 30.0);
      view.update();
      QTest::qWait(60);
      QImage image = view.grabWindow().convertToFormat(QImage::Format_RGB888);
      if (image.size() != QSize(1120, 760)) throw std::runtime_error("record at QT_SCALE_FACTOR=1");
      if (frame % 45 == 0 && !image.save(output.filePath(stem + QString("-%1.png").arg(frame))))
        throw std::runtime_error("snapshot write failed");
      const auto bytes = image.sizeInBytes();
      if (encoder.write(reinterpret_cast<const char*>(image.constBits()), bytes) != bytes)
        throw std::runtime_error("encoder write failed");
      while (encoder.bytesToWrite() > 0)
        if (!encoder.waitForBytesWritten(5000)) throw std::runtime_error("encoder stalled");
    }
    encoder.closeWriteChannel();
    if (!encoder.waitForFinished(10000) || encoder.exitCode() != 0)
      throw std::runtime_error(encoder.readAllStandardError().toStdString());
    auto* lens = scene->findChild<QQuickItem*>(pattern == 9 ? "sizeGlass" : pattern >= 6 ? "referenceGlass" : "lens");
    const QString source = pattern == 4 || pattern == 9 ? "user-supplied still image" :
                           pattern == 5 || pattern == 8 ? "WWDC desert still at 179.8 seconds" :
                           "procedural diagnostic background";
    const QString motion = pattern == 9 ? "growing and translating surface; geometry, optical depth, scattering and shadow respond to size"
      : pattern >= 6
      ? scene->findChild<QQuickItem*>("referenceStudy")->property("motionDescription").toString()
      : pattern == 4 ? "source translation; fixed lens geometry and optics"
                     : "source zoom; fixed lens geometry and optics";
    QJsonObject metadata{{"scene", name}, {"frames", 180}, {"frames_per_second", 30},
                         {"duration_seconds", 6}, {"source", source}, {"motion", motion},
                         {"real_time_benchmark", false}, {"apple_motion_reconstruction", false},
                         {"width", lens->width()}, {"body_height", lens->height()},
                         {"bevel", lens->property("edgeWidth").toDouble()},
                         {"height", lens->property("surfaceHeight").toDouble()},
                         {"backing_distance", lens->property("thickness").toDouble()}};
    QFile file(output.filePath(stem + ".json"));
    if (!file.open(QIODevice::WriteOnly)) throw std::runtime_error("metadata write failed");
    file.write(QJsonDocument(metadata).toJson());
    std::cout << "Recorded 6-second GPU-rendered study: "
              << output.filePath(stem + ".mp4").toStdString() << '\n';
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "FAIL " << error.what() << '\n';
    return 1;
  }
}
