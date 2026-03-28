import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
  ));

  runApp(
    ChangeNotifierProvider(
      create: (_) => DrawingState(),
      child: const BrushDrawApp(),
    ),
  );
}

class BrushDrawApp extends StatelessWidget {
  const BrushDrawApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Brush Draw',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2B6CFF),
        useMaterial3: true,
        brightness: Brightness.light,
        fontFamily: 'Roboto', // Change to 'SF Pro Display' or your preferred
        sliderTheme: SliderThemeData(
          activeTrackColor: const Color(0xFF2B6CFF),
          inactiveTrackColor: Colors.grey.shade200,
          thumbColor: const Color(0xFF2B6CFF),
          overlayColor: const Color(0x222B6CFF),
          trackHeight: 6,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        ),
      ),
      home: const DrawingScreen(),
    );
  }
}

class DrawingScreen extends StatelessWidget {
  const DrawingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.grey.shade100,
      body: Stack(
        children:[
          // ── Canvas Area ──
          const Positioned.fill(
            child: DrawingCanvasWidget(),
          ),
          // ── Floating Toolbar ──
          const Align(
            alignment: Alignment.bottomCenter,
            child: AppToolbar(),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════ MODELS ═══════════════════

class SeededRng {
  int _state;
  SeededRng(int seed) : _state = seed & 0xFFFFFFFF;

  double next() {
    _state = ((_state * 1664525) + 1013904223) & 0xFFFFFFFF;
    return (_state & 0xFFFFFFFF) / 0x100000000;
  }

  double range(double a, double b) => a + (b - a) * next();
  int rangeInt(int a, int b) =>
      a + (next() * (b - a + 1)).floor().clamp(0, b - a);
  T choice<T>(List<T> arr) =>
      arr[(next() * arr.length).floor().clamp(0, arr.length - 1)];
}

class BrushShape {
  int symmetry;
  int complexity;
  double density;
  double organic;
  double core;
  double roundness;
  double shadowSize;
  double shadowOpacity;

  BrushShape({
    this.symmetry = 3,
    this.complexity = 11,
    this.density = 0.53,
    this.organic = 0.43,
    this.core = 0.23,
    this.roundness = 0.40,
    this.shadowSize = 0.20,
    this.shadowOpacity = 0.35,
  });
}

class JitterSettings {
  double size;
  double angle;
  double opacity;
  double spacing;

  JitterSettings({
    this.size = 0.05,
    this.angle = 10,
    this.opacity = 0.10,
    this.spacing = 0.0,
  });
}

class BrushSettings {
  Color color;
  int seed;
  BrushShape shape;

  double softness;
  double feather;
  double grain;

  double size;
  double spacing;
  double flow;
  double smoothing;
  double angleSmoothing;
  double scatter;
  bool followAngle;
  BlendMode blendMode;
  double angleOffsetDeg;

  JitterSettings jitter;

  ui.Image? stampImage;
  bool ready;

  BrushSettings({
    this.color = const Color(0xFF1A1A1A),
    int? seed,
    BrushShape? shape,
    this.softness = 0.0,
    this.feather = 0.0,
    this.grain = 0.0,
    this.size = 512,
    this.spacing = 0.15,
    this.flow = 1.0,
    this.smoothing = 0.15,
    this.angleSmoothing = 0.0,
    this.scatter = 0.0,
    this.followAngle = true,
    this.blendMode = BlendMode.srcOver,
    this.angleOffsetDeg = 0,
    JitterSettings? jitter,
    this.stampImage,
    this.ready = false,
  })  : seed = seed ?? Random().nextInt(0xFFFFFFFF),
        shape = shape ?? BrushShape(),
        jitter = jitter ?? JitterSettings();
}

class StampPoint {
  final double x, y, size, angle, alpha;
  const StampPoint(
      {required this.x,
      required this.y,
      required this.size,
      required this.angle,
      required this.alpha});
}

class StrokeData {
  final ui.Image stampImage;
  final BlendMode blendMode;
  final List<StampPoint> stamps;
  final int layerId;

  StrokeData({
    required this.stampImage,
    required this.blendMode,
    required this.stamps,
    required this.layerId,
  });
}

class DrawingLayer {
  final int id;
  String name;
  bool visible;
  double opacity;
  BlendMode blendMode;
  String maskMode;
  double glowSize;
  double glowStrength;

  List<StrokeData> strokes;
  ui.Image? cachedImage;
  int bakedStrokeCount; // Incremental rendering optimization

  DrawingLayer({
    required this.id,
    required this.name,
    this.visible = true,
    this.opacity = 1.0,
    this.blendMode = BlendMode.srcOver,
    this.maskMode = 'none',
    this.glowSize = 30,
    this.glowStrength = 50,
    List<StrokeData>? strokes,
    this.cachedImage,
    this.bakedStrokeCount = 0,
  }) : strokes = strokes ??[];
}

abstract class UndoAction {}

class StrokeUndoAction extends UndoAction {
  final int layerId;
  final StrokeData stroke;
  StrokeUndoAction({required this.layerId, required this.stroke});
}

class ClearUndoAction extends UndoAction {
  final List<LayerSnapshot> snapshots;
  ClearUndoAction({required this.snapshots});
}

class LayerSnapshot {
  final int id;
  final String name;
  final bool visible;
  final double opacity;
  final BlendMode blendMode;
  final String maskMode;
  final double glowSize;
  final double glowStrength;
  final List<StrokeData> strokes;

  LayerSnapshot({
    required this.id,
    required this.name,
    required this.visible,
    required this.opacity,
    required this.blendMode,
    required this.maskMode,
    required this.glowSize,
    required this.glowStrength,
    required this.strokes,
  });
}

class ColorPick {
  double h; // 0..360
  double s; // 0..1
  double v; // 0..1
  double a; // 0..1

  ColorPick({this.h = 0, this.s = 0, this.v = 0.1, this.a = 1.0});

  Color toColor() {
    return HSVColor.fromAHSV(a, h.clamp(0, 360), s.clamp(0, 1), v.clamp(0, 1))
        .toColor();
  }

  void setFromColor(Color c) {
    final hsv = HSVColor.fromColor(c);
    h = hsv.hue;
    s = hsv.saturation;
    v = hsv.value;
    a = c.alpha / 255.0;
  }

  String toHex() {
    final c = toColor();
    return '#${c.red.toRadixString(16).padLeft(2, '0')}'
        '${c.green.toRadixString(16).padLeft(2, '0')}'
        '${c.blue.toRadixString(16).padLeft(2, '0')}'
        '${c.alpha.toRadixString(16).padLeft(2, '0')}'
            .toUpperCase();
  }

  String toRgbaString() {
    final c = toColor();
    return 'rgba(${c.red}, ${c.green}, ${c.blue}, ${a.toStringAsFixed(2)})';
  }
}

// ═══════════════════ BRUSH GENERATOR ═══════════════════

double _clamp01(double v) => v.clamp(0.0, 1.0);

Future<ui.Image> generateStampImage({
  required BrushShape shape,
  required Color color,
  required int seed,
  required int imageSize,
  required double softness,
  required double feather,
  required double grain,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, imageSize.toDouble(), imageSize.toDouble()),
  );
  final sz = imageSize.toDouble();
  final half = sz / 2;

  _drawProceduralShape(canvas, half, half, half * 0.92, shape, color, seed);

  final rng = SeededRng(seed + 999);
  final coreR = half * (0.02 + _clamp01(shape.core) * 0.22);
  final coreRx = coreR * rng.range(0.7, 1.2);
  final coreRy = coreR * rng.range(0.7, 1.2);
  final corePaint = Paint()
    ..color = color.withValues(alpha: rng.range(0.12, 0.6));
  canvas.save();
  canvas.translate(half, half);
  canvas.drawOval(
    Rect.fromCenter(center: Offset.zero, width: coreRx * 2, height: coreRy * 2),
    corePaint,
  );
  canvas.restore();

  final basePicture = recorder.endRecording();
  ui.Image baseImage = await basePicture.toImage(imageSize, imageSize);

  if (shape.shadowOpacity > 0.001 && shape.shadowSize > 0.001) {
    baseImage = await _applyShadow(
        baseImage, imageSize, shape.shadowSize, shape.shadowOpacity);
  }
  if (softness > 0.001) {
    baseImage = await _applyBlur(baseImage, imageSize, softness);
  }
  if (feather > 0.001) {
    baseImage = await _applyFeather(baseImage, imageSize, feather);
  }
  if (grain > 0.001) {
    baseImage = await _applyGrain(baseImage, imageSize, grain);
  }

  return baseImage;
}

void _drawProceduralShape(Canvas canvas, double cx, double cy, double R,
    BrushShape shape, Color color, int seed) {
  final rng = SeededRng(seed);
  final folds = shape.symmetry.clamp(2, 5);
  final wedge = 2 * pi / folds;
  final margin = wedge * 0.08;
  final density = _clamp01(shape.density);
  final complexity = shape.complexity.clamp(1, 30);
  final organic = _clamp01(shape.organic);
  final roundK = _clamp01(shape.roundness);
  final baseCount = 3 + (complexity * 2.0).round() + (density * 12).round();

  final types =['ellipse', 'rect', 'poly', 'ellipse', 'ellipse', 'rect'];
  final primitives = <_Primitive>[];

  for (int i = 0; i < baseCount; i++) {
    final primType = rng.choice(types);
    final a = rng.range(-wedge / 2 + margin, wedge / 2 - margin);
    final wobA = (rng.next() - 0.5) * wedge * 0.25 * organic;
    final wobR = (rng.next() - 0.5) * R * 0.25 * organic;
    final rad = (rng.range(R * 0.05, R) + wobR).clamp(R * 0.04, R);
    final radians = a + wobA;
    final px = rad * cos(radians);
    final py = rad * sin(radians);
    final opacity = (rng.next() * 0.85 + 0.1).clamp(0.12, 0.95);

    if (primType == 'ellipse') {
      final scaleMax = 0.22 + complexity * 0.02;
      final rx = rng.range(R * 0.03, R * scaleMax) *
          (1 + (rng.next() - 0.5) * 0.6 * organic);
      final ry = rng.range(R * 0.03, R * scaleMax) *
          (1 + (rng.next() - 0.5) * 0.6 * organic);
      final rot = rng.range(-90, 90) + (rng.next() - 0.5) * 50 * organic;
      primitives.add(_Primitive(
        type: 'ellipse',
        cx: px,
        cy: py,
        rx: rx,
        ry: ry,
        rot: rot * pi / 180,
        opacity: opacity,
      ));
    } else if (primType == 'rect') {
      final w = rng.range(R * 0.05, R * (0.22 + complexity * 0.04));
      final h = rng.range(R * 0.05, R * (0.22 + complexity * 0.04));
      final rot = rng.range(-90, 90) + (rng.next() - 0.5) * 50 * organic;
      final rr = min(w, h) * (0.05 + 0.45 * roundK);
      primitives.add(_Primitive(
        type: 'rect',
        cx: px,
        cy: py,
        w: w,
        h: h,
        rr: rr,
        rot: rot * pi / 180,
        opacity: opacity,
      ));
    } else {
      final n = rng.rangeInt(3, 6);
      final pts = <Offset>[];
      for (int j = 0; j < n; j++) {
        final aa = rng.range(-wedge / 2 + margin, wedge / 2 - margin) +
            (rng.next() - 0.5) * wedge * 0.3 * organic;
        final rr = rng.range(R * 0.07, R).clamp(R * 0.06, R);
        pts.add(Offset(rr * cos(aa), rr * sin(aa)));
      }
      final rot = rng.range(-30, 30);
      primitives.add(_Primitive(
        type: 'poly',
        cx: 0,
        cy: 0,
        rot: rot * pi / 180,
        opacity: opacity,
        polyPts: pts,
      ));
    }
  }

  for (int k = 0; k < folds; k++) {
    final foldAngle = k * wedge;
    for (final p in primitives) {
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(foldAngle);

      final paint = Paint()
        ..color = color.withValues(alpha: p.opacity)
        ..style = PaintingStyle.fill;

      if (p.type == 'ellipse') {
        canvas.save();
        canvas.translate(p.cx, p.cy);
        canvas.rotate(p.rot);
        canvas.drawOval(
          Rect.fromCenter(
              center: Offset.zero, width: p.rx * 2, height: p.ry * 2),
          paint,
        );
        canvas.restore();
      } else if (p.type == 'rect') {
        canvas.save();
        canvas.translate(p.cx, p.cy);
        canvas.rotate(p.rot);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: p.w, height: p.h),
            Radius.circular(p.rr),
          ),
          paint,
        );
        canvas.restore();
      } else if (p.type == 'poly' &&
          p.polyPts != null &&
          p.polyPts!.length >= 3) {
        canvas.save();
        canvas.rotate(p.rot);
        final path = Path();
        path.moveTo(p.polyPts![0].dx, p.polyPts![0].dy);
        for (int i = 1; i < p.polyPts!.length; i++) {
          path.lineTo(p.polyPts![i].dx, p.polyPts![i].dy);
        }
        path.close();
        canvas.drawPath(path, paint);
        canvas.restore();
      }
      canvas.restore();
    }
  }
}

