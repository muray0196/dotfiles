#include <QDir>
#include <QGuiApplication>
#include <QImage>
#include <QJsonDocument>
#include <QJsonObject>
#include <QOpenGLContext>
#include <QOpenGLExtraFunctions>
#include <QQuickItem>
#include <QQuickView>
#include <QSGRendererInterface>
#include <QTest>
#include <QFile>
#include <algorithm>
#include <cmath>
#include <iostream>
#include <mutex>
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
    const QImage narrowChecker = capture(view);
    narrowChecker.save(output.filePath("narrow-checker.png"));
    double narrowContrast = 0;
    for (int y = 130; y < 250; ++y)
      for (int x = 190; x < 365; ++x)
        narrowContrast += difference(pixel(narrowChecker, view, x, y), pixel(narrowChecker, view, x + 1, y));
    require(narrowContrast < sharpContrast * 0.85 && narrowContrast > sharpContrast * 0.3,
            "narrow transmission softens fine detail while retaining its structure");
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

    load(view, build.filePath("Scene.qml"), QSize(1120, 760));
    root = view.rootObject();
    auto pressKey = [&](Qt::Key key) {
      // A separate desktop window can take activation during visual inspection.
      // Route synthetic input to the scene whose behavior is under test.
      root->forceActiveFocus(Qt::OtherFocusReason);
      QTest::keyClick(&view, key);
    };
    set("animated", false);
    set("pattern", 0);
    set("phase", 1.7);
    require(capture(view).save(output.filePath("color.png")), "saved color reference");
    pressKey(Qt::Key_2);
    require(root->property("pattern").toInt() == 1, "keyboard scene selection works");
    require(capture(view).save(output.filePath("grid.png")), "saved grid reference");

    QPoint center(20 + 718 + 92, 90 + 204 + 63);
    QTest::mouseMove(&view, center);
    QTest::mousePress(&view, Qt::LeftButton, Qt::NoModifier, center);
    QTest::qWait(210);
    auto* lens = root->findChild<QQuickItem*>("lens");
    require(lens && lens->width() > 198, "pointer press changes lens geometry");
    QTest::mouseMove(&view, center + QPoint(-90, 70), 40);
    QTest::qWait(100);
    require(std::abs(root->property("lensX").toDouble() - 628) < 2 &&
            std::abs(root->property("lensY").toDouble() - 274) < 2,
            "lens follows the pointer without an initial jump");
    QTest::mouseRelease(&view, Qt::LeftButton, Qt::NoModifier, center + QPoint(-90, 70));
    QTest::qWait(210);
    require(std::abs(lens->width() - 184) < 0.1, "lens returns to rest after release");
    set("pattern", 2);
    require(capture(view).save(output.filePath("type.png")), "saved text reference");
    set("pattern", 3);
    require(capture(view).save(output.filePath("split.png")), "saved light and dark split reference");
    set("dark", true);
    require(capture(view).save(output.filePath("contrast.png")), "saved dark contrast reference");
    set("dark", false);
    set("phase", 0.0);
    pressKey(Qt::Key_5);
    auto* flower = root->findChild<QQuickItem*>("flowerImage");
    auto* smallLens = root->findChild<QQuickItem*>("smallLens");
    const QImage flowerGlass = capture(view);
    require(root->property("pattern").toInt() == 4 && flower && flower->property("status").toInt() == 1,
            "Flower scene loads the supplied image through the real background pipeline");
    require(std::abs(lens->x() - 390) < 0.1 && std::abs(lens->y() - 185) < 0.1,
            "switching to Flower places the lens across the petal and sky boundary");
    require(flowerGlass.save(output.filePath("flower.png")), "saved flower lens reference");
    require(smallLens && smallLens->isVisible() && smallLens->width() < lens->width(),
            "Flower exposes both sizes against the same live source");
    pressKey(Qt::Key_G);
    QTest::qWait(180);
    const double forming = root->property("materialAmount").toDouble();
    require(forming > 0.02 && forming < 0.98 && lens->opacity() == 1.0,
            "Compare animates optical strength while keeping the glass item fully opaque");
    require(capture(view).save(output.filePath("flower-transition.png")), "saved optical transition reference");
    QTest::qWait(700);
    const QImage flowerBare = capture(view);
    require(flowerBare.save(output.filePath("flower-bare.png")), "saved unmodified flower reference");
    lens->setVisible(false);
    smallLens->setVisible(false);
    const QImage flowerHidden = capture(view);
    const double imageScale = double(flowerBare.width()) / view.width();
    const QRect stageRect = QRectF(20 * imageScale, 90 * imageScale,
                                   1080 * imageScale, 590 * imageScale).toAlignedRect();
    require(meanDifference(flowerBare.copy(stageRect), flowerHidden.copy(stageRect)) < 0.5,
            "both dissolved lenses equal the source with no residual rim or shadow");
    lens->setVisible(true);
    smallLens->setVisible(true);
    pressKey(Qt::Key_G);
    QTest::qWait(750);
    require(meanDifference(flowerGlass, capture(view)) < 0.5,
            "materialization returns to the same optical state without feedback");

    const QPointF largePosition = lens->position();
    const QPointF smallPosition = smallLens->position();
    const double flowerDepth = root->property("flowerDepth").toDouble();
    const double flowerBevel = root->property("flowerBevel").toDouble();
    const double flowerHeight = root->property("flowerHeight").toDouble();
    set("phase", 1.5);
    const QImage rightward = capture(view);
    set("phase", 4.5);
    const QImage leftward = capture(view);
    require(lens->position() == largePosition && smallLens->position() == smallPosition &&
            lens->property("thickness").toDouble() == flowerDepth &&
            smallLens->property("thickness").toDouble() == flowerDepth,
            "source motion leaves both lens positions and optical depths fixed");
    auto regionChanged = [&](QQuickItem* item) {
      const QRect region = QRectF((20 + item->x() + 20) * imageScale,
                                  (90 + item->y() + 20) * imageScale,
                                  (item->width() - 40) * imageScale,
                                  (item->height() - 40) * imageScale).toAlignedRect();
      return meanDifference(rightward.copy(region), leftward.copy(region)) > 12;
    };
    require(regionChanged(lens) && regionChanged(smallLens),
            "both lens interiors respond visibly across the source-motion cycle");
    set("phase", 6.0);
    require(meanDifference(flowerGlass, capture(view)) < 0.5,
            "the full Flower motion cycle returns without accumulated distortion");
    set("phase", 0.0);

    set("lensX", 130.0);
    set("lensY", 270.0);
    require(capture(view).save(output.filePath("flower-petal.png")), "saved lens crossing the petal silhouette");
    set("lensX", 730.0);
    set("lensY", 185.0);
    require(capture(view).save(output.filePath("flower-sky.png")), "saved lens over a quiet sky region");

    pressKey(Qt::Key_6);
    capture(view).save(output.filePath("desert.png"));
    pressKey(Qt::Key_G);
    QTest::qWait(750);
    capture(view).save(output.filePath("desert-bare.png"));
    pressKey(Qt::Key_G);
    QTest::qWait(750);

    auto* study = root->findChild<QQuickItem*>("referenceStudy");
    auto* referenceGlass = root->findChild<QQuickItem*>("referenceGlass");
    auto* bar = root->findChild<QQuickItem*>("foregroundBar");
    for (int mode = 0; mode < 3; ++mode) {
      pressKey(static_cast<Qt::Key>(Qt::Key_7 + mode));
      set("phase", 0.0);
      const QImage start = capture(view);
      const QPointF startPosition = referenceGlass->position();
      const QString name = QStringList{"boundary", "lighting", "panel"}.at(mode);
      if (!start.save(output.filePath(name + ".png"))) throw std::runtime_error("study capture failed");
      require(study->isVisible() && !lens->isVisible() && !smallLens->isVisible(),
              "reference study replaces the previous glass without hidden-state leakage");
      if (mode == 0) {
        const int x = int(20 + referenceGlass->x() + referenceGlass->width() / 2);
        // The returning light band sits inside the last seven logical pixels.
        // Stay clear of the outer two-pixel highlight and coverage boundary.
        const int y = int(90 + referenceGlass->y() + referenceGlass->height() - 5);
        set("bend", false);
        const QImage unbent = capture(view);
        require(pixel(start, view, x, y).red() > pixel(unbent, view, x, y).red() + 50
                && pixel(start, view, x, y).red() > pixel(start, view, x, y - 15).red() + 50,
                "boundary lens encloses the dark pocket with refracted light below it");
        set("bend", true);
      }
      set("phase", 1.5);
      const QImage moved = capture(view);
      require(meanDifference(start, moved) > 1,
              "the reference study produces a visible temporal change");
      require((referenceGlass->position() == startPosition) == (mode == 1),
              "lighting keeps geometry fixed while crossing and panel studies move the glass");
      if (mode == 2) {
        const QPointF point = bar->mapToScene(QPointF(bar->width() / 2, bar->height() / 2));
        require(pixel(moved, view, int(point.x()), int(point.y())).red() > 250,
                "the moving panel keeps its foreground bar sharp and white");
      }
      set("phase", 6.0);
      require(meanDifference(start, capture(view)) < 0.5,
              "reference motion returns to its initial image without accumulated feedback");
    }

    pressKey(Qt::Key_0);
    set("phase", 0.0);
    auto* sizeStudy = root->findChild<QQuickItem*>("sizeStudy");
    auto* sizeGlass = root->findChild<QQuickItem*>("sizeGlass");
    auto* sizeInk = root->findChild<QQuickItem*>("sizeInk");
    const QImage compact = capture(view);
    compact.save(output.filePath("size-compact.png"));
    require(sizeStudy->isVisible() && !study->isVisible() && !lens->isVisible(),
            "key zero opens the size study with no previous glass left visible");
    const double compactDepth = sizeGlass->property("thickness").toDouble();
    set("phase", 3.0);
    const QImage expanded = capture(view);
    expanded.save(output.filePath("size-expanded.png"));
    require(sizeGlass->width() > 700 && sizeGlass->height() > 400
            && sizeGlass->property("thickness").toDouble() > compactDepth * 2,
            "expanding the control increases dimensions and optical depth");
    set("phase", 1.5);
    sizeInk->setVisible(false);
    set("compare", true);
    QTest::qWait(750);
    const QImage dissolvedSize = capture(view);
    sizeGlass->setVisible(false);
    require(meanDifference(dissolvedSize.copy(stageRect), capture(view).copy(stageRect)) < 0.5,
            "the intermediate size dissolves to its source without a residual colored reflection");
    sizeGlass->setVisible(true);
    set("compare", false);
    QTest::qWait(750);
    // Exercise actual default material values, not the explicit optical fixture:
    // with bending and light isolated, Clear softens detail while retaining
    // the broad color distribution rather than introducing a neutral veil.
    set("bend", false);
    set("illuminate", false);
    const QRect clearCore = QRectF((20 + sizeGlass->x() + 70) * imageScale,
                                   (90 + sizeGlass->y() + 70) * imageScale,
                                   (sizeGlass->width() - 140) * imageScale,
                                   (sizeGlass->height() - 140) * imageScale).toAlignedRect();
    const QImage defaultCore = capture(view).copy(clearCore);
    const QImage sourceCore = dissolvedSize.copy(clearCore);
    const double defaultDetailChange = meanDifference(sourceCore, defaultCore);
    require(defaultDetailChange > 0.1 && defaultDetailChange < 3.0,
            "default Clear applies restrained local softness to transmitted detail");
    require(meanDifference(sourceCore.scaled(24, 24, Qt::IgnoreAspectRatio, Qt::SmoothTransformation),
                           defaultCore.scaled(24, 24, Qt::IgnoreAspectRatio, Qt::SmoothTransformation)) < 1.0,
            "default Clear retains the broad source colors without a diffuse body veil");
    set("bend", true);
    set("illuminate", true);
    sizeInk->setVisible(true);
    set("phase", 6.0);
    require(meanDifference(compact, capture(view)) < 0.5,
            "growth and shrinkage return to the same compact material without accumulated feedback");

    set("pattern", 0);
    const double beforeMotion = root->property("phase").toDouble();
    set("animated", true);
    QTest::qWait(300);
    require(root->property("phase").toDouble() > beforeMotion + 0.1,
            "live frame animation advances the background");
    set("animated", false);

    // Exercise the actual Flower settings on coordinate-coded content. This
    // detects a regression to the shallow sand profile even if flower colors
    // happen to conceal it in one static screenshot.
    load(view, build.filePath("TestScene.qml"), QSize(640, 420));
    root = view.rootObject();
    set("glassX", 210.0);
    set("glassY", 100.0);
    set("glassWidth", 220.0);
    set("glassHeight", 220.0);
    set("glassRadius", 110.0);
    set("bevel", flowerBevel);
    set("surfaceHeight", flowerHeight);
    set("backingDistance", flowerDepth);
    const QImage unfolded = capture(view);
    set("optics", 1.0);
    const QImage folded = capture(view);
    const int centerRed = pixel(unfolded, view, 320, 210).red();
    require(pixel(folded, view, 426, 210).red() < centerRed - 5 &&
            pixel(folded, view, 213, 210).red() > centerRed + 5,
            "Flower rim rays reach the opposite side of the circle center");
    require(difference(pixel(folded, view, 320, 210), pixel(unfolded, view, 320, 210)) <= 1 &&
            pixel(folded, view, 390, 210).red() > centerRed + 10,
            "strong rim folding retains an upright, undisplaced interior");
    set("glassX", 244.0);
    set("glassY", 134.0);
    set("glassWidth", 152.0);
    set("glassHeight", 152.0);
    set("glassRadius", 76.0);
    const QImage smallFold = capture(view);
    require(pixel(smallFold, view, 392, 210).red() < pixel(folded, view, 426, 210).red() - 5,
            "shared optical depth produces a stronger relative fold in the small circle");

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

    QJsonObject result{{"checks", checks}, {"identity_mean_error_255", identityError},
                       {"blur_contrast_ratio", softContrast / sharpContrast},
                       {"narrow_contrast_ratio", narrowContrast / sharpContrast},
                       {"default_detail_change_255", defaultDetailChange},
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
