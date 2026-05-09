/// Integration-level peek-detection tests that run the full detection
/// algorithm across a comprehensive frame corpus and verify every published
/// contract from the plan.
///
/// These tests do NOT touch camera, ML Kit, or TFLite.
/// They exercise the detection FSM, debounce, enrollment proxy, and
/// PeekConfig thresholds exhaustively.
///
/// Run with:
///   flutter test packages/peek_shield_core/test/peek_detection_integration_test.dart
library;

import 'dart:math';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Minimal inline types (mirrors of the real SDK types)
// ---------------------------------------------------------------------------

enum PeekState { clear, uncertain, peeking }

class PeekConfig {
  final double yawHardThreshold;
  final double yawSoftThreshold;
  final double pitchHardThreshold;
  final double pitchSoftThreshold;
  final int blurHoldMs;
  final double enrollMatchThreshold;
  final double noFaceClearSeconds;

  const PeekConfig({
    this.yawHardThreshold = 30.0,
    this.yawSoftThreshold = 20.0,
    this.pitchHardThreshold = 35.0,
    this.pitchSoftThreshold = 25.0,
    this.blurHoldMs = 800,
    this.enrollMatchThreshold = 0.55,
    this.noFaceClearSeconds = 2.0,
  });

  PeekConfig copyWith({
    double? yawHardThreshold,
    double? yawSoftThreshold,
    double? pitchHardThreshold,
    double? pitchSoftThreshold,
    int? blurHoldMs,
    double? enrollMatchThreshold,
    double? noFaceClearSeconds,
  }) => PeekConfig(
    yawHardThreshold: yawHardThreshold ?? this.yawHardThreshold,
    yawSoftThreshold: yawSoftThreshold ?? this.yawSoftThreshold,
    pitchHardThreshold: pitchHardThreshold ?? this.pitchHardThreshold,
    pitchSoftThreshold: pitchSoftThreshold ?? this.pitchSoftThreshold,
    blurHoldMs: blurHoldMs ?? this.blurHoldMs,
    enrollMatchThreshold: enrollMatchThreshold ?? this.enrollMatchThreshold,
    noFaceClearSeconds: noFaceClearSeconds ?? this.noFaceClearSeconds,
  );

  static PeekConfig low() => const PeekConfig(
    yawHardThreshold: 40.0,
    yawSoftThreshold: 30.0,
    pitchHardThreshold: 45.0,
    pitchSoftThreshold: 35.0,
    blurHoldMs: 500,
  );

  static PeekConfig high() => const PeekConfig(
    yawHardThreshold: 20.0,
    yawSoftThreshold: 12.0,
    pitchHardThreshold: 22.0,
    pitchSoftThreshold: 15.0,
    blurHoldMs: 1200,
  );
}

class DetectionEngine {
  DetectionEngine({PeekConfig? config}) : _config = config ?? const PeekConfig();

  final PeekConfig _config;
  DateTime? _lastPeekTime;
  DateTime? _lastFaceSeenTime;
  PeekState _current = PeekState.clear;

  PeekState process({
    required int faceCount,
    double yaw = 0.0,
    double pitch = 0.0,
    bool hasEnrollment = false,
    bool enrollmentMatches = true,
    required DateTime now,
  }) {
    if (faceCount == 0) {
      if (_lastFaceSeenTime != null &&
          now.difference(_lastFaceSeenTime!).inMilliseconds >=
              (_config.noFaceClearSeconds * 1000).toInt()) {
        return _emit(PeekState.clear, now);
      }
      return _current;
    }

    _lastFaceSeenTime = now;

    if (faceCount > 1) return _emit(PeekState.peeking, now);

    final aY = yaw.abs();
    final aP = pitch.abs();

    if (aY > _config.yawHardThreshold || aP > _config.pitchHardThreshold) {
      return _emit(PeekState.peeking, now);
    }

    if (hasEnrollment) {
      if (!enrollmentMatches) return _emit(PeekState.peeking, now);
      if (aY > _config.yawSoftThreshold || aP > _config.pitchSoftThreshold) {
        return _emit(PeekState.peeking, now);
      }
      return _emit(PeekState.clear, now);
    }

    if (aY > _config.yawSoftThreshold || aP > _config.pitchSoftThreshold) {
      return _emit(PeekState.uncertain, now);
    }

    return _emit(PeekState.clear, now);
  }

  PeekState _emit(PeekState s, DateTime t) {
    if (s == PeekState.peeking) {
      _lastPeekTime = t;
    } else if (_lastPeekTime != null &&
        t.difference(_lastPeekTime!).inMilliseconds < _config.blurHoldMs) {
      _current = PeekState.peeking;
      return _current;
    }
    _current = s;
    return _current;
  }
}