Future<ui.Image> _applyShadow(
    ui.Image src, int size, double shadowSize, double shadowOpacity) async {
  final recorder = ui.PictureRecorder();
  final canvas =
      Canvas(recorder, Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()));
  final sigma = shadowSize * size * 0.10;
  canvas.drawImage(
    src,
    Offset.zero,
    Paint()
      ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma)
      ..colorFilter = ColorFilter.mode(
          Colors.black.withValues(alpha: shadowOpacity), BlendMode.srcIn),
  );
  canvas.drawImage(src, Offset.zero, Paint());
  final pic = recorder.endRecording();
  return pic.toImage(size, size);
}

Future<ui.Image> _applyBlur(ui.Image src, int size, double softness) async {
  final recorder = ui.PictureRecorder();
  final canvas =
      Canvas(recorder, Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()));
  final maxBlur = size * 0.06;
  canvas.drawImage(
    src,
    Offset.zero,
    Paint()
      ..imageFilter = ui.ImageFilter.blur(
          sigmaX: softness * maxBlur, sigmaY: softness * maxBlur),
  );
  final pic = recorder.endRecording();
  return pic.toImage(size, size);
}

Future<ui.Image> _applyFeather(ui.Image src, int size, double feather) async {
  final recorder = ui.PictureRecorder();
  final canvas =
      Canvas(recorder, Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()));
  final sz = size.toDouble();
  final half = sz / 2;

  canvas.drawImage(src, Offset.zero, Paint());

  final r0 = (1 - feather) * half;
  final gradient = ui.Gradient.radial(
    Offset(half, half),
    half,
    [const Color(0xFFFFFFFF), const Color(0x00FFFFFF)],
    [r0 / half, 1.0],
  );
  canvas.drawRect(
    Rect.fromLTWH(0, 0, sz, sz),
    Paint()
      ..shader = gradient
      ..blendMode = BlendMode.dstIn,
  );

  final pic = recorder.endRecording();
  return pic.toImage(size, size);
}

Future<ui.Image> _applyGrain(ui.Image src, int size, double grain) async {
  final recorder = ui.PictureRecorder();
  final canvas =
      Canvas(recorder, Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()));

  canvas.drawImage(src, Offset.zero, Paint());

  final noiseRec = ui.PictureRecorder();
  final noiseCanvas = Canvas(
      noiseRec, Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()));
  final rng = Random();
  final amp = (255 * grain * 0.6).round();
  final step = max(1, size ~/ 128);
  for (int y = 0; y < size; y += step) {
    for (int x = 0; x < size; x += step) {
      final a = (255 - rng.nextInt(amp + 1)).clamp(0, 255);
      noiseCanvas.drawRect(
        Rect.fromLTWH(
            x.toDouble(), y.toDouble(), step.toDouble(), step.toDouble()),
        Paint()..color = Color.fromARGB(a, 255, 255, 255),
      );
    }
  }
  final noisePic = noiseRec.endRecording();
  final noiseImg = await noisePic.toImage(size, size);

  canvas.drawImage(noiseImg, Offset.zero, Paint()..blendMode = BlendMode.dstIn);
  noiseImg.dispose();

  final pic = recorder.endRecording();
  return pic.toImage(size, size);
}

class _Primitive {
  final String type;
  final double cx, cy, rx, ry, w, h, rr, rot, opacity;
  final List<Offset>? polyPts;

  _Primitive({
    required this.type,
    this.cx = 0,
    this.cy = 0,
    this.rx = 0,
    this.ry = 0,
    this.w = 0,
    this.h = 0,
    this.rr = 0,
    this.rot = 0,
    this.opacity = 1.0,
    this.polyPts,
  });
}

// ═══════════════════ STATE ═══════════════════

int _nearestPow2(int n) {
  int p = 1;
  while (p < n) {
    p <<= 1;
  }
  return p;
}

double _lerpAngle(double a, double b, double t) {
  final diff = atan2(sin(b - a), cos(b - a));
  return a + diff * t;
}

