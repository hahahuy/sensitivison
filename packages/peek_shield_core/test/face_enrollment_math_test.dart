/// Unit tests for the maths helpers extracted from [FaceEnrollmentService].
///
/// Tests the L2-normalise, BGRA→RGB conversion, bounding-box clamp,
/// and Float32 normalisation logic — all pure functions testable
/// without the TFLite runtime or ML Kit.
///
/// Run with:
///   flutter test packages/peek_shield_core/test/face_enrollment_math_test.dart
library;

import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Pure-function extracts (mirrors of the private methods in
// FaceEnrollmentService — tested here in isolation so we don't need
// to instantiate the real service which requires TFLite).
// ---------------------------------------------------------------------------

List<double> l2Normalize(List<double> vec) {
  double sumSq = 0.0;
  for (final v in vec) {
    sumSq += v * v;
  }
  final norm = sqrt(sumSq);
  if (norm == 0.0) return List<double>.from(vec);
  return vec.map((v) => v / norm).toList();
}

/// BGRA (4 bytes per pixel) → RGB (3 bytes per pixel).
Uint8List bgraToRgb(Uint8List bgra, int width, int height) {
  final pixelCount = width * height;
  final rgb = Uint8List(pixelCount * 3);
  for (int i = 0; i < pixelCount; i++) {
    final src = i * 4;
    final dst = i * 3;
    rgb[dst] = bgra[src + 2]; // R ← B[2]
    rgb[dst + 1] = bgra[src + 1]; // G ← G[1]
    rgb[dst + 2] = bgra[src]; // B ← B[0]
  }
  return rgb;
}

/// Normalises a pixel byte value (0–255) to [-1, 1] as FaceNet expects.
double normalisePixel(int byte) => (byte / 127.5) - 1.0;

/// Clamps bounding-box coordinates to image bounds.
/// Returns {x, y, w, h} in a record.
({int x, int y, int w, int h}) clampBoundingBox({
  required double left,
  required double top,
  required double bboxW,
  required double bboxH,
  required int imgW,
  required int imgH,
}) {
  final x = left.round().clamp(0, imgW - 1);
  final y = top.round().clamp(0, imgH - 1);
  final w = bboxW.round().clamp(1, imgW - x);
  final h = bboxH.round().clamp(1, imgH - y);
  return (x: x, y: y, w: w, h: h);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── L2 normalisation ───────────────────────────────────────────────────────

  group('l2Normalize', () {
    test('result has unit L2 norm', () {
      final vec = List.generate(128, (i) => (i - 64).toDouble());
      final n = l2Normalize(vec);
      final norm = sqrt(n.fold(0.0, (s, v) => s + v * v));
      expect(norm, closeTo(1.0, 1e-9));
    });

    test('already-normalised vector is unchanged', () {
      final v = [0.6, 0.8]; // |v| = 1
      final n = l2Normalize(v);
      expect(n[0], closeTo(0.6, 1e-9));
      expect(n[1], closeTo(0.8, 1e-9));
    });

    test('zero vector returns zero vector (no NaN / divide-by-zero)', () {
      final v = [0.0, 0.0, 0.0, 0.0];
      final n = l2Normalize(v);
      expect(n.every((x) => x == 0.0), isTrue);
    });

    test('single-element vector normalises to ±1', () {
      expect(l2Normalize([5.0])[0], closeTo(1.0, 1e-9));
      expect(l2Normalize([-3.0])[0], closeTo(-1.0, 1e-9));
    });

    test('128-dim FaceNet output normalises correctly', () {
      final rng = Random(7);
      final raw = List.generate(128, (_) => rng.nextDouble() * 2 - 1);
      final normed = l2Normalize(raw);
      final norm = sqrt(normed.fold(0.0, (s, v) => s + v * v));
      expect(norm, closeTo(1.0, 1e-9));
    });

    test('does not mutate the original list', () {
      final original = [3.0, 4.0];
      l2Normalize(original);
      expect(original[0], 3.0);
      expect(original[1], 4.0);
    });
  });

  // ── BGRA → RGB conversion ──────────────────────────────────────────────────

  group('bgraToRgb', () {
    test('converts a single pixel correctly', () {
      // BGRA = [50, 100, 200, 255] → RGB = [200, 100, 50]
      final bgra = Uint8List.fromList([50, 100, 200, 255]);
      final rgb = bgraToRgb(bgra, 1, 1);
      expect(rgb[0], 200); // R
      expect(rgb[1], 100); // G
      expect(rgb[2], 50); // B
    });

    test('output length is width × height × 3', () {
      final bgra = Uint8List(4 * 4 * 4); // 4×4 image, 4 bytes/px
      final rgb = bgraToRgb(bgra, 4, 4);
      expect(rgb.length, 4 * 4 * 3);
    });

    test('pure red pixel BGRA [0, 0, 255, 255] → RGB [255, 0, 0]', () {
      final bgra = Uint8List.fromList([0, 0, 255, 255]);
      final rgb = bgraToRgb(bgra, 1, 1);
      expect(rgb[0], 255); // R
      expect(rgb[1], 0); // G
      expect(rgb[2], 0); // B
    });

    test('pure blue pixel BGRA [255, 0, 0, 255] → RGB [0, 0, 255]', () {
      final bgra = Uint8List.fromList([255, 0, 0, 255]);
      final rgb = bgraToRgb(bgra, 1, 1);
      expect(rgb[0], 0); // R
      expect(rgb[1], 0); // G
      expect(rgb[2], 255); // B
    });

    test('white pixel round-trips correctly', () {
      final bgra = Uint8List.fromList([255, 255, 255, 255]);
      final rgb = bgraToRgb(bgra, 1, 1);
      expect(rgb, [255, 255, 255]);
    });

    test('black pixel round-trips correctly', () {
      final bgra = Uint8List.fromList([0, 0, 0, 255]);
      final rgb = bgraToRgb(bgra, 1, 1);
      expect(rgb, [0, 0, 0]);
    });

    test('alpha channel is stripped (not present in output)', () {
      // 2×1 image: first pixel has alpha=100, second alpha=200
      final bgra = Uint8List.fromList([
        10, 20, 30, 100, // pixel 0
        40, 50, 60, 200, // pixel 1
      ]);
      final rgb = bgraToRgb(bgra, 2, 1);
      expect(rgb.length, 6); // only 6 bytes, no alpha
    });

    test('multiple pixels are converted independently', () {
      final bgra = Uint8List.fromList([
        10, 20, 30, 255, // B=10, G=20, R=30 → RGB [30, 20, 10]
        100, 150, 200, 255, // B=100, G=150, R=200 → RGB [200, 150, 100]
      ]);
      final rgb = bgraToRgb(bgra, 2, 1);
      expect(rgb[0], 30);
      expect(rgb[1], 20);
      expect(rgb[2], 10);
      expect(rgb[3], 200);
      expect(rgb[4], 150);
      expect(rgb[5], 100);
    });
  });

  // ── Pixel normalisation ────────────────────────────────────────────────────

  group('normalisePixel', () {
    test('0 → -1.0', () => expect(normalisePixel(0), closeTo(-1.0, 1e-9)));
    test('255 → ~+1.0', () => expect(normalisePixel(255), closeTo(1.0, 0.01)));
    test('127 → ~0.0', () => expect(normalisePixel(127), closeTo(-0.00392, 0.001)));
    test('128 → ~0.003', () => expect(normalisePixel(128), closeTo(0.00392, 0.001)));
    test('result always in [-1, 1]', () {
      for (int b = 0; b <= 255; b++) {
        final v = normalisePixel(b);
        expect(v, greaterThanOrEqualTo(-1.0));
        expect(v, lessThanOrEqualTo(1.01)); // slight float headroom
      }
    });
  });

  // ── Bounding box clamp ─────────────────────────────────────────────────────

  group('clampBoundingBox', () {
    test('normal face box is unchanged when within image', () {
      final r = clampBoundingBox(
        left: 50,
        top: 80,
        bboxW: 100,
        bboxH: 120,
        imgW: 640,
        imgH: 480,
      );
      expect(r.x, 50);
      expect(r.y, 80);
      expect(r.w, 100);
      expect(r.h, 120);
    });

    test('negative left is clamped to 0', () {
      final r = clampBoundingBox(
        left: -10,
        top: 0,
        bboxW: 100,
        bboxH: 100,
        imgW: 640,
        imgH: 480,
      );
      expect(r.x, 0);
    });

    test('width extending beyond image right edge is clamped', () {
      final r = clampBoundingBox(
        left: 600,
        top: 0,
        bboxW: 200, // would extend to 800, image is 640
        bboxH: 100,
        imgW: 640,
        imgH: 480,
      );
      expect(r.x + r.w, lessThanOrEqualTo(640));
    });

    test('height extending beyond image bottom is clamped', () {
      final r = clampBoundingBox(
        left: 0,
        top: 400,
        bboxW: 100,
        bboxH: 200, // would extend to 600, image is 480
        imgW: 640,
        imgH: 480,
      );
      expect(r.y + r.h, lessThanOrEqualTo(480));
    });

    test('width/height minimum is 1 (never zero)', () {
      // Degenerate box: left exactly at right edge
      final r = clampBoundingBox(
        left: 639,
        top: 0,
        bboxW: 0,
        bboxH: 0,
        imgW: 640,
        imgH: 480,
      );
      expect(r.w, greaterThanOrEqualTo(1));
      expect(r.h, greaterThanOrEqualTo(1));
    });

    test('top clamped to 0 when negative', () {
      final r = clampBoundingBox(
        left: 0,
        top: -50,
        bboxW: 100,
        bboxH: 200,
        imgW: 640,
        imgH: 480,
      );
      expect(r.y, 0);
    });

    test('full-frame box is clamped to exactly image dimensions', () {
      final r = clampBoundingBox(
        left: 0,
        top: 0,
        bboxW: 640,
        bboxH: 480,
        imgW: 640,
        imgH: 480,
      );
      expect(r.x, 0);
      expect(r.y, 0);
      expect(r.w, 640);
      expect(r.h, 480);
    });
  });
}
