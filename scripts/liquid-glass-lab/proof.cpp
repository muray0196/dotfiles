#include <QDir>
#include <QGuiApplication>
#include <QImage>
#include <QJsonDocument>
#include <QJsonObject>
#include <QOpenGLContext>
#include <QOpenGLExtraFunctions>
#include <QQuickItem>
#include <QQuickView>
#include <QQmlComponent>
#include <QJSValue>
#include <QSignalSpy>
#include <QSGRendererInterface>
#include <QTest>
#include <QFile>
#include <algorithm>
#include <cmath>
#include <iostream>
#include <mutex>
#include <memory>
#include <stdexcept>

namespace {
struct GraphicsInfo {
  std::mutex mutex;
  QString renderer;

  void observe() {
    std::lock_guard lock(mutex);
    auto* context = QOpenGLContext::currentContext();
    if (context && renderer.isEmpty())
      renderer = QString::fromLatin1(reinterpret_cast<const char*>(context->extraFunctions()->glGetString(GL_RENDERER)));
  }

  QString name() {
    std::lock_guard lock(mutex);
    return renderer;
  }
};

int checks = 0;
void require(bool condition, const char* description) {
  if (!condition) throw std::runtime_error(description);
  ++checks;
  std::cout << "ok  " << description << '\n';
}

QColor pixel(const QImage& image, const QQuickView& view, int x, int y) {
  const double scale = double(image.width()) / view.width();
  return image.pixelColor(int((x + 0.5) * scale), int((y + 0.5) * scale));
}

int difference(QColor a, QColor b) {
  return std::max({std::abs(a.red() - b.red()), std::abs(a.green() - b.green()), std::abs(a.blue() - b.blue())});
}

double meanDifference(const QImage& a, const QImage& b) {
  if (a.size() != b.size()) throw std::runtime_error("capture size changed unexpectedly");
  double sum = 0;
  for (int y = 0; y < a.height(); ++y)
    for (int x = 0; x < a.width(); ++x)
      sum += difference(a.pixelColor(x, y), b.pixelColor(x, y));
  return sum / (a.width() * a.height());
}

QImage capture(QQuickView& view) {
  view.update();
  QTest::qWait(100);
  QImage image = view.grabWindow();
  if (image.isNull()) throw std::runtime_error("GPU capture returned no pixels");
  return image;
}

QQuickItem* visualItem(QQuickItem* root, const QString& name) {
  if (root->objectName() == name) return root;
  for (auto* child : root->childItems())
    if (auto* found = visualItem(child, name)) return found;
  return nullptr;
}

void load(QQuickView& view, const QString& path, QSize size) {
  view.hide();
  view.setSource(QUrl());
  view.setMinimumSize(QSize(1, 1));
  view.setMaximumSize(QSize(8192, 8192));
  view.setSource(QUrl::fromLocalFile(path));
  view.setMinimumSize(size);
  view.setMaximumSize(size);
  view.resize(size);
  if (view.status() == QQuickView::Error) throw std::runtime_error("QML failed to load");
  view.show();
  if (!QTest::qWaitForWindowExposed(&view, 5000)) throw std::runtime_error("test window was not exposed");
  QTest::qWait(200);
  if (view.size() != size) throw std::runtime_error("compositor changed the fixture size; use a floating proof window");
}
}