class DrawingState extends ChangeNotifier {
  final int worldWidth = 1800;
  final int worldHeight = 1800;
  Color backgroundColor = Colors.white;

  BrushSettings brush = BrushSettings();
  ColorPick colorPick = ColorPick(h: 0, s: 0, v: 0.1, a: 1.0);

  int _nextLayerId = 1;
  List<DrawingLayer> layers =[];
  int activeLayerIndex = 0;

  DrawingLayer? get activeLayer => layers.isNotEmpty
      ? layers[activeLayerIndex.clamp(0, layers.length - 1)]
      : null;

  Matrix4 worldToScreen = Matrix4.identity();
  Matrix4 screenToWorld = Matrix4.identity();
  bool cameraInitialized = false;

  bool drawing = false;
  Offset? lastPoint;
  Offset? lastRaw;
  double carry = 0;
  double smoothedDirAngle = 0;
  StrokeData? activeStroke;

  final List<UndoAction> undoStack =[];
  final List<UndoAction> redoStack =[];
  static const int maxUndo = 30;

  DrawingState() {
    _addInitialLayer();
    _rebuildBrush();
  }

  void _addInitialLayer() {
    layers.add(DrawingLayer(id: _nextLayerId++, name: 'Layer 1'));
    activeLayerIndex = 0;
  }

  bool _brushBuilding = false;

  Future<void> _rebuildBrush() async {
    if (_brushBuilding) return;
    _brushBuilding = true;

    final baseSize = _nearestPow2(brush.size.round()).clamp(64, 1024);
    try {
      final img = await generateStampImage(
        shape: brush.shape,
        color: brush.color,
        seed: brush.seed,
        imageSize: baseSize,
        softness: brush.softness,
        feather: brush.feather,
        grain: brush.grain,
      );
      brush.stampImage = img;
      brush.ready = true;
    } catch (_) {
      brush.ready = false;
    }
    _brushBuilding = false;
    notifyListeners();
  }

  void updateBrush() {
    brush.color = colorPick.toColor();
    _rebuildBrush();
  }

  void randomizeSeed() {
    brush.seed = Random().nextInt(0xFFFFFFFF);
    updateBrush();
  }

  void setColor(Color c) {
    colorPick.setFromColor(c);
    brush.color = colorPick.toColor();
    updateBrush();
  }

  void updateColorFromPick() {
    brush.color = colorPick.toColor();
    updateBrush();
  }

  void initCamera(Size viewSize) {
    final sx = viewSize.width / worldWidth;
    final sy = viewSize.height / worldHeight;
    final scale = min(sx, sy) * 0.9;
    final cx = viewSize.width / 2;
    final cy = viewSize.height / 2;
    final wcx = worldWidth / 2.0;
    final wcy = worldHeight / 2.0;

    worldToScreen = Matrix4.identity()
      ..translate(cx, cy)
      ..scale(scale, scale)
      ..translate(-wcx, -wcy);
    screenToWorld = Matrix4.copy(worldToScreen)..invert();
    cameraInitialized = true;
    notifyListeners();
  }

  Offset toWorld(Offset screen) {
    final v = screenToWorld.transform4(Vector4(screen.dx, screen.dy, 0, 1));
    return Offset(v.x / v.w, v.y / v.w);
  }

  void applyPanZoom(Matrix4 delta) {
    worldToScreen = delta * worldToScreen;
    screenToWorld = Matrix4.copy(worldToScreen)..invert();
    notifyListeners();
  }

  void resetCamera(Size viewSize) {
    initCamera(viewSize);
  }

  double _getSpacing() {
    return max(1.0, brush.size * brush.spacing);
  }

  _StampParams _computeStampParams() {
    final j = brush.jitter;
    final rng = Random();
    double signed() => rng.nextDouble() * 2 - 1;

    final sizeJitter = 1 + signed() * j.size;
    final sz = max(1.0, brush.size * sizeJitter);

    final angleOffset = brush.angleOffsetDeg * pi / 180;
    final baseAngle = brush.followAngle ? smoothedDirAngle : 0.0;
    final angle = baseAngle + angleOffset + (signed() * j.angle) * pi / 180;

    final alpha = (brush.flow * (1 + signed() * j.opacity)).clamp(0.0, 1.0);

    final scatterR = brush.scatter * brush.size * rng.nextDouble();
    final scatterA = rng.nextDouble() * pi * 2;
    final offX = scatterR * cos(scatterA);
    final offY = scatterR * sin(scatterA);

    final spacing = max(1.0, _getSpacing() * (1 + signed() * j.spacing));

    return _StampParams(
        size: sz,
        angle: angle,
        alpha: alpha,
        offX: offX,
        offY: offY,
        spacing: spacing);
  }

  void beginStroke(Offset worldPoint) {
    final layer = activeLayer;
    if (layer == null || !brush.ready || brush.stampImage == null) return;

    drawing = true;
    carry = 0;
    smoothedDirAngle = 0;
    lastPoint = worldPoint;
    lastRaw = worldPoint;

    final params = _computeStampParams();
    activeStroke = StrokeData(
      stampImage: brush.stampImage!,
      blendMode: brush.blendMode,
      stamps:[],
      layerId: layer.id,
    );
    activeStroke!.stamps.add(StampPoint(
      x: worldPoint.dx + params.offX,
      y: worldPoint.dy + params.offY,
      size: params.size,
      angle: params.angle,
      alpha: params.alpha,
    ));
    notifyListeners();
  }

  void extendStroke(Offset currentWorld) {
    final layer = activeLayer;
    if (layer == null || activeStroke == null || lastRaw == null) return;

    final s = brush.smoothing.clamp(0.0, 0.9);
    final mix = s == 0 ? 1.0 : (1.0 - s);
    final smoothed = Offset(
      lastPoint!.dx + (currentWorld.dx - lastPoint!.dx) * mix,
      lastPoint!.dy + (currentWorld.dy - lastPoint!.dy) * mix,
    );
    lastPoint = smoothed;

    final from = lastRaw!;
    final dx = smoothed.dx - from.dx;
    final dy = smoothed.dy - from.dy;
    final dist = sqrt(dx * dx + dy * dy);
    if (dist < 0.1) return;

    final ang = atan2(dy, dx);
    final angS = brush.angleSmoothing.clamp(0.0, 0.9);
    smoothedDirAngle = _lerpAngle(smoothedDirAngle, ang, 1.0 - angS);

    double remaining = dist;
    double t = 0;
    while (true) {
      final params = _computeStampParams();
      final spacing = params.spacing;
      if (carry + remaining < spacing) break;

      final step = spacing - carry;
      t += step / dist;
      if (t > 1.0) break;
      final cx = from.dx + dx * t;
      final cy = from.dy + dy * t;

      activeStroke!.stamps.add(StampPoint(
        x: cx + params.offX,
        y: cy + params.offY,
        size: params.size,
        angle: params.angle,
        alpha: params.alpha,
      ));

      remaining -= step;
      carry = 0;
    }
    carry += remaining;
    lastRaw = smoothed;
    notifyListeners();
  }

  void endStroke() {
    if (activeStroke != null && activeStroke!.stamps.isNotEmpty) {
      final layer = layers.firstWhere(
        (l) => l.id == activeStroke!.layerId,
        orElse: () => layers.first,
      );
      
      final strokeToAdd = activeStroke!;
      layer.strokes.add(strokeToAdd);
      
      // Clear activeStroke immediately. CanvasPainter will render the unbaked stroke
      // seamlessly because layer.strokes.length > layer.bakedStrokeCount.
      activeStroke = null;
      drawing = false;
      carry = 0;

      // Update cache incrementally (prevents full canvas rebuilds on every stroke)
      _updateLayerCacheIncremental(layer, [strokeToAdd]);

      undoStack.add(StrokeUndoAction(layerId: layer.id, stroke: strokeToAdd));
      if (undoStack.length > maxUndo) undoStack.removeAt(0);
      redoStack.clear();
    } else {
      activeStroke = null;
      drawing = false;
      carry = 0;
    }
    notifyListeners();
  }

  Future<void> _updateLayerCacheIncremental(
      DrawingLayer layer, List<StrokeData> newStrokes) async {
    final sz = Size(worldWidth.toDouble(), worldHeight.toDouble());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Offset.zero & sz);

    if (layer.cachedImage != null) {
      canvas.drawImage(layer.cachedImage!, Offset.zero, Paint());
    }

    for (final stroke in newStrokes) {
      _paintStroke(canvas, stroke);
    }

    final pic = recorder.endRecording();
    final img = await pic.toImage(worldWidth, worldHeight);

