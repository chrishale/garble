import 'dart:async';
import 'dart:ui' as ui;

/// A measured silhouette of a single glyph.
///
/// Coordinates are normalised in EM-style space: x in [0, advance], y is
/// distance below the baseline (positive = down, like screen space).
/// `unitsPerEm` is the y-extent used for normalisation, so callers scale
/// everything by `(targetEm / unitsPerEm) * fontSize` at render time.
class GlyphProfile {
  static const double rasterReferenceSize = 384;

  final String char;
  final String fontFamily;

  // Tight ink bounds in baseline-relative pixels (raster space).
  // top is negative for ascenders; bottom is positive for descenders.
  final ui.Rect inkBounds;

  // Per-row leftmost and rightmost ink x within inkBounds.
  // Length = sampleRows; index 0 is top of inkBounds, last is bottom.
  // Values are baseline-relative x in raster pixels.
  final List<double> leftProfile;
  final List<double> rightProfile;

  // Slope of a least-squares fit over the middle 60% of each edge,
  // expressed as dx/dy (positive = edge leans right as y increases).
  final double dominantLeftSlope;
  final double dominantRightSlope;

  // R² of the fit; values < 0.7 indicate the edge is too curved to treat
  // as a straight slope (e.g. O, C, S) — callers should fall back to 0.
  final double slopeConfidenceLeft;
  final double slopeConfidenceRight;

  // The font size used when rasterising; profile coords scale linearly with it.
  final double rasterFontSize;

  // Horizontal advance used during rasterisation (paragraph width).
  final double advanceWidth;

  const GlyphProfile({
    required this.char,
    required this.fontFamily,
    required this.inkBounds,
    required this.leftProfile,
    required this.rightProfile,
    required this.dominantLeftSlope,
    required this.dominantRightSlope,
    required this.slopeConfidenceLeft,
    required this.slopeConfidenceRight,
    required this.rasterFontSize,
    required this.advanceWidth,
  });

  int get sampleRows => leftProfile.length;
}

class GlyphProfiler {
  GlyphProfiler._();
  static final GlyphProfiler instance = GlyphProfiler._();

  static const double _rasterFontSize = 384;
  static const int _rasterSize = 512;
  static const int _sampleRows = 64;
  static const int _alphaThreshold = 24;

  /// Pixels (raster-space) of padding added to every silhouette on each
  /// side. Bakes the visual gap between adjacent letters into the profile
  /// so collision physics enforces it directly — no runtime per-pair
  /// spacing math required. At fontSize=96 (renderScale=0.25), each
  /// raster pixel of padding becomes 0.25 px of visual gap, so 20 here
  /// ≈ 10 px between adjacent letters' visible ink edges. Tweak this
  /// to change the row spacing.
  static const double kSilhouettePaddingRaster = 20.0;

  final Map<String, GlyphProfile> _cache = {};
  final Map<String, Future<GlyphProfile>> _inFlight = {};

  String _key(String char, String family) => '$family::$char';

  GlyphProfile? cached(String char, String family) => _cache[_key(char, family)];

  Future<GlyphProfile> profile(String char, String family) {
    final key = _key(char, family);
    final hit = _cache[key];
    if (hit != null) return Future.value(hit);
    final pending = _inFlight[key];
    if (pending != null) return pending;
    final future = _profile(char, family).then((p) {
      _cache[key] = p;
      return p;
    }).whenComplete(() {
      _inFlight.remove(key);
    });
    _inFlight[key] = future;
    return future;
  }

  Future<void> profileAll(Iterable<String> chars, String family) async {
    final futures = <Future<void>>[];
    for (final c in chars.toSet()) {
      futures.add(profile(c, family));
    }
    await Future.wait(futures);
  }