int main(int argc, char** argv) {
  QGuiApplication app(argc, argv);
  QGuiApplication::setDesktopFileName("liquid-glass-lab-proof");
  if (argc != 3) {
    std::cerr << "Usage: proof BUILD_DIRECTORY OUTPUT_DIRECTORY\n";
    return 2;
  }
  const QDir build(QString::fromLocal8Bit(argv[1]));
  const QDir output(QString::fromLocal8Bit(argv[2]));
  QDir().mkpath(output.absolutePath());
  GraphicsInfo graphics;
  QQuickView view;
  QObject::connect(&view, &QQuickWindow::beforeRendering, &view, [&] { graphics.observe(); }, Qt::DirectConnection);
  view.setTitle("Liquid Glass — optical verification");
  view.setResizeMode(QQuickView::SizeRootObjectToView);
  try {
    load(view, build.filePath("TestScene.qml"), QSize(640, 420));
    auto* root = view.rootObject();
    auto set = [&](const char* name, QVariant value) {
      if (!root->setProperty(name, value)) throw std::runtime_error("missing test property");
    };
    set("showGlass", false);
    const QImage reference = capture(view);
    require(view.rendererInterface()->graphicsApi() != QSGRendererInterface::Software,
            "rendered with a graphics API, not Qt's software item renderer");
    require(std::abs(pixel(reference, view, 320, 210).red() - 115) < 3,
            "coordinate-encoded backdrop reached the render target");
    set("showGlass", true);
    const QImage identity = capture(view);
    const double identityError = meanDifference(reference, identity);
    require(identityError < 0.5, "zero-effect glass preserves backdrop alignment and color");

    set("optics", 1.0);
    const QImage refracted = capture(view);
    require(pixel(refracted, view, 135, 195).red() > pixel(reference, view, 135, 195).red() + 1,
            "left edge samples toward the interior");
    require(pixel(refracted, view, 428, 195).red() < pixel(reference, view, 428, 195).red() - 1,
            "right edge samples toward the interior");
    require(pixel(refracted, view, 280, 73).green() > pixel(reference, view, 280, 73).green() + 1,
            "top edge samples toward the interior");
    require(difference(pixel(refracted, view, 280, 195), pixel(reference, view, 280, 195)) <= 1,
            "flat center has no unintended displacement");
    require(difference(pixel(refracted, view, 95, 195), pixel(reference, view, 95, 195)) <= 1,
            "glass does not alter pixels outside its shape");

    set("presence", 0.0);
    set("transmissionRoughness", 0.008);
    set("softness", 1.0);
    set("edgeSoftness", 1.0);
    set("ambientReflection", 1.0);
    set("lighting", 1.0);
    set("adaptation", 1.0);
    require(meanDifference(reference, capture(view)) < 0.5,
            "zero optical presence preserves the source with all effects enabled");
    set("presence", 1.0);
    set("transmissionRoughness", 0.0);
    set("softness", 0.0);
    set("edgeSoftness", 0.0);
    set("ambientReflection", 0.0);
    set("lighting", 0.0);
    set("adaptation", 0.0);

    set("optics", 0.0);
    set("glassX", 230.5);
    set("glassY", 110.25);
    set("glassWidth", 250.0);
    set("glassHeight", 166.0);
    require(meanDifference(reference, capture(view)) < 0.5,
            "fractional movement and resizing preserve source coordinates");
    set("glassX", 132.0);
    set("glassY", 70.0);
    set("glassWidth", 300.0);
    set("glassHeight", 250.0);
    set("optics", 1.0);
    set("phase", 1.0);
    const QImage advanced = capture(view);
    require(pixel(advanced, view, 280, 195).blue() - pixel(refracted, view, 280, 195).blue() >= 49,
            "stationary glass receives a changed background frame");
    for (int i = 0; i < 4; ++i) {
      set("phase", i % 2 == 0 ? 0.3 : 0.8);
      capture(view);
    }
    set("phase", 0.0);
    require(meanDifference(refracted, capture(view)) < 0.5,
            "repeated updates do not accumulate glass feedback");

    set("pattern", 1.0);
    set("optics", 0.0);
    const QImage checker = capture(view);
    set("softness", 1.0);
    const QImage softened = capture(view);
    double sharpContrast = 0, softContrast = 0;
    for (int y = 130; y < 250; ++y) {
      for (int x = 190; x < 365; ++x) {
        sharpContrast += difference(pixel(checker, view, x, y), pixel(checker, view, x + 1, y));
        softContrast += difference(pixel(softened, view, x, y), pixel(softened, view, x + 1, y));
      }
    }
    require(softContrast < sharpContrast * 0.2, "shared blur reduces high-frequency backdrop contrast");

    set("softness", 0.0);
    set("backingDistance", 100.0);
    set("transmissionRoughness", 0.008);
    set("filterInterior", false);
    const QImage narrowChecker = capture(view);
    narrowChecker.save(output.filePath("narrow-checker.png"));
    double narrowContrast = 0;
    for (int y = 130; y < 250; ++y)
      for (int x = 190; x < 365; ++x)
        narrowContrast += difference(pixel(narrowChecker, view, x, y), pixel(narrowChecker, view, x + 1, y));
    require(narrowContrast < sharpContrast * 0.85 && narrowContrast > sharpContrast * 0.3,
            "narrow transmission softens fine detail while retaining its structure");
    set("filterInterior", true);
    const QImage interiorChecker = capture(view);
    interiorChecker.save(output.filePath("interior-checker.png"));
    double filteredMean = 0, sourceMean = 0, interiorContrast = 0;
    int corePixels = 0;
    for (int y = 130; y < 250; ++y) {
      for (int x = 190; x < 365; ++x) {
        filteredMean += pixel(interiorChecker, view, x, y).red();
        sourceMean += pixel(checker, view, x, y).red();
        interiorContrast += difference(pixel(interiorChecker, view, x, y),
                                       pixel(interiorChecker, view, x + 1, y));
        ++corePixels;
      }
    }
    require(std::abs(filteredMean - sourceMean) / corePixels < 1.5,
            "interior filtering preserves the displayed mean of bright and dark detail");
    require(interiorContrast < narrowContrast && interiorContrast > sharpContrast * 0.1,
            "interior filtering softens fine detail without erasing its structure");
    // Compare rendered pixels against the retained checkpoint kernel, including
    // refraction and light. All straight edges and curved corners are protected.
    set("optics", 1.0);
    set("lighting", 1.0);
    set("filterInterior", false);
    const QImage committedRim = capture(view);
    set("filterInterior", true);
    const QImage filteredRim = capture(view);
    int rimDifference = 0;
    for (int y = 70; y < 320; ++y) {
      for (int x = 132; x < 432; ++x) {
        const double qx = std::abs(x + 0.5 - 282) - 110;
        const double qy = std::abs(y + 0.5 - 195) - 85;
        const double distance = std::hypot(std::max(qx, 0.0), std::max(qy, 0.0))
                                + std::min(std::max(qx, qy), 0.0) - 40;
        if (distance >= -24 && distance <= 0)
          rimDifference = std::max(rimDifference, difference(pixel(committedRim, view, x, y),
                                                            pixel(filteredRim, view, x, y)));
      }
    }
    require(rimDifference <= 1, "interior filtering preserves committed edge and corner pixels");
    set("optics", 0.0);
    set("lighting", 0.0);
    // A bright neighbor must not lift the interior of a dark region. Test the
    // bounded footprint at a deliberately long optical path as well as color.
    set("backingDistance", 500.0);
    for (int pattern : {4, 5}) {
      set("pattern", pattern);
      set("transmissionRoughness", 0.0);
      const QImage unfiltered = capture(view);
      set("transmissionRoughness", 0.008);
      const QImage filtered = capture(view);
      bool preservesRegions = true;
      for (int x = 270; x < 375; ++x) {
        if (std::abs(x - 320) < 8) continue;
        preservesRegions &= difference(pixel(unfiltered, view, x, 195), pixel(filtered, view, x, 195)) <= 1;
      }
      require(preservesRegions, pattern == 4
              ? "narrow transmission keeps dark and bright regions intact without a broad halo"
              : "narrow transmission preserves saturated orange and blue regions");
      require(meanDifference(unfiltered.copy(0, 0, 90, unfiltered.height()),
                             filtered.copy(0, 0, 90, filtered.height())) < 0.5,
              "narrow transmission leaves the background outside the glass unchanged");
    }
    set("backingDistance", 36.0);
    set("transmissionRoughness", 0.0);

    set("pattern", 0.0);
    set("softness", 0.0);
    set("foreground", true);
    const QImage textReference = capture(view);
    set("optics", 1.0);
    set("softness", 1.0);
    set("transmissionRoughness", 0.008);
    set("lighting", 1.0);
    const QImage textGlass = capture(view);
    int whitePixels = 0, alteredText = 0;
    for (int y = 164; y < 204; ++y) {
      for (int x = 110; x < 420; ++x) {
        QColor c = pixel(textReference, view, x, y);
        if (c.red() > 250 && c.green() > 250 && c.blue() > 250) {
          ++whitePixels;
          alteredText += difference(c, pixel(textGlass, view, x, y)) > 1;
        }
      }
    }
    require(whitePixels > 100 && alteredText == 0, "foreground glyph pixels remain sharp and undisplaced");
    set("transmissionRoughness", 0.0);

    set("pattern", 2.0);
    set("phase", 0.1);
    set("inkProbe", true);
    require(pixel(capture(view), view, 460, 340).red() > 240,
            "label group chooses light ink from a dark sampled background");
    set("phase", 0.9);
    require(pixel(capture(view), view, 460, 340).red() < 40,
            "label group chooses dark ink when the sampled background becomes light");
    set("foreground", false);
    set("inkProbe", false);
    set("phase", 0.1);
    set("optics", 0.0);
    set("softness", 0.0);
    set("lightAngle", -2.35619449);
    const QImage litCorner = capture(view);
    set("lightAngle", -0.78539816);
    const QImage rotatedLight = capture(view);
    litCorner.save(output.filePath("light-corner.png"));
    rotatedLight.save(output.filePath("light-corner-rotated.png"));
    int highlightChange = 0;
    for (int y = 80; y < 86; ++y)
      for (int x = 142; x < 148; ++x)
        highlightChange = std::max(highlightChange,
          pixel(litCorner, view, x, y).red() - pixel(rotatedLight, view, x, y).red());
    require(highlightChange > 90,
            "a rotating light moves the concentrated highlight off the previous corner");
    // Six pixels inside this small corner, clear of the two-pixel core.
    require(pixel(litCorner, view, 148, 86).red() > pixel(rotatedLight, view, 148, 86).red() + 8,
            "directional illumination extends inward beyond the thin edge highlight");
    require(difference(pixel(litCorner, view, 280, 195), pixel(rotatedLight, view, 280, 195)) <= 1,
            "rim-light motion does not repaint the flat interior");

    set("lightAngle", -1.95);
    const QImage leftLight = capture(view);
    set("lightAngle", -1.3);
    const QImage rightLight = capture(view);
    require(pixel(leftLight, view, 190, 71).red() > pixel(leftLight, view, 370, 71).red() + 30
            && pixel(rightLight, view, 370, 71).red() > pixel(rightLight, view, 190, 71).red() + 30,
            "a highlight travels along a straight edge instead of lighting it uniformly");

    set("pattern", 3.0);
    set("ambientReflection", 1.0);
    set("phase", 0.0);
    const QImage warmSurroundings = capture(view);
    set("phase", 1.0);
    const QImage coolSurroundings = capture(view);
    warmSurroundings.save(output.filePath("ambient-warm.png"));
    coolSurroundings.save(output.filePath("ambient-cool.png"));
    require(pixel(warmSurroundings, view, 280, 80).red() > pixel(coolSurroundings, view, 280, 80).red() + 12
            && pixel(coolSurroundings, view, 280, 80).blue() > pixel(warmSurroundings, view, 280, 80).blue() + 12,
            "nearby content colors reflect into the curved face over an unchanged gray source");
    require(difference(pixel(warmSurroundings, view, 280, 195), pixel(coolSurroundings, view, 280, 195)) <= 1,
            "environment reflection leaves the flat center unchanged");
    set("ambientReflection", 0.0);
    const QImage coolUnreflected = capture(view);
    set("phase", 0.0);
    require(difference(pixel(coolUnreflected, view, 280, 80), pixel(capture(view), view, 280, 80)) <= 1,
            "disabling environment reflection removes the surrounding-color response");

    // The body lens must affect the former flat core without painting a veil
    // over the source or changing pixels outside the body.
    load(view, build.filePath("TestScene.qml"), QSize(640, 420));
    root = view.rootObject();
    set("glassX", 145.0);
    set("glassY", 60.0);
    set("glassWidth", 350.0);
    set("glassHeight", 300.0);
    set("glassRadius", 56.0);
    set("bevel", 43.0);
    set("surfaceHeight", 34.0);
    set("backingDistance", 100.0);
    set("optics", 1.0);
    const QImage flatBody = capture(view);
    flatBody.save(output.filePath("body-flat.png"));
    set("crownHeight", 18.0);
    const QImage curvedBody = capture(view);
    curvedBody.save(output.filePath("body-lens.png"));
    require(pixel(curvedBody, view, 260, 210).red() > pixel(flatBody, view, 260, 210).red() &&
            pixel(curvedBody, view, 380, 210).red() < pixel(flatBody, view, 380, 210).red(),
            "body curvature refracts the interior along the horizontal axis");
    require(pixel(curvedBody, view, 320, 150).green() > pixel(flatBody, view, 320, 150).green() &&
            pixel(curvedBody, view, 320, 270).green() < pixel(flatBody, view, 320, 270).green(),
            "body curvature refracts the interior along the vertical axis");
    require(difference(pixel(curvedBody, view, 320, 210), pixel(flatBody, view, 320, 210)) <= 1,
            "the body lens keeps its optical center aligned");
    require(meanDifference(curvedBody.copy(0, 0, 90, curvedBody.height()),
                           flatBody.copy(0, 0, 90, flatBody.height())) < 0.5,
            "body curvature leaves the outer background unchanged");
    bool smoothCore = true;
    for (int x = 205; x < 435; ++x) {
      const int step = pixel(curvedBody, view, x + 1, 210).red() - pixel(curvedBody, view, x, 210).red();
      smoothCore = smoothCore && step >= 0 && step <= 1;
    }
    require(smoothCore, "body curvature has no inverted or discontinuous horizontal core samples");
    set("presence", 0.0);
    const QImage absentCrown = capture(view);
    set("showGlass", false);
    require(meanDifference(absentCrown, capture(view)) < 0.5,
            "zero presence preserves the source with body curvature enabled");
    set("showGlass", true);
    set("presence", 1.0);
    set("crownHeight", 0.0);
    require(meanDifference(flatBody, capture(view)) < 0.5,
            "disabling body curvature restores the original optical profile");
    set("crownHeight", 18.0);
    set("pattern", 2);
    set("transmissionRoughness", 0.008);
    for (double level : {0.0, 0.35, 1.0}) {
      set("phase", level);
      set("showGlass", false);
      const QImage uniform = capture(view);
      set("showGlass", true);
      require(meanDifference(uniform, capture(view)) < 0.5,
              "body curvature and narrow transmission preserve uniform black, gray, and white");
    }

    load(view, build.filePath("Playground.qml"), QSize(1120, 800));
    root = view.rootObject();
    set("showContent", false);
    set("background", 3);
    auto playgroundShot = [&]() {
      const QImage frame = capture(view);
      const double scale = double(frame.width()) / view.width();
      return frame.copy(QRectF(20 * scale, 180 * scale, 1080 * scale, 464 * scale).toAlignedRect());
    };
    auto clickPlayground = [&](const QString& name) {
      auto* button = visualItem(root, name);
      if (!button) throw std::runtime_error("missing playground control: " + name.toStdString());
      QTest::mouseClick(&view, Qt::LeftButton, Qt::NoModifier,
                       button->mapToScene(QPointF(button->width() / 2, button->height() / 2)).toPoint());
      QTest::qWait(100);
    };
    const char* inherited[] = {"edgeWidth", "surfaceHeight", "thickness", "crownHeight", "magnification",
                              "refraction", "lighting", "ambientReflection", "adaptation", "shadowStrength"};
    QQmlComponent defaultGlass(view.engine(), QUrl::fromLocalFile(build.filePath("Glass.qml")));
    for (int shape = 0; shape < 6; ++shape) {
      clickPlayground(QString("shapeButton%1").arg(shape));
      require(root->property("shape").toInt() == shape, "shape button selects its playground geometry");
      const QImage geometryShot = capture(view);
      geometryShot.save(output.filePath(QString("playground-shape-%1.png").arg(shape)));
      for (int index = 0; index < (shape == 5 ? 3 : 1); ++index) {
        auto* sample = visualItem(root, QString("playgroundGlass%1").arg(index));
        require(sample != nullptr, "playground instantiates each requested surface");
        QVariantMap inputs;
        for (const char* name : {"width", "height", "radius", "backdrop", "softenedBackdrop", "backdropSize", "backdropPosition"})
          inputs.insert(QString::fromLatin1(name), sample->property(name));
        std::unique_ptr<QObject> defaults(defaultGlass.createWithInitialProperties(inputs));
        require(defaults != nullptr, "shared Glass component provides the comparison defaults");
        bool same = true;
        for (const char* name : inherited)
          same &= std::abs(sample->property(name).toDouble() - defaults->property(name).toDouble()) < 0.00001;
        require(same, "shape inherits current optics without a tuned material profile");
        const auto* shader = sample->findChild<QQuickItem*>("glassShader");
        require(shader && QUrl::fromLocalFile(build.filePath("Glass.qml"))
                              .resolved(shader->property("fragmentShader").toUrl()).toLocalFile() == build.filePath("glass.frag.qsb"),
                "playground surface renders the shared glass shader");
      }
    }
    set("shape", 2);
    QTest::qWait(100);
    auto* sample = visualItem(root, "playgroundGlass0");
    QVariantList optics;
    for (const char* name : inherited) optics.append(sample->property(name));
    for (int background = 0; background < 8; ++background) {
      clickPlayground(QString("backgroundButton%1").arg(background));
      require(root->property("background").toInt() == background, "background button selects its source");
      QVariantList next;
      for (const char* name : inherited) next.append(sample->property(name));
      require(next == optics, "background selection leaves optical parameters unchanged");
      set("compare", true);
      const QImage comparison = playgroundShot();
      sample->setVisible(false);
      require(meanDifference(comparison, playgroundShot()) < 0.5, "Compare exposes the exact unfiltered background");
      sample->setVisible(true);
      set("compare", false);
    }
    set("background", 3);
    require(root->property("clarity").toInt() == 1 && root->property("tint").toInt() == 0,
            "playground defaults to gently filtered Soft with tint Off");
    const QImage clearPlayground = playgroundShot();
    clickPlayground("clarityButton0");
    const QImage sharpPlayground = playgroundShot();
    require(sample->property("transmissionRoughness").toDouble() == 0
            && meanDifference(clearPlayground, sharpPlayground) > 0.01,
            "Clear retains full detail and Soft uses the existing narrow filter");
    const auto* specimenForCore = sample->parentItem();
    const QImage defaultFrame = capture(view);
    const double imageScale = double(defaultFrame.width()) / view.width();
    const QPointF origin = specimenForCore->mapToScene(QPointF(70, 70));
    const QRect clearCore = QRectF(origin.x() * imageScale, origin.y() * imageScale,
                                  (sample->width() - 140) * imageScale,
                                  (sample->height() - 140) * imageScale).toAlignedRect();
    sample->setProperty("refraction", 0.0);
    sample->setProperty("lighting", 0.0);
    const QImage defaultCore = capture(view).copy(clearCore);
    sample->setVisible(false);
    const QImage sourceCore = capture(view).copy(clearCore);
    require(meanDifference(sourceCore, defaultCore) < 0.5,
            "Clear preserves source detail without added blur or a body veil");
    sample->setVisible(true);
    sample->setProperty("refraction", 1.0);
    sample->setProperty("lighting", 1.0);
    const auto tintPresets = root->property("tintPresets").value<QJSValue>().toVariant().toList();
    QFile paletteFile(build.filePath("tints.json"));
    if (!paletteFile.open(QIODevice::ReadOnly)) throw std::runtime_error("missing shared tint palette");
    const auto palette = QJsonDocument::fromJson(paletteFile.readAll()).object();
    require(tintPresets.size() == 8 && palette.size() == 8,
            "palette contains Off, Black, White, and five colors");
    for (int clarity = 0; clarity < 3; ++clarity) {
      clickPlayground(QString("clarityButton%1").arg(clarity));
      const QImage natural = playgroundShot();
      for (int tint = 0; tint < tintPresets.size(); ++tint) {
        clickPlayground(QString("tintButton%1").arg(tint));
        const auto entry = tintPresets[tint].toMap();
        const QString name = entry["name"].toString();
        require(sample->property("tintColor").value<QColor>() == QColor(palette[name].toString())
                && root->property("tint").toInt() == tint && root->property("clarity").toInt() == clarity,
                "tint button selects the shared color without changing clarity");
        require(sample->property("transmissionRoughness").toDouble() == (clarity == 1 ? 0.008 : 0)
                && sample->property("diffusion").toDouble() == (clarity == 2 ? 1 : 0),
                "tint never changes or stacks the smoothing filters");
        if (tint) require(meanDifference(natural, playgroundShot()) > 1, "each tint visibly colors every clarity");
        set("compare", true);
        const QImage absent = playgroundShot();
        sample->setVisible(false);
        require(meanDifference(absent, playgroundShot()) < 0.5,
                "every clarity and tint combination dissolves to the exact source");
        sample->setVisible(true);
        set("compare", false);
        QVariantList currentOptics;
        for (const char* property : inherited) currentOptics.append(sample->property(property));
        require(currentOptics == optics, "tint leaves geometry and lighting settings unchanged");
        clickPlayground("tintButton0");
        require(meanDifference(natural, playgroundShot()) < 0.05,
                "Tint Off restores the same clarity without residual color");
      }
    }
    clickPlayground("tintButton3");
    clickPlayground("clarityButton1");
    require(root->property("tint").toInt() == 3, "changing clarity preserves the chosen tint");
    clickPlayground("tintButton0");
    require(meanDifference(clearPlayground, playgroundShot()) < 0.05,
            "clarity and tint round trips restore the same Soft render");
    set("background", 6);
    const QPoint tintCenter = sample->mapToScene(QPointF(sample->width() / 2, sample->height() / 2)).toPoint();
    for (int tint = 0; tint < tintPresets.size(); ++tint) {
      set("tint", tint);
      const QColor color = sample->property("tintColor").value<QColor>();
      const QColor actual = pixel(capture(view), view, tintCenter.x(), tintCenter.y());
      const QColor expected = QColor::fromRgbF(1 - color.alphaF() + color.alphaF() * color.redF(),
                                              1 - color.alphaF() + color.alphaF() * color.greenF(),
                                              1 - color.alphaF() + color.alphaF() * color.blueF());
      require(difference(actual, expected) <= 1,
              "flat white reveals the exact palette hue and opacity without premultiplied-color errors");
    }
    set("tint", 0);
    set("background", 3);
    auto* specimen = sample->parentItem();
    const QPointF initial = specimen->position();
    const QPoint playgroundCenter = specimen->mapToScene(QPointF(specimen->width() / 2, specimen->height() / 2)).toPoint();
    QTest::mousePress(&view, Qt::LeftButton, Qt::NoModifier, playgroundCenter);
    QTest::mouseMove(&view, playgroundCenter + QPoint(72, 18), 100);
    QTest::mouseRelease(&view, Qt::LeftButton, Qt::NoModifier, playgroundCenter + QPoint(72, 18));
    require(specimen->x() > initial.x() + 50 && meanDifference(clearPlayground, playgroundShot()) > 0.1,
            "dragging changes backdrop sampling at the actual surface position");
    root->forceActiveFocus(Qt::OtherFocusReason);
    QTest::keyClick(&view, Qt::Key_R);
    require(specimen->position() == initial && meanDifference(clearPlayground, playgroundShot()) < 0.05,
            "Recenter restores geometry and source alignment");
    set("background", 0);
    set("showContent", true);
    set("shape", 5);
    for (int clarity = 0; clarity < 3; ++clarity) {
      set("clarity", clarity);
      for (int tint = 0; tint < tintPresets.size(); ++tint) {
        set("tint", tint);
        capture(view).save(output.filePath(QString("playground-%1-%2.png").arg(clarity).arg(tintPresets[tint].toMap()["name"].toString())));
      }
    }
    set("clarity", 1);
    set("tint", 0);
    capture(view).save(output.filePath("playground.png"));
    QSignalSpy closeRequested(root, SIGNAL(closeRequested()));
    clickPlayground("closeButton");
    require(closeRequested.count() == 1, "Close requests exit from the playground host");

    QJsonObject result{{"checks", checks}, {"identity_mean_error_255", identityError},
                       {"blur_contrast_ratio", softContrast / sharpContrast},
                       {"narrow_contrast_ratio", narrowContrast / sharpContrast},
                       {"foreground_pixels_checked", whitePixels},
                       {"device_pixel_ratio", view.devicePixelRatio()},
                       {"graphics_api", int(view.rendererInterface()->graphicsApi())},
                       {"renderer", graphics.name()},
                       {"gpu_timing_measured", false},
                       {"native_apple_comparison", false}, {"desktop_backdrop", false}};
    QFile json(output.filePath("results.json"));
    if (!json.open(QIODevice::WriteOnly)) throw std::runtime_error("could not save results");
    json.write(QJsonDocument(result).toJson());
    std::cout << "PASS " << checks << " checks; evidence: " << output.absolutePath().toStdString() << '\n';
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "FAIL " << error.what() << '\n';
    return 1;
  }
}