    layer.cachedImage?.dispose();
    layer.cachedImage = img;
    layer.bakedStrokeCount += newStrokes.length;
    notifyListeners();
  }

  Future<void> _rebuildLayerCacheFull(DrawingLayer layer) async {
    final sz = Size(worldWidth.toDouble(), worldHeight.toDouble());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Offset.zero & sz);

    for (final stroke in layer.strokes) {
      _paintStroke(canvas, stroke);
    }

    final pic = recorder.endRecording();
    final img = await pic.toImage(worldWidth, worldHeight);

    layer.cachedImage?.dispose();
    layer.cachedImage = img;
    layer.bakedStrokeCount = layer.strokes.length;
    notifyListeners();
  }

  void _paintStroke(Canvas canvas, StrokeData stroke) {
    for (final st in stroke.stamps) {
      canvas.save();
      canvas.translate(st.x, st.y);
      canvas.rotate(st.angle);
      final half = st.size / 2;
      canvas.drawImageRect(
        stroke.stampImage,
        Rect.fromLTWH(0, 0, stroke.stampImage.width.toDouble(),
            stroke.stampImage.height.toDouble()),
        Rect.fromLTWH(-half, -half, st.size, st.size),
        Paint()
          ..color = Color.fromARGB((st.alpha * 255).round(), 255, 255, 255)
          ..blendMode = stroke.blendMode
          ..filterQuality = FilterQuality.medium,
      );
      canvas.restore();
    }
  }

  void undo() {
    if (drawing) endStroke();
    if (undoStack.isEmpty) return;
    final action = undoStack.removeLast();
    redoStack.add(action);

    if (action is StrokeUndoAction) {
      final layer = layers.firstWhere(
        (l) => l.id == action.layerId,
        orElse: () => layers.first,
      );
      if (layer.strokes.isNotEmpty) {
        layer.strokes.removeLast();
        layer.cachedImage?.dispose();
        layer.cachedImage = null;
        layer.bakedStrokeCount = 0; // Fallback to raw strokes while rebuilding
        _rebuildLayerCacheFull(layer);
      }
    } else if (action is ClearUndoAction) {
      _restoreSnapshots(action.snapshots);
    }
    notifyListeners();
  }

  void redo() {
    if (drawing) endStroke();
    if (redoStack.isEmpty) return;
    final action = redoStack.removeLast();
    undoStack.add(action);

    if (action is StrokeUndoAction) {
      final layer = layers.firstWhere(
        (l) => l.id == action.layerId,
        orElse: () => layers.first,
      );
      layer.strokes.add(action.stroke);
      _updateLayerCacheIncremental(layer, [action.stroke]);
    } else if (action is ClearUndoAction) {
      _clearAllInternal();
    }
    notifyListeners();
  }

  void clearAll() {
    if (drawing) endStroke();
    final snapshots = _takeSnapshots();
    _clearAllInternal();
    undoStack.add(ClearUndoAction(snapshots: snapshots));
    if (undoStack.length > maxUndo) undoStack.removeAt(0);
    redoStack.clear();
    notifyListeners();
  }

  void _clearAllInternal() {
    for (final l in layers) {
      l.strokes.clear();
      l.cachedImage?.dispose();
      l.cachedImage = null;
      l.bakedStrokeCount = 0;
    }
  }

  List<LayerSnapshot> _takeSnapshots() {
    return layers
        .map((l) => LayerSnapshot(
              id: l.id,
              name: l.name,
              visible: l.visible,
              opacity: l.opacity,
              blendMode: l.blendMode,
              maskMode: l.maskMode,
              glowSize: l.glowSize,
              glowStrength: l.glowStrength,
              strokes: List.from(l.strokes),
            ))
        .toList();
  }

  void _restoreSnapshots(List<LayerSnapshot> snaps) {
    for (final snap in snaps) {
      final idx = layers.indexWhere((l) => l.id == snap.id);
      if (idx >= 0) {
        layers[idx].strokes = List.from(snap.strokes);
        layers[idx].visible = snap.visible;
        layers[idx].opacity = snap.opacity;
        layers[idx].blendMode = snap.blendMode;
        layers[idx].cachedImage?.dispose();
        layers[idx].cachedImage = null;
        layers[idx].bakedStrokeCount = 0;
        _rebuildLayerCacheFull(layers[idx]);
      }
    }
  }

  void addLayer() {
    final l = DrawingLayer(id: _nextLayerId++, name: 'Layer $_nextLayerId');
    layers.add(l);
    activeLayerIndex = layers.length - 1;
    notifyListeners();
  }

  void removeLayer(int id) {
    if (layers.length <= 1) return;
    final idx = layers.indexWhere((l) => l.id == id);
    if (idx < 0) return;
    layers[idx].cachedImage?.dispose();
    layers.removeAt(idx);
    if (activeLayerIndex >= layers.length) {
      activeLayerIndex = layers.length - 1;
    }
    notifyListeners();
  }

  void selectLayer(int index) {
    activeLayerIndex = index.clamp(0, layers.length - 1);
    notifyListeners();
  }

  void toggleLayerVisibility(int id) {
    final l = layers.firstWhere((l) => l.id == id, orElse: () => layers.first);
    l.visible = !l.visible;
    notifyListeners();
  }

  void reorderLayer(int fromIndex, int toIndex) {
    if (fromIndex == toIndex) return;
    final item = layers.removeAt(fromIndex);
    layers.insert(toIndex.clamp(0, layers.length), item);
    if (activeLayerIndex == fromIndex) {
      activeLayerIndex = toIndex.clamp(0, layers.length - 1);
    }
    notifyListeners();
  }

  void updateLayerSettings(int id,
      {String? name,
      double? opacity,
      BlendMode? blendMode,
      String? maskMode,
      double? glowSize,
      double? glowStrength}) {
    final idx = layers.indexWhere((l) => l.id == id);
    if (idx < 0) return;
    final l = layers[idx];
    if (name != null) l.name = name;
    if (opacity != null) l.opacity = opacity;
    if (blendMode != null) l.blendMode = blendMode;
    if (maskMode != null) l.maskMode = maskMode;
    if (glowSize != null) l.glowSize = glowSize;
    if (glowStrength != null) l.glowStrength = glowStrength;
    notifyListeners();
  }

  Future<Uint8List?> exportPng() async {
    final recorder = ui.PictureRecorder();
    final sz = Size(worldWidth.toDouble(), worldHeight.toDouble());
    final canvas = Canvas(recorder, Offset.zero & sz);

    canvas.drawRect(Offset.zero & sz, Paint()..color = backgroundColor);

    for (final l in layers) {
      if (!l.visible) continue;
      if (l.cachedImage == null) {
        // Fallback for unbaked elements during saving (rare)
        for (final st in l.strokes) {
          _paintStroke(canvas, st);
        }
        continue;
      }

      if (l.blendMode == BlendMode.plus) {
        final blurPx = 2.0 + (l.glowSize / 100) * 24;
        final haloAlpha = (l.glowStrength / 100) * l.opacity;
        canvas.saveLayer(
            Offset.zero & sz,
            Paint()
              ..blendMode = BlendMode.plus
              ..color = Color.fromARGB((haloAlpha * 255).round(), 255, 255, 255)
              ..imageFilter =
                  ui.ImageFilter.blur(sigmaX: blurPx, sigmaY: blurPx));
        canvas.drawImage(l.cachedImage!, Offset.zero, Paint());
        canvas.restore();
        canvas.saveLayer(
            Offset.zero & sz,
            Paint()
              ..blendMode = BlendMode.plus
              ..color =
                  Color.fromARGB((l.opacity * 255).round(), 255, 255, 255));
        canvas.drawImage(l.cachedImage!, Offset.zero, Paint());
        canvas.restore();
      } else if (l.maskMode == 'alpha') {
        canvas.saveLayer(
            Offset.zero & sz,
            Paint()
              ..blendMode = BlendMode.dstIn
              ..color =
                  Color.fromARGB((l.opacity * 255).round(), 255, 255, 255));
        canvas.drawImage(l.cachedImage!, Offset.zero, Paint());
        canvas.restore();
      } else if (l.maskMode == 'alpha-invert') {
        canvas.saveLayer(
            Offset.zero & sz,
            Paint()
              ..blendMode = BlendMode.dstOut
              ..color =
                  Color.fromARGB((l.opacity * 255).round(), 255, 255, 255));
        canvas.drawImage(l.cachedImage!, Offset.zero, Paint());
        canvas.restore();
      } else {
        canvas.saveLayer(
            Offset.zero & sz,
            Paint()
              ..blendMode = l.blendMode
              ..color =
                  Color.fromARGB((l.opacity * 255).round(), 255, 255, 255));
        canvas.drawImage(l.cachedImage!, Offset.zero, Paint());
        canvas.restore();
      }
    }

    final pic = recorder.endRecording();
    final img = await pic.toImage(worldWidth, worldHeight);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return byteData?.buffer.asUint8List();
  }
}