  Future<GlyphProfile> _profile(String char, String family) async {
    final paragraphStyle = ui.ParagraphStyle(
      textDirection: ui.TextDirection.ltr,
      fontFamily: family,
      fontSize: _rasterFontSize,
      textAlign: ui.TextAlign.left,
    );
    final builder = ui.ParagraphBuilder(paragraphStyle)
      ..pushStyle(ui.TextStyle(color: const ui.Color(0xFFFFFFFF), fontFamily: family))
      ..addText(char);
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: 2048));

    final baselineY = paragraph.alphabeticBaseline;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawPaint(ui.Paint()..color = const ui.Color(0x00000000));
    canvas.drawParagraph(paragraph, ui.Offset.zero);
    final picture = recorder.endRecording();
    final image = await picture.toImage(_rasterSize, _rasterSize);
    picture.dispose();
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();

    if (byteData == null) {
      throw StateError('Failed to read glyph raster for "$char"');
    }
    final pixels = byteData.buffer.asUint8List();

    // Pass 1: find ink bounding box.
    int minX = _rasterSize, minY = _rasterSize, maxX = -1, maxY = -1;
    for (int y = 0; y < _rasterSize; y++) {
      final rowOffset = y * _rasterSize * 4;
      for (int x = 0; x < _rasterSize; x++) {
        final a = pixels[rowOffset + x * 4 + 3];
        if (a > _alphaThreshold) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }

    if (maxX < 0) {
      // Empty glyph (e.g. space). Synthesise a tiny zero-ink profile.
      final advanceWidth = paragraph.maxIntrinsicWidth.clamp(1.0, _rasterFontSize);
      paragraph.dispose();
      final empty = List<double>.filled(_sampleRows, 0.0);
      return GlyphProfile(
        char: char,
        fontFamily: family,
        inkBounds: ui.Rect.fromLTWH(0, -baselineY, advanceWidth, 0),
        leftProfile: List<double>.from(empty),
        rightProfile: List<double>.filled(_sampleRows, advanceWidth),
        dominantLeftSlope: 0,
        dominantRightSlope: 0,
        slopeConfidenceLeft: 0,
        slopeConfidenceRight: 0,
        rasterFontSize: _rasterFontSize,
        advanceWidth: advanceWidth,
      );
    }

    // Convert raster coords to baseline-relative.
    final inkBounds = ui.Rect.fromLTRB(
      minX.toDouble(),
      minY - baselineY,
      maxX + 1.0,
      maxY + 1.0 - baselineY,
    );

    // Pass 2: sample left/right profile at evenly spaced rows.
    final left = List<double>.filled(_sampleRows, double.nan);
    final right = List<double>.filled(_sampleRows, double.nan);
    for (int s = 0; s < _sampleRows; s++) {
      // Sample row spans inkBounds top..bottom inclusive.
      final t = _sampleRows == 1 ? 0.5 : s / (_sampleRows - 1);
      final yPx = (minY + t * (maxY - minY)).round().clamp(0, _rasterSize - 1);
      final rowOffset = yPx * _rasterSize * 4;
      int rowMin = -1, rowMax = -1;
      for (int x = minX; x <= maxX; x++) {
        final a = pixels[rowOffset + x * 4 + 3];
        if (a > _alphaThreshold) {
          if (rowMin < 0) rowMin = x;
          rowMax = x;
        }
      }
      if (rowMin >= 0) {
        left[s] = rowMin.toDouble();
        right[s] = rowMax.toDouble();
      }
    }
    // Fill gaps (empty rows mid-glyph, e.g. middle of A) by linear interpolation
    // between nearest valid samples — keeps profiles monotonic-ish for collision.
    _interpolateGaps(left);
    _interpolateGaps(right);

    final advanceWidth = paragraph.maxIntrinsicWidth;
    paragraph.dispose();

    // Sample y in raster pixel space — fit slope in true dx/dy units so it's
    // comparable across glyphs of different ink heights.
    final ys = List<double>.generate(_sampleRows, (s) {
      final t = _sampleRows == 1 ? 0.5 : s / (_sampleRows - 1);
      return minY + t * (maxY - minY);
    });
    final leftFit = _fitMiddleSlope(left, ys);
    final rightFit = _fitMiddleSlope(right, ys);

    // Inflate silhouette outward by kSilhouettePaddingRaster on each side.
    // Collision polygons built from these padded profiles are larger than
    // the visible glyph by `padding` per side, so when two letters' fixtures
    // touch, their visible ink sits `2 * padding * scale` apart.
    const pad = kSilhouettePaddingRaster;
    for (var i = 0; i < left.length; i++) {
      left[i] -= pad;
      right[i] += pad;
    }
    final paddedInk = ui.Rect.fromLTRB(
      inkBounds.left - pad,
      inkBounds.top - pad,
      inkBounds.right + pad,
      inkBounds.bottom + pad,
    );

    return GlyphProfile(
      char: char,
      fontFamily: family,
      inkBounds: paddedInk,
      leftProfile: left,
      rightProfile: right,
      dominantLeftSlope: leftFit.slope,
      dominantRightSlope: rightFit.slope,
      slopeConfidenceLeft: leftFit.r2,
      slopeConfidenceRight: rightFit.r2,
      rasterFontSize: _rasterFontSize,
      advanceWidth: advanceWidth,
    );
  }

  static void _interpolateGaps(List<double> values) {
    final n = values.length;
    int i = 0;
    while (i < n && values[i].isNaN) {
      i++;
    }
    if (i == n) return; // all NaN
    // Fill leading NaNs with first valid.
    for (int j = 0; j < i; j++) {
      values[j] = values[i];
    }
    int last = i;
    for (int k = i + 1; k < n; k++) {
      if (values[k].isNaN) continue;
      if (k - last > 1) {
        final a = values[last];
        final b = values[k];
        for (int g = last + 1; g < k; g++) {
          final t = (g - last) / (k - last);
          values[g] = a + (b - a) * t;
        }
      }
      last = k;
    }
    // Fill trailing NaNs.
    for (int k = last + 1; k < n; k++) {
      values[k] = values[last];
    }
  }

  static _SlopeFit _fitMiddleSlope(List<double> xs, List<double> ys) {
    final n = xs.length;
    final start = (n * 0.2).round();
    final end = (n * 0.8).round();
    final count = end - start;
    if (count < 3) return const _SlopeFit(0, 0);
    double sumY = 0, sumX = 0;
    for (int i = start; i < end; i++) {
      sumY += ys[i];
      sumX += xs[i];
    }
    final meanY = sumY / count;
    final meanX = sumX / count;
    double sxy = 0, syy = 0, sxx = 0;
    for (int i = start; i < end; i++) {
      final dy = ys[i] - meanY;
      final dx = xs[i] - meanX;
      sxy += dy * dx;
      syy += dy * dy;
      sxx += dx * dx;
    }
    if (syy == 0) return const _SlopeFit(0, 0);
    final slope = sxy / syy; // dx per dy in raster pixels
    final r2 = sxx == 0 ? 1.0 : (sxy * sxy) / (syy * sxx);
    return _SlopeFit(slope, r2.clamp(0.0, 1.0).toDouble());
  }
}

class _SlopeFit {
  final double slope;
  final double r2;
  const _SlopeFit(this.slope, this.r2);
}
