import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:forge2d/forge2d.dart' as f2;

import '../models/game.dart';
import '../services/glyph_profiler.dart';

const String kGarbleFontFamily = 'Garble';

// Draw the Forge2D collision polygons + body centroids on top of the
// glyphs. Useful when tuning silhouette padding or polygon slicing.
const bool kDebugDrawBodies = false;

// How aggressively to align letters by silhouette centre-of-gravity vs
// shared baseline. 0 = pure baseline alignment (identical Y for every
// paragraph origin). 1 = pure COG alignment (every body's centroid sits
// on the same horizontal line, so top-heavy glyphs like T drop, bottom-
// heavy glyphs like L rise). >1 exaggerates the effect for stronger
// nestling. The exiting letter still flies relative to its current Y.
const double kCogAlignmentBias = 1.4;

// Maximum static tilt applied to each glyph at spawn (radians). Each
// letter gets a deterministic angle in [-amp, +amp] driven by a hash of
// its character + position, so adjacent letters typically tilt in
// opposite directions and their tilted silhouettes nestle more tightly
// when compression squeezes the row. Bodies stay at fixedRotation so
// order is still preserved.
const double kAngleAmplitudeRad = 0.3; // ≈17.2°

// Logical-pixel gap kept between the row and each side of the stage. The
// requested font size is scaled down at spawn so the assembled glyph row
// always fits within `stage.width - 2 * kHorizontalPadding`.
const double kHorizontalPadding = 16.0;

class GarbleStage extends StatefulWidget {
  final GameController controller;
  final double height;
  final double fontSize;

  const GarbleStage({
    super.key,
    required this.controller,
    this.height = 140,
    this.fontSize = 96,
  });

  @override
  State<GarbleStage> createState() => _GarbleStageState();
}

class _Letter {
  final int index;
  final String char;
  final GlyphProfile profile;
  final f2.Body body;

  // Body-local offset from the body's origin (silhouette centroid) back
  // to the glyph's paragraph origin (baseline-left). Used at paint and
  // hit-test time so the glyph aligns with the body even though Forge2D
  // positions the body at its centre of mass.
  final f2.Vector2 paintOffset;

  // Stage-local Y the spring should pull this letter's paragraph origin to.
  // Differs slightly per glyph (see kBaselineNudgeRaster) so adjacent
  // letters nestle into each other's silhouette tilts.
  final double targetY;

  double alpha = 1;
  bool exiting = false;
  double exitGravity = 0; // signed: + down, - up

  _Letter({
    required this.index,
    required this.char,
    required this.profile,
    required this.body,
    required this.paintOffset,
    required this.targetY,
  });
}