class _StampParams {
  final double size, angle, alpha, offX, offY, spacing;
  const _StampParams({
    required this.size,
    required this.angle,
    required this.alpha,
    required this.offX,
    required this.offY,
    required this.spacing,
  });
}

extension Matrix4Ext on Matrix4 {
  Vector4 transform4(Vector4 v) {
    return Vector4(
      storage[0] * v.x + storage[4] * v.y + storage[8] * v.z + storage[12] * v.w,
      storage[1] * v.x + storage[5] * v.y + storage[9] * v.z + storage[13] * v.w,
      storage[2] * v.x + storage[6] * v.y + storage[10] * v.z + storage[14] * v.w,
      storage[3] * v.x + storage[7] * v.y + storage[11] * v.z + storage[15] * v.w,
    );
  }
}

class Vector4 {
  final double x, y, z, w;
  const Vector4(this.x, this.y, this.z, this.w);
}

// ═══════════════════ CANVAS WIDGET ═══════════════════

class DrawingCanvasWidget extends StatefulWidget {
  const DrawingCanvasWidget({super.key});

  @override
  State<DrawingCanvasWidget> createState() => _DrawingCanvasWidgetState();
}

class _DrawingCanvasWidgetState extends State<DrawingCanvasWidget> {
  final Map<int, Offset> _pointers = {};
  _GestureState? _gesture;
  bool _isDrawing = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<DrawingState>(
      builder: (context, state, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            if (!state.cameraInitialized) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                state.initCamera(
                    Size(constraints.maxWidth, constraints.maxHeight));
              });
            }
            return Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) => _onPointerDown(e, state, constraints),
              onPointerMove: (e) => _onPointerMove(e, state),
              onPointerUp: (e) => _onPointerUp(e, state),
              onPointerCancel: (e) => _onPointerUp(e, state),
              onPointerSignal: (e) => _onPointerSignal(e, state),
              child: CustomPaint(
                painter: _CanvasPainter(state),
                size: Size(constraints.maxWidth, constraints.maxHeight),
              ),
            );
          },
        );
      },
    );
  }

  void _onPointerDown(
      PointerDownEvent e, DrawingState state, BoxConstraints c) {
    _pointers[e.pointer] = e.localPosition;

    if (_pointers.length == 2) {
      if (_isDrawing) {
        state.endStroke();
        _isDrawing = false;
      }
      _startGesture(state);
    } else if (_pointers.length == 1) {
      if (!state.cameraInitialized) {
        state.initCamera(Size(c.maxWidth, c.maxHeight));
      }
      _isDrawing = true;
      final wp = state.toWorld(e.localPosition);
      state.beginStroke(wp);
    }
  }

  void _onPointerMove(PointerMoveEvent e, DrawingState state) {
    if (_pointers.containsKey(e.pointer)) {
      _pointers[e.pointer] = e.localPosition;
    }

    if (_pointers.length >= 2) {
      _updateGesture(state);
      _isDrawing = false;
    } else if (_pointers.length == 1 && _isDrawing) {
      final wp = state.toWorld(e.localPosition);
      state.extendStroke(wp);
    }
  }

  void _onPointerUp(PointerEvent e, DrawingState state) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) {
      _gesture = null;
    }
    if (_pointers.isEmpty && _isDrawing) {
      state.endStroke();
      _isDrawing = false;
    }
  }

  void _onPointerSignal(PointerSignalEvent e, DrawingState state) {
    if (e is PointerScrollEvent) {
      final scale = e.scrollDelta.dy > 0 ? 0.92 : 1.08;
      final focus = e.localPosition;
      final delta = Matrix4.identity()
        ..translate(focus.dx, focus.dy)
        ..scale(scale, scale)
        ..translate(-focus.dx, -focus.dy);
      state.applyPanZoom(delta);
    }
  }

  void _startGesture(DrawingState state) {
    final pts = _pointers.values.toList();
    final c0 = Offset((pts[0].dx + pts[1].dx) / 2, (pts[0].dy + pts[1].dy) / 2);
    final dx = pts[1].dx - pts[0].dx, dy = pts[1].dy - pts[0].dy;
    _gesture = _GestureState(
      startMatrix: Matrix4.copy(state.worldToScreen),
      center: c0,
      startDist: sqrt(dx * dx + dy * dy),
      startAngle: atan2(dy, dx),
    );
  }

  void _updateGesture(DrawingState state) {
    if (_gesture == null || _pointers.length < 2) return;
    final pts = _pointers.values.toList();
    final c1 = Offset((pts[0].dx + pts[1].dx) / 2, (pts[0].dy + pts[1].dy) / 2);
    final dx = pts[1].dx - pts[0].dx, dy = pts[1].dy - pts[0].dy;
    final d1 = sqrt(dx * dx + dy * dy);
    if (_gesture!.startDist < 5) return;
    final a1 = atan2(dy, dx);

    final scale = d1 / _gesture!.startDist;
    final rot = a1 - _gesture!.startAngle;

    final delta = Matrix4.identity()
      ..translate(c1.dx, c1.dy)
      ..rotateZ(rot)
      ..scale(scale, scale)
      ..translate(-_gesture!.center.dx, -_gesture!.center.dy);

    state.worldToScreen = delta * _gesture!.startMatrix;
    state.screenToWorld = Matrix4.copy(state.worldToScreen)..invert();
    state.notifyListeners();
  }
}

class _GestureState {
  final Matrix4 startMatrix;
  final Offset center;
  final double startDist;
  final double startAngle;
  _GestureState(
      {required this.startMatrix,
      required this.center,
      required this.startDist,
      required this.startAngle});
}

class _CanvasPainter extends CustomPainter {
  final DrawingState state;

  _CanvasPainter(this.state) : super(repaint: state);

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);

    canvas.save();
    canvas.transform(state.worldToScreen.storage);

    final worldRect = Rect.fromLTWH(
        0, 0, state.worldWidth.toDouble(), state.worldHeight.toDouble());

    // Main background color
    canvas.drawRect(worldRect, Paint()..color = state.backgroundColor);

    for (int i = 0; i < state.layers.length; i++) {
      final l = state.layers[i];
      if (!l.visible) continue;

      final layerPaint = Paint()
        ..color = Color.fromARGB((l.opacity * 255).round(), 255, 255, 255);

      if (l.maskMode == 'alpha') {
        layerPaint.blendMode = BlendMode.dstIn;
      } else if (l.maskMode == 'alpha-invert') {
        layerPaint.blendMode = BlendMode.dstOut;
      } else {
        layerPaint.blendMode = l.blendMode;
      }

      // Optimization: Avoid saveLayer if fully opaque and normal blend
      bool needsSaveLayer = l.opacity < 1.0 ||
          l.blendMode != BlendMode.srcOver ||
          l.maskMode != 'none';

      if (needsSaveLayer) {
        canvas.saveLayer(worldRect, layerPaint);
      }

      // Draw Baked Cache
      if (l.cachedImage != null) {
        canvas.drawImage(l.cachedImage!, Offset.zero, Paint());
      }

      // Draw Unbaked Strokes (Blink prevention mechanism)
      for (int j = l.bakedStrokeCount; j < l.strokes.length; j++) {
        _paintStroke(canvas, l.strokes[j]);
      }

      // Draw Active Stroke
      if (i == state.activeLayerIndex && state.activeStroke != null) {
        _paintStroke(canvas, state.activeStroke!);
      }

      if (needsSaveLayer) {
        canvas.restore();
      }
    }

    // World bounds outline
    canvas.drawRect(
      worldRect,
      Paint()
        ..color = Colors.black12
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    canvas.restore(); // end camera
  }

  void _paintStroke(Canvas canvas, StrokeData stroke) {
    for (final st in stroke.stamps) {
      canvas.save();
      canvas.translate(st.x, st.y);
      canvas.rotate(st.angle);
      final half = st.size / 2;
      canvas.drawImageRect(
        stroke.stampImage,
        Rect.fromLTWH(0, 0, stroke.stampImage.width.toDouble(),
            stroke.stampImage.height.toDouble()),
        Rect.fromLTWH(-half, -half, st.size, st.size),
        Paint()
          ..color = Color.fromARGB((st.alpha * 255).round(), 255, 255, 255)
          ..blendMode = stroke.blendMode
          ..filterQuality = FilterQuality.medium,
      );
      canvas.restore();
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFFE9E9EC);
    canvas.drawRect(Offset.zero & size, bg);

    final line = Paint()
      ..color = const Color(0x12000000)
      ..strokeWidth = 1;
    const step = 32.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter old) => true;
}