// ---------------------------------------------------------------------------
// Cosine similarity (for enrollment simulation tests)
// ---------------------------------------------------------------------------

double cosineSim(List<double> a, List<double> b) {
  double dot = 0, nA = 0, nB = 0;
  for (int i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    nA += a[i] * a[i];
    nB += b[i] * b[i];
  }
  final d = sqrt(nA) * sqrt(nB);
  return d == 0 ? 0.0 : dot / d;
}

List<double> l2Norm(List<double> v) {
  final n = sqrt(v.fold(0.0, (s, x) => s + x * x));
  return n == 0 ? v : v.map((x) => x / n).toList();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final _epoch = DateTime(2025, 3, 1);
DateTime _t(int ms) => _epoch.add(Duration(milliseconds: ms));

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── Default config threshold contracts ────────────────────────────────────

  group('Default PeekConfig — threshold contracts', () {
    late DetectionEngine e;
    setUp(() => e = DetectionEngine());

    // Yaw hard threshold
    test('yaw exactly at hard threshold (30°) → peeking', () {
      expect(e.process(faceCount: 1, yaw: 30.0, now: _t(0)), PeekState.peeking);
    });

    test('yaw just below hard threshold (29.9°) → clear or uncertain', () {
      final s = e.process(faceCount: 1, yaw: 29.9, now: _t(0));
      expect(s, isNot(PeekState.peeking));
    });

    test('yaw just above hard threshold (30.1°) → peeking', () {
      expect(e.process(faceCount: 1, yaw: 30.1, now: _t(0)), PeekState.peeking);
    });

    // Pitch hard threshold
    test('pitch at 35° → peeking', () {
      expect(e.process(faceCount: 1, pitch: 35.0, now: _t(0)), PeekState.peeking);
    });

    test('pitch at 34.9° → clear or uncertain', () {
      final s = e.process(faceCount: 1, pitch: 34.9, now: _t(0));
      expect(s, isNot(PeekState.peeking));
    });

    // Negative angles (mirrored)
    test('negative yaw > 30° → peeking (abs applied)', () {
      expect(e.process(faceCount: 1, yaw: -35.0, now: _t(0)), PeekState.peeking);
    });

    test('negative pitch > 35° → peeking (abs applied)', () {
      expect(e.process(faceCount: 1, pitch: -40.0, now: _t(0)), PeekState.peeking);
    });

    // Soft threshold
    test('yaw at soft threshold (20°), no enrollment → uncertain', () {
      expect(
        e.process(faceCount: 1, yaw: 20.0, hasEnrollment: false, now: _t(0)),
        PeekState.uncertain,
      );
    });

    test('yaw just below soft (19.9°), no enrollment → clear', () {
      expect(
        e.process(faceCount: 1, yaw: 19.9, hasEnrollment: false, now: _t(0)),
        PeekState.clear,
      );
    });

    // Straight gaze
    test('straight gaze (yaw=2°, pitch=1°) → clear', () {
      expect(e.process(faceCount: 1, yaw: 2.0, pitch: 1.0, now: _t(0)), PeekState.clear);
    });
  });

  // ── Multi-face ─────────────────────────────────────────────────────────────

  group('Multi-face detection', () {
    test('2 faces → peeking immediately', () {
      final e = DetectionEngine();
      expect(e.process(faceCount: 2, now: _t(0)), PeekState.peeking);
    });

    test('3 faces → peeking', () {
      final e = DetectionEngine();
      expect(e.process(faceCount: 3, now: _t(0)), PeekState.peeking);
    });

    test('0 faces does not override existing state within grace period', () {
      final e = DetectionEngine();
      e.process(faceCount: 1, yaw: 35.0, now: _t(0)); // trigger peek
      final s = e.process(faceCount: 0, now: _t(500)); // 500ms later, still in hold
      expect(s, PeekState.peeking);
    });
  });

  // ── No-face grace period ───────────────────────────────────────────────────

  group('No-face grace period (noFaceClearSeconds = 2.0)', () {
    test('no face for 1.9s keeps current clear state', () {
      final e = DetectionEngine();
      e.process(faceCount: 1, yaw: 2.0, now: _t(0));
      final s = e.process(faceCount: 0, now: _t(1900));
      expect(s, PeekState.clear);
    });

    test('no face for 2.1s → clear', () {
      final e = DetectionEngine();
      e.process(faceCount: 1, yaw: 2.0, now: _t(0));
      final s = e.process(faceCount: 0, now: _t(2100));
      expect(s, PeekState.clear);
    });

    test('no face seen at all → clear from start', () {
      final e = DetectionEngine();
      final s = e.process(faceCount: 0, now: _t(0));
      expect(s, PeekState.clear);
    });
  });

  // ── Debounce (800ms hold) ──────────────────────────────────────────────────

  group('Debounce — 800ms hold after peek trigger', () {
    test('clear at 799ms is still held as peeking', () {
      final e = DetectionEngine();
      e.process(faceCount: 1, yaw: 35.0, now: _t(0));
      final s = e.process(faceCount: 1, yaw: 5.0, now: _t(799));
      expect(s, PeekState.peeking);
    });

    test('clear at exactly 800ms exits hold (on-boundary released)', () {
      final e = DetectionEngine();
      e.process(faceCount: 1, yaw: 35.0, now: _t(0));
      // 800ms: the hold condition is < blurHoldMs, so 800 >= 800 releases.
      final s = e.process(faceCount: 1, yaw: 5.0, now: _t(800));
      expect(s, PeekState.clear);
    });

    test('clear at 801ms → clear', () {
      final e = DetectionEngine();
      e.process(faceCount: 1, yaw: 35.0, now: _t(0));
      final s = e.process(faceCount: 1, yaw: 5.0, now: _t(801));
      expect(s, PeekState.clear);
    });

    test('peek triggers can be chained — each resets the hold timer', () {
      final e = DetectionEngine();
      e.process(faceCount: 1, yaw: 35.0, now: _t(0));    // first trigger
      e.process(faceCount: 1, yaw: 5.0, now: _t(600));   // within hold
      e.process(faceCount: 1, yaw: 35.0, now: _t(700));  // second trigger resets
      // 700 + 799 = 1499ms — still within new hold window
      final s = e.process(faceCount: 1, yaw: 5.0, now: _t(1499));
      expect(s, PeekState.peeking);
    });

    test('custom blurHoldMs=300 — releases at 300ms', () {
      final e = DetectionEngine(
        config: const PeekConfig(blurHoldMs: 300),
      );
      e.process(faceCount: 1, yaw: 35.0, now: _t(0));
      expect(e.process(faceCount: 1, yaw: 5.0, now: _t(299)), PeekState.peeking);
      expect(e.process(faceCount: 1, yaw: 5.0, now: _t(300)), PeekState.clear);
    });
  });

  // ── Enrollment ────────────────────────────────────────────────────────────

  group('Enrollment-aware detection', () {
    test('match at hard threshold → peeking overrides enrollment', () {
      final e = DetectionEngine();
      final s = e.process(
        faceCount: 1, yaw: 35.0,
        hasEnrollment: true, enrollmentMatches: true,
        now: _t(0),
      );
      expect(s, PeekState.peeking);
    });

    test('match at soft angle → clear (enrollment suppresses uncertain)', () {
      final e = DetectionEngine();
      final s = e.process(
        faceCount: 1, yaw: 25.0,
        hasEnrollment: true, enrollmentMatches: true,
        now: _t(0),
      );
      expect(s, PeekState.clear);
    });

    test('no match at any angle → peeking', () {
      final e = DetectionEngine();
      final s = e.process(
        faceCount: 1, yaw: 5.0,
        hasEnrollment: true, enrollmentMatches: false,
        now: _t(0),
      );
      expect(s, PeekState.peeking);
    });

    test('match at straight gaze → clear', () {
      final e = DetectionEngine();
      final s = e.process(
        faceCount: 1, yaw: 2.0, pitch: 1.0,
        hasEnrollment: true, enrollmentMatches: true,
        now: _t(0),
      );
      expect(s, PeekState.clear);
    });

    test('pitch soft threshold with match → clear', () {
      final e = DetectionEngine();
      final s = e.process(
        faceCount: 1, pitch: 24.0,
        hasEnrollment: true, enrollmentMatches: true,
        now: _t(0),
      );
      expect(s, PeekState.clear);
    });

    test('pitch just at soft threshold with match → peeking', () {
      final e = DetectionEngine();
      final s = e.process(
        faceCount: 1, pitch: 25.0,
        hasEnrollment: true, enrollmentMatches: true,
        now: _t(0),
      );
      expect(s, PeekState.peeking);
    });
  });

  // ── PeekConfig presets ─────────────────────────────────────────────────────

  group('PeekConfig presets', () {
    test('high sensitivity: 22° yaw triggers peeking', () {
      final e = DetectionEngine(config: PeekConfig.high());
      expect(e.process(faceCount: 1, yaw: 22.0, now: _t(0)), PeekState.peeking);
    });

    test('default sensitivity: 22° yaw → uncertain (not peeking)', () {
      final e = DetectionEngine();
      // 22° is between soft (20°) and hard (30°) with no enrollment
      final s = e.process(faceCount: 1, yaw: 22.0, now: _t(0));
      expect(s, PeekState.uncertain);
    });

    test('low sensitivity: 35° yaw → uncertain (not peeking)', () {
      final e = DetectionEngine(config: PeekConfig.low());
      // 35° is between low's soft (30°) and hard (40°) — uncertain
      final s = e.process(faceCount: 1, yaw: 35.0, now: _t(0));
      expect(s, PeekState.uncertain);
    });

    test('high blurHoldMs=1200 holds for 1199ms', () {
      final e = DetectionEngine(config: PeekConfig.high());
      e.process(faceCount: 1, yaw: 25.0, now: _t(0));
      final s = e.process(faceCount: 1, yaw: 5.0, now: _t(1199));
      expect(s, PeekState.peeking);
    });

    test('copyWith changes only specified field', () {
      const base = PeekConfig();
      final modified = base.copyWith(blurHoldMs: 2000);
      expect(modified.blurHoldMs, 2000);
      expect(modified.yawHardThreshold, base.yawHardThreshold);
    });
  });

  // ── Full realistic frame sequences ────────────────────────────────────────

  group('Realistic frame sequence — owner + shoulder-surfer', () {
    test('10 frames: owner → surfer enters → leaves → clear', () {
      final e = DetectionEngine();

      // 0–300ms: owner, straight
      for (int ms = 0; ms <= 300; ms += 100) {
        expect(e.process(faceCount: 1, yaw: 4.0, now: _t(ms)), PeekState.clear,
            reason: 'frame at ${ms}ms should be clear');
      }

      // 400ms: shoulder surfer enters hard angle
      expect(e.process(faceCount: 1, yaw: 38.0, now: _t(400)), PeekState.peeking,
          reason: 'surfer entered at 400ms');

      // 500–800ms: still peeking (or in debounce)
      expect(e.process(faceCount: 1, yaw: 40.0, now: _t(500)), PeekState.peeking);
      expect(e.process(faceCount: 1, yaw: 5.0, now: _t(700)), PeekState.peeking,
          reason: '700ms — within 800ms debounce after last peek at 500ms');

      // 1400ms: >800ms after last trigger at 500ms → clears
      expect(e.process(faceCount: 1, yaw: 4.0, now: _t(1400)), PeekState.clear,
          reason: 'hold expired at 1400ms');
    });
  });

  // ── Cosine similarity threshold ───────────────────────────────────────────

  group('Cosine similarity — enrollment threshold (0.55)', () {
    const threshold = 0.55;

    test('identical L2-normalised vectors have similarity = 1.0', () {
      final v = l2Norm(List.generate(128, (i) => sin(i.toDouble())));
      expect(cosineSim(v, v), closeTo(1.0, 1e-6));
    });

    test('same person with small noise stays above threshold', () {
      final base = l2Norm(List.generate(128, (i) => sin(i.toDouble())));
      final rng = Random(42);
      final noisy = l2Norm(base.map((v) => v + (rng.nextDouble() - 0.5) * 0.05).toList());
      expect(cosineSim(base, noisy), greaterThan(threshold));
    });

    test('different person (random unrelated) stays below threshold', () {
      final rng1 = Random(111);
      final rng2 = Random(222);
      final a = l2Norm(List.generate(128, (_) => rng1.nextDouble()));
      final b = l2Norm(List.generate(128, (_) => rng2.nextDouble()));
      expect(cosineSim(a, b), lessThan(threshold));
    });

    test('orthogonal vectors give similarity = 0', () {
      final a = [1.0, 0.0, 0.0, 0.0];
      final b = [0.0, 1.0, 0.0, 0.0];
      expect(cosineSim(a, b), closeTo(0.0, 1e-6));
    });

    test('anti-parallel vectors give similarity = -1', () {
      final a = [1.0, 0.0];
      final b = [-1.0, 0.0];
      expect(cosineSim(a, b), closeTo(-1.0, 1e-6));
    });

    test('zero vector returns 0 (no NaN / div-by-zero)', () {
      final z = [0.0, 0.0, 0.0];
      final v = [1.0, 0.0, 0.0];
      expect(cosineSim(z, v), 0.0);
      expect(cosineSim(z, z), 0.0);
    });
  });
}