class _GarbleStageState extends State<GarbleStage>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  late final f2.World _world;
  late List<_Letter?> _letters;
  int _lastMask = 0;
  Size? _lastSize;
  bool _profilesReady = false;
  bool _profilesRequested = false;
  final math.Random _rng = math.Random();

  // Font size actually used for the current spawn — equals widget.fontSize
  // unless the row had to be shrunk to fit the stage width.
  late double _effectiveFontSize = widget.fontSize;

  // Each settling letter is pulled horizontally toward the row's centre.
  // Outer letters squeeze inner letters; the silhouette collision polygons
  // resolve the bunching. Order is preserved by construction because
  // bodies have fixed rotation and convex polygons can't pass through
  // each other along a single line.
  static const double _compressionStiffness = 22.0;
  static const double _baselineStiffness = 80.0;
  static const double _maxDisplacement = 60.0;

  // Number of horizontal slabs per silhouette. More slices ≈ more
  // faithful collision shape; cost is O(slices²) for contact pairs.
  static const int _polygonSlices = 12;

  @override
  void initState() {
    super.initState();
    _world = f2.World(f2.Vector2.zero());
    _letters = List<_Letter?>.filled(
      widget.controller.level.garble.length,
      null,
    );
    _lastMask = widget.controller.mask;
    widget.controller.addListener(_onControllerChanged);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_profilesRequested) {
      _profilesRequested = true;
      _loadProfiles();
    }
  }

  Future<void> _loadProfiles() async {
    final chars = widget.controller.level.garble.split('').toSet();
    // Force the engine to load the Garble font before rasterising — without
    // this the profiler can capture fallback glyphs.
    final warmup = TextPainter(
      text: TextSpan(
        text: chars.join(),
        style: const TextStyle(fontFamily: kGarbleFontFamily, fontSize: 64),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    warmup.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 16));
    await GlyphProfiler.instance.profileAll(chars, kGarbleFontFamily);
    if (!mounted) return;
    setState(() {
      _profilesReady = true;
    });
    _spawnAll();
  }

  @override
  void dispose() {
    _ticker.dispose();
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    final newMask = widget.controller.mask;
    if (newMask == _lastMask) return;
    final fullMask = (1 << widget.controller.level.garble.length) - 1;
    if (newMask == fullMask && _lastMask != fullMask) {
      _destroyAll();
      _lastMask = newMask;
      _spawnAll();
      return;
    }
    final dropped = _lastMask & ~newMask;
    for (var i = 0; i < _letters.length; i++) {
      if ((dropped & (1 << i)) != 0) {
        final l = _letters[i];
        if (l != null && !l.exiting) _launchExit(l);
      }
    }
    _lastMask = newMask;
  }

  void _destroyAll() {
    for (var i = 0; i < _letters.length; i++) {
      final l = _letters[i];
      if (l != null) _world.destroyBody(l.body);
      _letters[i] = null;
    }
  }

  void _launchExit(_Letter l) {
    l.exiting = true;
    final dirSign = _rng.nextBool() ? -1.0 : 1.0;
    final speed = 700.0 + _rng.nextDouble() * 400.0;
    l.body.linearVelocity = f2.Vector2(
      (_rng.nextDouble() - 0.5) * 280.0,
      dirSign * speed,
    );
    l.exitGravity = dirSign * 2400.0;
    // Allow tumble during the exit for a bit of life.
    l.body.setFixedRotation(false);
    l.body.angularVelocity = (_rng.nextDouble() - 0.5) * 10.0;
    // Stop colliding with the row so the exit doesn't shove its
    // neighbours sideways as it leaves.
    for (final fixture in l.body.fixtures) {
      final filter = fixture.filterData;
      filter.maskBits = 0;
      fixture.filterData = filter;
    }
  }

  void _spawnAll() {
    final size = _lastSize;
    if (size == null || !_profilesReady) return;

    final garble = widget.controller.level.garble;
    var scale = widget.fontSize / GlyphProfile.rasterReferenceSize;
    final mask = widget.controller.mask;

    final activeIndices = <int>[];
    for (var i = 0; i < garble.length; i++) {
      if ((mask & (1 << i)) != 0) activeIndices.add(i);
    }
    if (activeIndices.isEmpty) return;

    // Lay letters out side-by-side using the silhouette-aware advance,
    // then centre the row horizontally on screen. Letters spawn already
    // at their tightest no-overlap arrangement; the compression force
    // just keeps them there as the row evolves.
    final origins = <double>[0];
    for (var k = 1; k < activeIndices.length; k++) {
      final prev = GlyphProfiler.instance.cached(
        garble[activeIndices[k - 1]],
        kGarbleFontFamily,
      )!;
      final cur = GlyphProfiler.instance.cached(
        garble[activeIndices[k]],
        kGarbleFontFamily,
      )!;
      origins.add(origins.last + _silhouetteAdvance(prev, cur, scale));
    }
    final lastP = GlyphProfiler.instance.cached(
      garble[activeIndices.last],
      kGarbleFontFamily,
    )!;
    var assemblyWidth = origins.last + lastP.inkBounds.width * scale;

    // If the row is wider than the stage (minus side padding), shrink the
    // whole assembly uniformly so it fits. Origins, advances and the
    // upcoming silhouette slices are all linear in `scale`, so a single
    // multiplicative correction is exact.
    final maxWidth = size.width - 2 * kHorizontalPadding;
    if (assemblyWidth > maxWidth && maxWidth > 0) {
      final fit = maxWidth / assemblyWidth;
      scale *= fit;
      for (var k = 0; k < origins.length; k++) {
        origins[k] *= fit;
      }
      assemblyWidth *= fit;
    }
    _effectiveFontSize = scale * GlyphProfile.rasterReferenceSize;

    final shift = (size.width - assemblyWidth) / 2;
    final baselineY = size.height * 0.7;

    // Pre-compute each glyph's silhouette centroid so we can align the
    // row by centre-of-gravity rather than baseline. centroid.y is in
    // stage-local pixels, baseline-relative (negative = above baseline).
    final centroids = <f2.Vector2>[];
    for (final idx in activeIndices) {
      final profile = GlyphProfiler.instance.cached(
        garble[idx],
        kGarbleFontFamily,
      )!;
      final slices = _buildPolygonSlices(profile, scale);
      centroids.add(_silhouetteCentroid(slices));
    }
    var avgCentroidY = 0.0;
    for (final c in centroids) {
      avgCentroidY += c.y;
    }
    avgCentroidY /= centroids.length;

    for (var k = 0; k < activeIndices.length; k++) {
      final idx = activeIndices[k];
      final ch = garble[idx];
      final profile = GlyphProfiler.instance.cached(ch, kGarbleFontFamily)!;
      // Pull this glyph's paragraph origin so its centroid lands on the
      // shared COG line (with a tunable bias). At bias=1 every body sits
      // at body.position.y = baselineY + avgCentroidY, so a top-heavy
      // letter (T, F) drops and a bottom-heavy letter (L, J) rises —
      // adjacent silhouettes naturally nestle into each other's tilt.
      final cogShift = (avgCentroidY - centroids[k].y) * kCogAlignmentBias;
      final letterBaselineY = baselineY + cogShift;
      _letters[idx] = _createLetter(
        index: idx,
        char: ch,
        profile: profile,
        scale: scale,
        originX: origins[k] + shift,
        baselineY: letterBaselineY,
        angle: _letterAngle(idx, ch),
        precomputedCentroid: centroids[k],
        precomputedSlices: null,
      );
    }
  }

  // Deterministic per-letter angle in [-kAngleAmplitudeRad, +kAngleAmplitudeRad].
  // Same character at the same position always picks the same tilt, so the
  // row is stable across re-spawns; varying both index and codepoint means
  // adjacent letters usually tilt in opposite directions and let their
  // angled silhouettes nestle when compression squeezes the row.
  double _letterAngle(int idx, String ch) {
    final h = (idx * 31 + ch.codeUnitAt(0) * 17 + 13) % 200;
    final t = h / 199.0; // [0, 1]
    return (t - 0.5) * 2 * kAngleAmplitudeRad;
  }

  // Area-weighted centroid of a multi-slice silhouette in paragraph-origin
  // space (x = pixels right of paragraph origin, y = pixels below baseline).
  f2.Vector2 _silhouetteCentroid(List<List<f2.Vector2>> slices) {
    if (slices.isEmpty) return f2.Vector2.zero();
    var totalArea = 0.0;
    var cx = 0.0, cy = 0.0;
    for (final s in slices) {
      final a = _polyArea(s);
      final c = _polyCentroid(s);
      totalArea += a;
      cx += c.x * a;
      cy += c.y * a;
    }
    if (totalArea == 0) return f2.Vector2.zero();
    return f2.Vector2(cx / totalArea, cy / totalArea);
  }

  // Smallest gap-free advance between two adjacent paragraph origins
  // at the given scale. The profiles are already inflated by
  // GlyphProfiler.kSilhouettePaddingRaster on each side, so the resulting
  // advance bakes in the desired visual gap.
  double _silhouetteAdvance(GlyphProfile prev, GlyphProfile cur, double scale) {
    var maxOverlap = 0.0;
    for (var s = 0; s < prev.sampleRows; s++) {
      final candidate = prev.rightProfile[s] - cur.leftProfile[s];
      if (candidate > maxOverlap) maxOverlap = candidate;
    }
    return maxOverlap * scale;
  }

  _Letter _createLetter({
    required int index,
    required String char,
    required GlyphProfile profile,
    required double scale,
    required double originX,
    required double baselineY,
    double angle = 0,
    f2.Vector2? precomputedCentroid,
    List<List<f2.Vector2>>? precomputedSlices,
  }) {
    final slices = precomputedSlices ?? _buildPolygonSlices(profile, scale);
    if (slices.isEmpty) {
      // Empty/space glyph — give it a tiny dot so it still has mass.
      slices.add([
        f2.Vector2(0, -4),
        f2.Vector2(4, -4),
        f2.Vector2(4, 0),
        f2.Vector2(0, 0),
      ]);
    }

    final centroid = precomputedCentroid ?? _silhouetteCentroid(slices);

    // Body position is the silhouette centroid in world space. The body
    // is rotated by `angle` around the centroid, so to make the paragraph
    // origin land at (originX, baselineY) the centroid must be offset by
    // R(angle) * centroid_local from the paragraph origin.
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);
    final bodyPosX = originX + cosA * centroid.x - sinA * centroid.y;
    final bodyPosY = baselineY + sinA * centroid.x + cosA * centroid.y;

    final bodyDef = f2.BodyDef()
      ..type = f2.BodyType.dynamic
      ..position = f2.Vector2(bodyPosX, bodyPosY)
      ..angle = angle
      ..linearDamping = 5.0
      ..fixedRotation = true
      ..allowSleep = false;
    final body = _world.createBody(bodyDef);

    for (final slice in slices) {
      final localVerts = slice
          .map((p) => f2.Vector2(p.x - centroid.x, p.y - centroid.y))
          .toList();
      if (_distinctCount(localVerts) < 3) continue;
      final shape = f2.PolygonShape()..set(localVerts);
      body.createFixture(
        f2.FixtureDef(shape)
          ..density = 0.02
          ..friction = 0.4
          ..restitution = 0.0,
      );
    }

    return _Letter(
      index: index,
      char: char,
      profile: profile,
      body: body,
      paintOffset: f2.Vector2(-centroid.x, -centroid.y),
      targetY: baselineY,
    );
  }

  // Decompose the silhouette into horizontal trapezoid slabs. Each slab
  // is convex and Forge2D can collide multi-fixture bodies, so the union
  // approximates the glyph shape (including concavities like A's wedge).
  List<List<f2.Vector2>> _buildPolygonSlices(GlyphProfile p, double scale) {
    final ink = p.inkBounds;
    final n = p.sampleRows;
    final slices = <List<f2.Vector2>>[];
    final stepRows = math.max(1, (n / _polygonSlices).ceil());
    for (var s = 0; s < n - 1; s += stepRows) {
      final s2 = math.min(n - 1, s + stepRows);
      final tA = n == 1 ? 0.5 : s / (n - 1);
      final tB = n == 1 ? 0.5 : s2 / (n - 1);
      final yA = (ink.top + tA * ink.height) * scale;
      final yB = (ink.top + tB * ink.height) * scale;
      final lA = p.leftProfile[s] * scale;
      final lB = p.leftProfile[s2] * scale;
      final rA = p.rightProfile[s] * scale;
      final rB = p.rightProfile[s2] * scale;
      // Skip slabs that are empty on both edges (e.g. row inside an "A").
      if ((rA - lA) < 0.5 && (rB - lB) < 0.5) continue;
      // Counter-clockwise in screen space (y down):
      //   top-left → top-right → bottom-right → bottom-left
      slices.add([
        f2.Vector2(lA, yA),
        f2.Vector2(rA, yA),
        f2.Vector2(rB, yB),
        f2.Vector2(lB, yB),
      ]);
    }
    return slices;
  }

  double _polyArea(List<f2.Vector2> pts) {
    var a = 0.0;
    for (var i = 0; i < pts.length; i++) {
      final j = (i + 1) % pts.length;
      a += pts[i].x * pts[j].y - pts[j].x * pts[i].y;
    }
    return a.abs() / 2;
  }

  f2.Vector2 _polyCentroid(List<f2.Vector2> pts) {
    var x = 0.0, y = 0.0;
    for (final p in pts) {
      x += p.x;
      y += p.y;
    }
    return f2.Vector2(x / pts.length, y / pts.length);
  }

  int _distinctCount(List<f2.Vector2> pts) {
    var c = 0;
    for (var i = 0; i < pts.length; i++) {
      var dup = false;
      for (var j = 0; j < i; j++) {
        if ((pts[i] - pts[j]).length < 0.25) {
          dup = true;
          break;
        }
      }
      if (!dup) c++;
    }
    return c;
  }

  void _applyControlForces() {
    final size = _lastSize;
    if (size == null) return;
    final centerX = size.width / 2;
    for (var i = 0; i < _letters.length; i++) {
      final l = _letters[i];
      if (l == null) continue;
      final m = l.body.mass;
      if (l.exiting) {
        l.body.applyForce(f2.Vector2(0, l.exitGravity * m));
        continue;
      }
      // Compress horizontally toward the row's centre and spring vertically
      // to this letter's nudged baseline. Compression bunches the row;
      // collision polygons (= silhouette curves) keep glyphs apart; the
      // per-letter Y nudge lets neighbours nestle into each other's tilt.
      final dx = (centerX - l.body.position.x).clamp(
        -_maxDisplacement,
        _maxDisplacement,
      );
      // Paragraph origin Y in world = body.position.y + (paintOffset rotated
      // by the body's angle).y — needed because each letter has a static
      // tilt baked in at spawn.
      final cosA = math.cos(l.body.angle);
      final sinA = math.sin(l.body.angle);
      final paragraphY =
          l.body.position.y + sinA * l.paintOffset.x + cosA * l.paintOffset.y;
      final dy = (l.targetY - paragraphY).clamp(
        -_maxDisplacement,
        _maxDisplacement,
      );
      l.body.applyForce(
        f2.Vector2(dx * _compressionStiffness * m, dy * _baselineStiffness * m),
      );
    }
  }

  void _onTick(Duration elapsed) {
    if (_lastTick == Duration.zero) {
      _lastTick = elapsed;
      return;
    }
    var dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0) return;
    if (dt > 1 / 30) dt = 1 / 30;

    if (_lastSize == null) {
      setState(() {});
      return;
    }

    // Single-step physics. Box2D clears applied forces at the end of each
    // step, so we apply the control forces fresh every tick.
    _applyControlForces();
    _world.stepDt(dt);

    // Fade out exiting letters.
    for (var i = 0; i < _letters.length; i++) {
      final l = _letters[i];
      if (l == null) continue;
      if (l.exiting) {
        l.alpha = math.max(0, l.alpha - dt * 4);
      }
    }

    // Cull off-screen / faded exiting bodies.
    final size = _lastSize!;
    final cullTop = -size.height * 1.5;
    final cullBot = size.height * 2.5;
    for (var i = 0; i < _letters.length; i++) {
      final l = _letters[i];
      if (l == null || !l.exiting) continue;
      final y = l.body.position.y;
      if (y < cullTop || y > cullBot || l.alpha <= 0.01) {
        _world.destroyBody(l.body);
        _letters[i] = null;
      }
    }

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final restColor = theme.colorScheme.primary;
    final wordColor = theme.colorScheme.onSurface;
    final highlighted = widget.controller.currentIsWord;

    return RepaintBoundary(
      child: SizedBox(
        height: widget.height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, widget.height);
            final sizeChanged =
                _lastSize == null ||
                _lastSize!.width != size.width ||
                _lastSize!.height != size.height;
            _lastSize = size;
            if (sizeChanged && _profilesReady) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                if (_letters.every((l) => l == null)) {
                  _spawnAll();
                }
                // If letters already exist, the centre-pull force naturally
                // re-bunches them around the new centre on subsequent ticks.
              });
            }
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: _handleTapDown,
              child: Semantics(
                container: true,
                label: 'Garble: ${widget.controller.currentLetters}',
                child: CustomPaint(
                  size: size,
                  painter: _GarblePainter(
                    letters: _letters,
                    fontSize: _effectiveFontSize,
                    color: restColor,
                    glow: wordColor,
                    highlighted: highlighted,
                    family: kGarbleFontFamily,
                    profilesReady: _profilesReady,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.controller.gameOver) return;
    if (!_profilesReady) return;
    final hit = _hitTest(details.localPosition);
    if (hit == null) return;
    widget.controller.pop(hit);
  }

  int? _hitTest(Offset p) {
    final scale = _effectiveFontSize / GlyphProfile.rasterReferenceSize;
    for (var i = _letters.length - 1; i >= 0; i--) {
      final l = _letters[i];
      if (l == null || l.exiting) continue;
      // Each settling body has a static tilt baked in. Find paragraph
      // origin in world via the rotated paint offset, then inverse-rotate
      // the tap so the ink-bounds compare happens in glyph-local space.
      final cosA = math.cos(l.body.angle);
      final sinA = math.sin(l.body.angle);
      final originX =
          l.body.position.x + cosA * l.paintOffset.x - sinA * l.paintOffset.y;
      final originY =
          l.body.position.y + sinA * l.paintOffset.x + cosA * l.paintOffset.y;
      final dx = p.dx - originX;
      final dy = p.dy - originY;
      final lx = cosA * dx + sinA * dy;
      final ly = -sinA * dx + cosA * dy;
      final ink = l.profile.inkBounds;
      const pad = 6.0;
      if (lx >= ink.left * scale - pad &&
          lx <= ink.right * scale + pad &&
          ly >= ink.top * scale - pad &&
          ly <= ink.bottom * scale + pad) {
        return i;
      }
    }
    return null;
  }
}