// ═══════════════════ UI PANELS & TOOLS ═══════════════════

class AppToolbar extends StatelessWidget {
  const AppToolbar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DrawingState>(builder: (ctx, state, _) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 24.0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.5)),
                  boxShadow:[
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children:[
                    _ToolBtn(
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: state.colorPick.toColor(),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black12, width: 1.5),
                        ),
                      ),
                      onTap: () => _showColorModal(context, state),
                      tooltip: 'Color',
                    ),
                    _separator(),
                    _ToolBtn(
                      child: const Icon(Icons.brush_rounded, size: 22),
                      onTap: () => _showBrushModal(context, state),
                      tooltip: 'Brush',
                    ),
                    _ToolBtn(
                      child: const Icon(Icons.layers_rounded, size: 22),
                      onTap: () => _showLayersPanel(context, state),
                      tooltip: 'Layers',
                    ),
                    _separator(),
                    _ToolBtn(
                      child: const Icon(Icons.undo_rounded, size: 22),
                      onTap: () => state.undo(),
                      tooltip: 'Undo',
                    ),
                    _ToolBtn(
                      child: const Icon(Icons.redo_rounded, size: 22),
                      onTap: () => state.redo(),
                      tooltip: 'Redo',
                    ),
                    _separator(),
                    _ToolBtn(
                      child: const Icon(Icons.delete_sweep_rounded, size: 22),
                      onTap: () => state.clearAll(),
                      tooltip: 'Clear',
                    ),
                    _ToolBtn(
                      child: const Icon(Icons.save_alt_rounded, size: 22),
                      onTap: () => _savePng(context, state),
                      tooltip: 'Save',
                    ),
                    _ToolBtn(
                      child: const Icon(Icons.zoom_out_map_rounded, size: 22),
                      onTap: () {
                        final mq = MediaQuery.of(context);
                        state.resetCamera(mq.size);
                      },
                      tooltip: 'Reset View',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _separator() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Container(width: 1, height: 24, color: Colors.black12),
      );

  void _showColorModal(BuildContext context, DrawingState state) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Let it naturally size itself
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: _ColorModalBody(state: state),
        ),
      ),
    );
  }

  void _showBrushModal(BuildContext context, DrawingState state) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(child: _BrushModalBody(state: state)),
      ),
    );
  }

  void _showLayersPanel(BuildContext context, DrawingState state) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(child: _LayersPanelBody(state: state)),
      ),
    );
  }

  Future<void> _savePng(BuildContext context, DrawingState state) async {
    final bytes = await state.exportPng();
    if (bytes == null) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(
          '${dir.path}/drawing_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to Gallery', style: const TextStyle(fontWeight: FontWeight.bold)),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    }
  }
}

class _ToolBtn extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final String tooltip;

  const _ToolBtn({required this.child, required this.onTap, this.tooltip = ''});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════ COLOR MODAL ═══════════════════

class _ColorModalBody extends StatefulWidget {
  final DrawingState state;
  const _ColorModalBody({required this.state});
  @override
  State<_ColorModalBody> createState() => _ColorModalBodyState();
}

