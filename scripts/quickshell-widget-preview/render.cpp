#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QQuickItem>
#include <QQuickItemGrabResult>
#include <QQuickView>
#include <QSignalSpy>
#include <QSGRendererInterface>
#include <QTest>
#include <iostream>
#include <stdexcept>

int main(int argc, char** argv) {
  QGuiApplication app(argc, argv);
  if (argc != 4) return 2;
  const QDir build(QString::fromLocal8Bit(argv[1]));
  const QDir output(build.filePath("captures"));
  QDir().mkpath(output.path());
  QQuickView view;
  view.setMinimumSize(QSize(1920, 1080));
  view.setMaximumSize(QSize(1920, 1080));
  view.setResizeMode(QQuickView::SizeRootObjectToView);
  view.resize(1920, 1080);
  view.setSource(QUrl::fromLocalFile(build.filePath("Composition.qml")));
  try {
    if (view.status() == QQuickView::Error) {
      for (const auto& error : view.errors()) std::cerr << error.toString().toStdString() << '\n';
      throw std::runtime_error("QML did not load");
    }
    view.show();
    QTest::qWait(700);
    if (view.rendererInterface()->graphicsApi() == QSGRendererInterface::Software)
      throw std::runtime_error("The material needs the real GPU shader renderer");
    auto* root = view.rootObject();
    auto set = [&](const char* key, QVariant value) {
      if (!root->setProperty(key, value)) throw std::runtime_error("missing scene property");
    };
    auto grab = [&]() {
      view.update(); QTest::qWait(120);
      auto image = view.grabWindow();
      if (image.size() != QSize(1920, 1080)) throw std::runtime_error("unexpected rendered size");
      return image;
    };
    auto* foreground = root->findChild<QQuickItem*>("widgetForeground");
    if (!foreground) throw std::runtime_error("foreground layer missing");
    auto grabForeground = [&]() {
      view.update(); QTest::qWait(120);
      const auto result = foreground->grabToImage();
      if (!result) throw std::runtime_error("foreground capture unavailable");
      QSignalSpy ready(result.data(), &QQuickItemGrabResult::ready);
      if (!ready.wait(3000) || result->image().size() != QSize(1920, 1080))
        throw std::runtime_error("foreground capture failed");
      return result->image();
    };
    QJsonArray files;
    auto save = [&](const QString& name) {
      // A still must show the final percentage, after the 220 ms bar transition.
      QTest::qWait(250);
      if (!grab().save(output.filePath(name + ".png"))) throw std::runtime_error("capture save failed");
      files.append(name + ".png");
    };
    set("showTools", false);
    save("soft-normal-no-controls");
    auto* provenance = root->findChild<QQuickItem*>("previewProvenance");
    if (!provenance || !provenance->isVisible()
        || !provenance->property("text").toString().contains("DEMONSTRATION DATA"))
      throw std::runtime_error("simulated Live state lost its demonstration label");
    set("showTools", true);
    for (int direction = 0; direction < 3; ++direction) {
      set("direction", direction);
      save(QString("direction-%1-soft").arg(direction));
    }
    set("direction", 0);
    for (int background = 0; background < 5; ++background) {
      set("background", background);
      save(QString("soft-%1").arg(QStringList{"flower", "desert", "bright", "dark", "detail"}[background]));
    }
    set("background", 2); set("darkText", true); save("soft-bright-dark-text");
    set("darkText", false);
    // Freeze data, change only the underlying imagery, and compare actual
    // foreground RGBA renders. This catches both ink flips and moving halos.
    int stableForegroundFrames = 0;
    QImage lightForeground;
    for (int palette = 0; palette < 2; ++palette) {
      set("darkText", palette == 1);
      set("background", 0); set("phase", 0.0);
      const auto reference = grabForeground();
      if (palette == 0) lightForeground = reference;
      else if (reference == lightForeground) throw std::runtime_error("foreground palette did not change");
      for (int background = 0; background < 5; ++background) {
        set("background", background);
        for (double phase : {0.0, 1.5, 3.0, 4.5}) {
          set("phase", phase);
          if (grabForeground() != reference) throw std::runtime_error("background changed foreground pixels");
          ++stableForegroundFrames;
        }
      }
    }
    set("darkText", false); set("phase", 0.0); set("background", 1);
    set("scenario", 1); save("soft-long-values");
    bool tooltipChecked = false;
    // Repeater delegates belong to the visual tree, but are not necessarily
    // QObject descendants. Inspect their labels as well as static children.
    QList<QQuickItem*> visualItems{root};
    for (qsizetype i = 0; i < visualItems.size(); ++i)
      visualItems.append(visualItems[i]->childItems());
    for (auto* item : visualItems) {
      if (!item->isVisible() || !item->property("truncated").toBool()) continue;
      const QPoint point = item->mapToScene(QPointF(item->width() / 2, item->height() / 2)).toPoint();
      QTest::mouseMove(&view, point);
      QTest::qWait(100);
      const auto expected = item->property("accessibleText").toString();
      bool revealed = root->property("detail").toString() == expected;
      for (auto* container : visualItems)
        revealed |= container->property("detail").toString() == expected;
      if (!expected.isEmpty() && revealed) {
        tooltipChecked = true;
        break;
      }
    }
    if (!tooltipChecked) throw std::runtime_error("long text could not be inspected on hover");
    QTest::mouseMove(&view, QPoint(960, 540));
    set("scenario", 2); save("soft-missing-data");
    set("scenario", 0); set("background", 0);
    auto* foregroundButton = root->findChild<QQuickItem*>("foregroundButton");
    if (!foregroundButton) throw std::runtime_error("foreground control missing");
    QTest::mouseClick(&view, Qt::LeftButton, Qt::NoModifier,
      foregroundButton->mapToScene(QPointF(foregroundButton->width() / 2, foregroundButton->height() / 2)).toPoint());
    if (!root->property("darkText").toBool()) throw std::runtime_error("foreground pointer click failed");
    root->forceActiveFocus();
    QTest::keyClick(&view, Qt::Key_F);
    if (root->property("darkText").toBool()) throw std::runtime_error("foreground key failed");
    QTest::keyClick(&view, Qt::Key_B);
    if (root->property("background").toInt() != 1) throw std::runtime_error("backdrop key failed");
    set("background", 0);
    QTest::keyClick(&view, Qt::Key_Space);
    QTest::qWait(250);
    if (root->property("phase").toDouble() <= 0) throw std::runtime_error("motion did not advance");
    QTest::keyClick(&view, Qt::Key_Space);
    set("phase", 0.0);
    QVariant audit;
    QMetaObject::invokeMethod(root, "audit", Q_RETURN_ARG(QVariant, audit));
    const auto geometry = QJsonObject::fromVariantMap(audit.toMap());
    for (const auto value : geometry) if (value.toDouble() > 1044) throw std::runtime_error("content extends past the glass");
    if (QString::fromLocal8Bit(argv[2]).size()) {
      QFile snapshot(QString::fromLocal8Bit(argv[2]));
      if (!snapshot.open(QIODevice::ReadOnly)) throw std::runtime_error("snapshot unreadable");
      auto data = QJsonDocument::fromJson(snapshot.readAll()).object();
      data["frozen"] = true;
      set("readings", data.toVariantMap());
      QTest::qWait(2500);
      save("soft-collector-snapshot");
      set("darkText", true); save("soft-dark-text-collector-snapshot"); set("darkText", false);
      set("scenario", 2); set("scenario", 0);
    }
    if (QString::fromLocal8Bit(argv[3]) == "motion") {
      QProcess encoder;
      encoder.start("ffmpeg", {"-hide_banner", "-loglevel", "error", "-y", "-f", "rawvideo", "-pixel_format", "rgb24", "-video_size", "1920x1080", "-framerate", "20", "-i", "pipe:0", "-an", "-c:v", "libx264", "-crf", "19", "-pix_fmt", "yuv420p", "-movflags", "+faststart", output.filePath("soft-motion.mp4")});
      if (!encoder.waitForStarted()) throw std::runtime_error("ffmpeg unavailable");
      for (int frame = 0; frame < 120; ++frame) {
        set("background", frame < 60 ? 0 : 1);
        set("phase", (frame % 60) / 10.0);
        QMetaObject::invokeMethod(root, "updateDemo");
        auto image = grab().convertToFormat(QImage::Format_RGB888);
        if (frame % 30 == 0 && !image.save(output.filePath(QString("motion-phase-%1.png").arg(frame))))
          throw std::runtime_error("motion sample save failed");
        const auto size = image.sizeInBytes();
        if (encoder.write(reinterpret_cast<const char*>(image.constBits()), size) != size) throw std::runtime_error("encoder write failed");
        while (encoder.bytesToWrite() > 0) if (!encoder.waitForBytesWritten(10000)) throw std::runtime_error("encoder stalled");
      }
      encoder.closeWriteChannel();
      if (!encoder.waitForFinished(20000) || encoder.exitCode()) throw std::runtime_error(encoder.readAllStandardError().toStdString());
      files.append("soft-motion.mp4");
    }
    QFile report(output.filePath("results.json"));
    if (!report.open(QIODevice::WriteOnly)) throw std::runtime_error("report write failed");
    report.write(QJsonDocument(QJsonObject{{"size", QJsonArray{1920, 1080}}, {"files", files}, {"content_bottoms", geometry}, {"keyboard_and_motion", true}, {"pointer_and_overflow_inspection", tooltipChecked}, {"stable_foreground_raster_frames", stableForegroundFrames}, {"foreground_backdrop_sampling", false}, {"path", "Qt Quick owned scene; unchanged accepted material"}, {"real_time_benchmark", false}, {"normal_compositor_modified", false}}).toJson());
    std::cout << "Rendered " << files.size() << " artifacts to " << output.path().toStdString() << '\n';
    return 0;
  } catch (const std::exception& e) {
    std::cerr << "FAIL: " << e.what() << '\n';
    return 1;
  }
}