class _GarblePainter extends CustomPainter {
  final List<_Letter?> letters;
  final double fontSize;
  final Color color;
  final Color glow;
  final bool highlighted;
  final String family;
  final bool profilesReady;

  _GarblePainter({
    required this.letters,
    required this.fontSize,
    required this.color,
    required this.glow,
    required this.highlighted,
    required this.family,
    required this.profilesReady,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!profilesReady) return;
    for (var i = 0; i < letters.length; i++) {
      final l = letters[i];
      if (l == null) continue;
      _paintLetter(canvas, l);
    }
    if (kDebugDrawBodies) {
      for (var i = 0; i < letters.length; i++) {
        final l = letters[i];
        if (l == null) continue;
        _paintDebug(canvas, l, i);
      }
    }
  }

  void _paintLetter(Canvas canvas, _Letter l) {
    final isHighlit = highlighted && !l.exiting;
    final paintColor = (isHighlit ? glow : color).withValues(
      alpha: l.alpha.clamp(0.0, 1.0),
    );
    final tp = TextPainter(
      text: TextSpan(
        text: l.char,
        style: TextStyle(
          color: paintColor,
          fontSize: fontSize,
          fontFamily: family,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final baselineFromTop = tp.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    canvas.save();
    // Body position is the silhouette centroid in world space. Translate
    // there, rotate (only nonzero for exiting bodies), then offset to
    // the glyph's paragraph origin and paint.
    canvas.translate(l.body.position.x, l.body.position.y);
    if (l.body.angle != 0) canvas.rotate(l.body.angle);
    canvas.translate(l.paintOffset.x, l.paintOffset.y);
    tp.paint(canvas, Offset(0, -baselineFromTop));
    canvas.restore();
    tp.dispose();
  }

  void _paintDebug(Canvas canvas, _Letter l, int index) {
    final hsv = HSVColor.fromAHSV(
      1.0,
      (index * 47.0) % 360,
      0.85,
      l.exiting ? 0.6 : 1.0,
    );
    final stroke = Paint()
      ..color = hsv.toColor()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final centroidDot = Paint()..color = hsv.toColor();

    canvas.save();
    canvas.translate(l.body.position.x, l.body.position.y);
    if (l.body.angle != 0) canvas.rotate(l.body.angle);
    for (final fixture in l.body.fixtures) {
      final shape = fixture.shape;
      if (shape is! f2.PolygonShape) continue;
      final verts = shape.vertices;
      if (verts.isEmpty) continue;
      final path = Path()..moveTo(verts[0].x, verts[0].y);
      for (var v = 1; v < verts.length; v++) {
        path.lineTo(verts[v].x, verts[v].y);
      }
      path.close();
      canvas.drawPath(path, stroke);
    }
    canvas.drawCircle(Offset.zero, 3, centroidDot);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GarblePainter old) => true;
}