class _ColorModalBodyState extends State<_ColorModalBody> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min, // Prevents drag conflict completely
        children:[
          _dragHandle(),
          _header('Color'),
          const SizedBox(height: 24),
          ColorWheelPicker(
            pick: widget.state.colorPick,
            onChanged: () {
              widget.state.updateColorFromPick();
              setState(() {});
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class ColorWheelPicker extends StatefulWidget {
  final ColorPick pick;
  final VoidCallback onChanged;

  const ColorWheelPicker(
      {super.key, required this.pick, required this.onChanged});

  @override
  State<ColorWheelPicker> createState() => _ColorWheelPickerState();
}

class _ColorWheelPickerState extends State<ColorWheelPicker> {
  bool _draggingHue = false;
  bool _draggingSV = false;
  static const double ringThickness = 28;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children:[
        LayoutBuilder(builder: (ctx, constraints) {
          final size = min(constraints.maxWidth, 320.0);
          final innerRadius = size / 2 - ringThickness - 6;
          final svSide = (innerRadius * sqrt2 * 0.96).clamp(44.0, size);

          return SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children:[
                // Hue Ring (Opaque HitTest prevents bottom sheet dragging)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) {
                    _draggingHue = true;
                    _updateHue(d.localPosition, size);
                  },
                  onPanUpdate: (d) {
                    if (_draggingHue) _updateHue(d.localPosition, size);
                  },
                  onPanEnd: (_) => _draggingHue = false,
                  child: CustomPaint(
                    size: Size(size, size),
                    painter: _HueRingPainter(ringThickness),
                  ),
                ),
                _buildHueCursor(size),

                // SV Square
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) {
                    _draggingSV = true;
                    _updateSV(d.localPosition, svSide);
                  },
                  onPanUpdate: (d) {
                    if (_draggingSV) _updateSV(d.localPosition, svSide);
                  },
                  onPanEnd: (_) => _draggingSV = false,
                  child: Container(
                    width: svSide,
                    height: svSide,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow:[
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: CustomPaint(
                        size: Size(svSide, svSide),
                        painter: _SVSquarePainter(widget.pick.h),
                      ),
                    ),
                  ),
                ),
                _buildSVCursor(svSide),
              ],
            ),
          );
        }),
        const SizedBox(height: 24),
        Row(
          children:[
            const Text('Opacity',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(width: 16),
            Expanded(
              child: Slider(
                value: widget.pick.a,
                onChanged: (v) {
                  widget.pick.a = v;
                  widget.onChanged();
                  setState(() {});
                },
              ),
            ),
            SizedBox(
              width: 48,
              child: Text('${(widget.pick.a * 100).round()}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children:[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: widget.pick.toColor(),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black12, width: 2),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children:[
                  _chip(widget.pick.toHex()),
                  _chip(widget.pick.toRgbaString()),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(text,
          style: const TextStyle(
              fontSize: 12, fontFamily: 'monospace', color: Colors.black87)),
    );
  }

  void _updateHue(Offset local, double size) {
    final cx = size / 2, cy = size / 2;
    final angle = atan2(local.dy - cy, local.dx - cx);
    widget.pick.h = (angle * 180 / pi + 360) % 360;
    widget.onChanged();
    setState(() {});
  }

  void _updateSV(Offset local, double side) {
    widget.pick.s = (local.dx / side).clamp(0, 1);
    widget.pick.v = (1 - local.dy / side).clamp(0, 1);
    widget.onChanged();
    setState(() {});
  }

  Widget _buildHueCursor(double size) {
    final r = size / 2 - ringThickness / 2 - 1;
    final th = widget.pick.h * pi / 180;
    final x = size / 2 + r * cos(th) - 10;
    final y = size / 2 + r * sin(th) - 10;
    return Positioned(
      left: x,
      top: y,
      child: IgnorePointer(
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: HSVColor.fromAHSV(1, widget.pick.h, 1, 1).toColor(),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow:[
              BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSVCursor(double svSide) {
    final cursorX = widget.pick.s * svSide - svSide / 2 - 10;
    final cursorY = (1 - widget.pick.v) * svSide - svSide / 2 - 10;
    return Positioned(
      left: null,
      top: null,
      child: Transform.translate(
        offset: Offset(cursorX, cursorY),
        child: IgnorePointer(
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: widget.pick.toColor().withOpacity(1),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow:[
                BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HueRingPainter extends CustomPainter {
  final double thickness;
  _HueRingPainter(this.thickness);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final r = size.width / 2 - thickness / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness;

    for (int deg = 0; deg < 360; deg++) {
      final a0 = (deg - 0.5) * pi / 180;
      final a1 = (deg + 1.5) * pi / 180;
      paint.color = HSVColor.fromAHSV(1, deg.toDouble(), 1, 1).toColor();
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        a0,
        a1 - a0,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SVSquarePainter extends CustomPainter {
  final double hue;
  _SVSquarePainter(this.hue);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect, Paint()..color = HSVColor.fromAHSV(1, hue, 1, 1).toColor());

    final whiteGrad = ui.Gradient.linear(
      Offset.zero,
      Offset(size.width, 0),[Colors.white, Colors.white.withOpacity(0)],
    );
    canvas.drawRect(rect, Paint()..shader = whiteGrad);

    final blackGrad = ui.Gradient.linear(
      Offset.zero,
      Offset(0, size.height),[Colors.black.withOpacity(0), Colors.black],
    );
    canvas.drawRect(rect, Paint()..shader = blackGrad);
  }

  @override
  bool shouldRepaint(covariant _SVSquarePainter old) => old.hue != hue;
}

// ═══════════════════ BRUSH PREVIEW ═══════════════════

class _BrushPreviewPainter extends CustomPainter {
  final BrushSettings b;
  _BrushPreviewPainter(this.b);

  @override
  void paint(Canvas canvas, Size size) {
    // Elegant dot-grid background
    final bgPaint = Paint()..color = Colors.grey.shade200;
    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16)),
        bgPaint);

    if (!b.ready || b.stampImage == null) return;

    double spacing = max(1.0, b.size * b.spacing);
    double carry = 0;
    Offset lastPoint = Offset(20, size.height / 2);

    for (double t = 0; t <= 1.0; t += 0.005) {
      double x = 20 + t * (size.width - 40);
      double y = size.height / 2 + sin(t * pi * 2) * 24;
      Offset pt = Offset(x, y);

      double dist = (pt - lastPoint).distance;
      double remaining = dist;

      while (carry + remaining >= spacing) {
        double step = spacing - carry;
        double ratio = step / dist;
        Offset stampPt = lastPoint + (pt - lastPoint) * ratio;

        canvas.save();
        canvas.translate(stampPt.dx, stampPt.dy);

        if (b.followAngle) {
          final dx = pt.dx - lastPoint.dx;
          final dy = pt.dy - lastPoint.dy;
          canvas.rotate(atan2(dy, dx) + b.angleOffsetDeg * pi / 180);
        } else {
          canvas.rotate(b.angleOffsetDeg * pi / 180);
        }

        final half = b.size / 2;
        canvas.drawImageRect(
          b.stampImage!,
          Rect.fromLTWH(0, 0, b.stampImage!.width.toDouble(),
              b.stampImage!.height.toDouble()),
          Rect.fromLTWH(-half, -half, b.size, b.size),
          Paint()
            ..color = b.color.withValues(alpha: b.flow)
            ..blendMode = b.blendMode
            ..filterQuality = FilterQuality.medium,
        );
        canvas.restore();

        remaining -= step;
        carry = 0;
        lastPoint = stampPt;
        dist = (pt - lastPoint).distance;
      }
      carry += remaining;
      lastPoint = pt;
    }
  }

  @override
  bool shouldRepaint(covariant _BrushPreviewPainter old) => true;
}

// ═══════════════════ BRUSH MODAL ═══════════════════

class _BrushModalBody extends StatefulWidget {
  final DrawingState state;
  const _BrushModalBody({required this.state});
  @override
  State<_BrushModalBody> createState() => _BrushModalBodyState();
}

class _BrushModalBodyState extends State<_BrushModalBody>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  BrushSettings get b => widget.state.brush;

  void _update() {
    widget.state.updateBrush();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (ctx, scrollController) {
        return Column(
          children:[
            _dragHandle(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children:[
                  _header('Studio Brush'),
                  const Spacer(),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.primary,
                    ),
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('Randomize',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    onPressed: () {
                      widget.state.randomizeSeed();
                      setState(() {});
                    },
                  ),
                ],
              ),
            ),
            // Preview Box
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: SizedBox(
                width: double.infinity,
                height: 100,
                child: CustomPaint(
                  painter: _BrushPreviewPainter(b),
                ),
              ),
            ),
            TabBar(
              controller: _tabCtrl,
              labelColor: Theme.of(context).colorScheme.primary,
              unselectedLabelColor: Colors.grey.shade600,
              indicatorColor: Theme.of(context).colorScheme.primary,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold),
              tabs: const[
                Tab(text: 'Dynamics'),
                Tab(text: 'Shape & Style'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children:[
                  _dynamicsTab(scrollController),
                  _shapeTab(scrollController),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _dynamicsTab(ScrollController sc) {
    return ListView(
      controller: sc,
      padding: const EdgeInsets.all(24),
      children:[
        _sectionTitle('Core Properties'),
        _slider('Size', b.size, 6, 1024, '${b.size.round()} px', (v) {
          b.size = v;
          _update();
        }),
        _slider('Spacing', b.spacing * 100, 5, 100,
            '${(b.spacing * 100).round()}%', (v) {
          b.spacing = v / 100;
          _update();
        }),
        _slider('Flow', b.flow * 100, 5, 100, '${(b.flow * 100).round()}%',
            (v) {
          b.flow = v / 100;
          _update();
        }),
        _slider('Smoothing', b.smoothing * 100, 0, 90,
            '${(b.smoothing * 100).round()}%', (v) {
          b.smoothing = v / 100;
          _update();
        }),
        const SizedBox(height: 24),
        _sectionTitle('Trajectory'),
        _slider('Angle smoothing', b.angleSmoothing * 100, 0, 90,
            '${(b.angleSmoothing * 100).round()}%', (v) {
          b.angleSmoothing = v / 100;
          _update();
        }),
        _slider('Angle offset', b.angleOffsetDeg, -180, 180,
            '${b.angleOffsetDeg.round()}°', (v) {
          b.angleOffsetDeg = v;
          _update();
        }),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Follow trajectory angle',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          value: b.followAngle,
          activeColor: Theme.of(context).colorScheme.primary,
          onChanged: (v) {
            b.followAngle = v;
            _update();
          },
        ),
        const SizedBox(height: 24),
        _sectionTitle('Jitter & Scatter'),
        _slider('Scatter radius', b.scatter * 100, 0, 100,
            '${(b.scatter * 100).round()}%', (v) {
          b.scatter = v / 100;
          _update();
        }),
        _slider('Size jitter', b.jitter.size * 100, 0, 50,
            '${(b.jitter.size * 100).round()}%', (v) {
          b.jitter.size = v / 100;
          _update();
        }),
        _slider('Angle jitter', b.jitter.angle, 0, 180,
            '${b.jitter.angle.round()}°', (v) {
          b.jitter.angle = v;
          _update();
        }),
        _slider('Opacity jitter', b.jitter.opacity * 100, 0, 100,
            '${(b.jitter.opacity * 100).round()}%', (v) {
          b.jitter.opacity = v / 100;
          _update();
        }),
      ],
    );
  }

  Widget _shapeTab(ScrollController sc) {
    final s = b.shape;
    return ListView(
      controller: sc,
      padding: const EdgeInsets.all(24),
      children:[
        _blendDropdown(),
        const SizedBox(height: 24),
        _sectionTitle('Shape Structure'),
        _slider('Symmetry folds', s.symmetry.toDouble(), 2, 5, '${s.symmetry}',
            (v) {
          s.symmetry = v.round();
          _update();
        }),
        _slider(
            'Complexity', s.complexity.toDouble(), 1, 30, '${s.complexity}',
            (v) {
          s.complexity = v.round();
          _update();
        }),
        _slider(
            'Density', s.density * 100, 0, 100, '${(s.density * 100).round()}%',
            (v) {
          s.density = v / 100;
          _update();
        }),
        _slider(
            'Organic', s.organic * 100, 0, 100, '${(s.organic * 100).round()}%',
            (v) {
          s.organic = v / 100;
          _update();
        }),
        _slider('Core density', s.core * 100, 0, 100,
            '${(s.core * 100).round()}%', (v) {
          s.core = v / 100;
          _update();
        }),
        _slider('Roundness', s.roundness * 100, 0, 100,
            '${(s.roundness * 100).round()}%', (v) {
          s.roundness = v / 100;
          _update();
        }),
        const SizedBox(height: 24),
        _sectionTitle('Texture & Shadow'),
        _slider('Softness', b.softness * 100, 0, 100,
            '${(b.softness * 100).round()}%', (v) {
          b.softness = v / 100;
          _update();
        }),
        _slider(
            'Feather', b.feather * 100, 0, 100, '${(b.feather * 100).round()}%',
            (v) {
          b.feather = v / 100;
          _update();
        }),
        _slider('Grain', b.grain * 100, 0, 100, '${(b.grain * 100).round()}%',
            (v) {
          b.grain = v / 100;
          _update();
        }),
        _slider('Shadow size', s.shadowSize * 100, 0, 100,
            '${(s.shadowSize * 100).round()}%', (v) {
          s.shadowSize = v / 100;
          _update();
        }),
        _slider('Shadow opacity', s.shadowOpacity * 100, 0, 100,
            '${(s.shadowOpacity * 100).round()}%', (v) {
          s.shadowOpacity = v / 100;
          _update();
        }),
      ],
    );
  }

  Widget _blendDropdown() {
    final modes = {
      BlendMode.srcOver: 'Normal',
      BlendMode.multiply: 'Multiply',
      BlendMode.screen: 'Screen',
      BlendMode.overlay: 'Overlay',
      BlendMode.plus: 'Add / Glow',
    };
    return Row(
      children:[
        const Text('Blend Mode',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: DropdownButton<BlendMode>(
            value: b.blendMode,
            isDense: true,
            underline: const SizedBox(),
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
            items: modes.entries
                .map((e) => DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500))))
                .toList(),
            onChanged: (v) {
              if (v != null) {
                b.blendMode = v;
                _update();
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _slider(String label, double value, double min, double max,
      String display, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children:[
              Text(label,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500)),
              const Spacer(),
              Text(display,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary)),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackShape: const RoundedRectSliderTrackShape(),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════ LAYERS PANEL ═══════════════════

class _LayersPanelBody extends StatefulWidget {
  final DrawingState state;
  const _LayersPanelBody({required this.state});
  @override
  State<_LayersPanelBody> createState() => _LayersPanelBodyState();
}

class _LayersPanelBodyState extends State<_LayersPanelBody> {
  DrawingState get s => widget.state;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (ctx, scrollController) {
        return Column(
          children:[
            _dragHandle(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children:[
                  _header('Layers'),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add_box_rounded, size: 28),
                    color: Theme.of(context).colorScheme.primary,
                    onPressed: () {
                      s.addLayer();
                      setState(() {});
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Background color row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children:[
                  const Text('Background Color',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _pickBackgroundColor(context),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: s.backgroundColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.black26, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: Colors.grey.shade200, thickness: 1.5, height: 24),
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollController: scrollController,
                itemCount: s.layers.length,
                onReorder: (oldIdx, newIdx) {
                  final rOld = s.layers.length - 1 - oldIdx;
                  var rNew = s.layers.length - 1 - newIdx;
                  if (rOld < rNew) rNew++;
                  s.reorderLayer(rOld, rNew.clamp(0, s.layers.length));
                  setState(() {});
                },
                itemBuilder: (ctx, index) {
                  final rIdx = s.layers.length - 1 - index;
                  final l = s.layers[rIdx];
                  final isActive = rIdx == s.activeLayerIndex;

                  return Container(
                    key: ValueKey(l.id),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: isActive
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isActive
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.shade300,
                        width: isActive ? 2 : 1,
                      ),
                      boxShadow:[
                        if (isActive)
                          BoxShadow(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          s.selectLayer(rIdx);
                          setState(() {});
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children:[
                              // Visibility Checkbox
                              GestureDetector(
                                onTap: () {
                                  s.toggleLayerVisibility(l.id);
                                  setState(() {});
                                },
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: l.visible
                                        ? Colors.black87
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: l.visible
                                          ? Colors.black87
                                          : Colors.grey.shade400,
                                      width: 2,
                                    ),
                                  ),
                                  child: l.visible
                                      ? const Icon(Icons.check,
                                          size: 20, color: Colors.white)
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 16),
                              // Live Thumbnail
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.black12),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(7),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children:[
                                      Container(color: s.backgroundColor),
                                      if (l.cachedImage != null)
                                        RawImage(
                                          image: l.cachedImage,
                                          fit: BoxFit.contain,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              // Meta Info
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children:[
                                    Text(l.name,
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    Text(
                                        '${_blendName(l.blendMode)} • ${(l.opacity * 100).round()}%',
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade600,
                                            fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                              // Settings & Drag
                              IconButton(
                                icon: const Icon(Icons.settings, size: 22),
                                color: Colors.grey.shade700,
                                onPressed: () => _showLayerSettings(context, l),
                              ),
                              const Icon(Icons.drag_indicator_rounded,
                                  color: Colors.grey),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  void _pickBackgroundColor(BuildContext context) {
    final colors =[
      Colors.white,
      Colors.black,
      const Color(0xFFF0F0F0),
      const Color(0xFF1E1E2C),
      const Color(0xFFFDF6E3), // Warm
      const Color(0xFF2B3A42), // Slate
      const Color(0xFFE8D5B7), // Paper
    ];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Background Color',
            style: TextStyle(fontWeight: FontWeight.bold)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: colors.map((c) {
            return GestureDetector(
              onTap: () {
                s.backgroundColor = c;
                s.notifyListeners();
                setState(() {});
                Navigator.pop(ctx);
              },
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black26, width: 2),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showLayerSettings(BuildContext context, DrawingLayer l) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: _LayerSettingsBody(
              state: s, layer: l, onUpdate: () => setState(() {})),
        ),
      ),
    );
  }

  String _blendName(BlendMode m) {
    switch (m) {
      case BlendMode.srcOver:
        return 'Normal';
      case BlendMode.multiply:
        return 'Multiply';
      case BlendMode.screen:
        return 'Screen';
      case BlendMode.overlay:
        return 'Overlay';
      case BlendMode.plus:
        return 'Add';
      case BlendMode.darken:
        return 'Darken';
      case BlendMode.lighten:
        return 'Lighten';
      case BlendMode.colorDodge:
        return 'Dodge';
      case BlendMode.colorBurn:
        return 'Burn';
      default:
        return m.name;
    }
  }
}

// ═══════════════════ LAYER SETTINGS ═══════════════════

class _LayerSettingsBody extends StatefulWidget {
  final DrawingState state;
  final DrawingLayer layer;
  final VoidCallback onUpdate;
  const _LayerSettingsBody(
      {required this.state, required this.layer, required this.onUpdate});
  @override
  State<_LayerSettingsBody> createState() => _LayerSettingsBodyState();
}

class _LayerSettingsBodyState extends State<_LayerSettingsBody> {
  late TextEditingController _nameCtrl;
  DrawingLayer get l => widget.layer;
  DrawingState get s => widget.state;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: l.name);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allModes = {
      BlendMode.srcOver: 'Normal',
      BlendMode.multiply: 'Multiply',
      BlendMode.screen: 'Screen',
      BlendMode.overlay: 'Overlay',
      BlendMode.darken: 'Darken',
      BlendMode.lighten: 'Lighten',
      BlendMode.colorDodge: 'Color Dodge',
      BlendMode.colorBurn: 'Color Burn',
      BlendMode.difference: 'Difference',
      BlendMode.plus: 'Add (Glow)',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children:[
          _dragHandle(),
          _header('Layer Settings'),
          const SizedBox(height: 24),
          TextField(
            controller: _nameCtrl,
            style: const TextStyle(fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              labelText: 'Layer Name',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              isDense: true,
            ),
            onChanged: (v) {
              s.updateLayerSettings(l.id, name: v);
              widget.onUpdate();
            },
          ),
          const SizedBox(height: 24),
          Row(
            children:[
              const Text('Opacity',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              Expanded(
                child: Slider(
                  value: l.opacity,
                  onChanged: (v) {
                    s.updateLayerSettings(l.id, opacity: v);
                    widget.onUpdate();
                    setState(() {});
                  },
                ),
              ),
              SizedBox(
                width: 48,
                child: Text('${(l.opacity * 100).round()}%',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children:[
              const Text('Blend Mode',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: DropdownButton<BlendMode>(
                  value: l.blendMode,
                  isDense: true,
                  underline: const SizedBox(),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  items: allModes.entries
                      .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w500))))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      s.updateLayerSettings(l.id, blendMode: v);
                      widget.onUpdate();
                      setState(() {});
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children:[
              const Text('Mask',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const Spacer(),
              SegmentedButton<String>(
                segments: const[
                  ButtonSegment(
                      value: 'none',
                      label: Text('None', style: TextStyle(fontSize: 13))),
                  ButtonSegment(
                      value: 'alpha',
                      label: Text('Alpha', style: TextStyle(fontSize: 13))),
                  ButtonSegment(
                      value: 'alpha-invert',
                      label: Text('Invert', style: TextStyle(fontSize: 13))),
                ],
                selected: {l.maskMode},
                onSelectionChanged: (v) {
                  s.updateLayerSettings(l.id, maskMode: v.first);
                  widget.onUpdate();
                  setState(() {});
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          if (s.layers.length > 1)
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade50,
                  foregroundColor: Colors.red.shade700,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Delete Layer',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                onPressed: () {
                  s.removeLayer(l.id);
                  widget.onUpdate();
                  Navigator.pop(context);
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════ COMMON HELPERS ═══════════════════

Widget _dragHandle() {
  return Center(
    child: Container(
      margin: const EdgeInsets.only(bottom: 24, top: 8),
      width: 40,
      height: 5,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(10),
      ),
    ),
  );
}

Widget _header(String text) => Text(text,
    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold));

Widget _sectionTitle(String text) => Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(text.toUpperCase(),
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: Colors.grey.shade500)),
    );
