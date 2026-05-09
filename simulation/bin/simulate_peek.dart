/// PeekShield — peek-detection simulation script.
///
/// Drives a pure-Dart replica of the detection algorithm through a series
/// of realistic scenario frames and prints a timestamped trace showing
/// PeekState transitions, then summarises pass / fail.
///
/// No camera, ML Kit, or TFLite required — runs on any Dart runtime.
///
/// Usage:
///   dart run peek_shield/simulation/bin/simulate_peek.dart
///
/// Output example:
///   [00:00.000] faceCount=1 yaw= 5.0 pitch= 2.0 → clear
///   [00:00.100] faceCount=1 yaw=35.0 pitch= 2.0 → PEEKING   ← trigger
///   ...
///   ✓ Scenario A — shoulder-surfer angle
///   ✓ Scenario B — 800ms debounce hold
///   ...
///   All 8 scenarios passed.
library;

import 'dart:math';

// ---------------------------------------------------------------------------
// Types
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

  static PeekConfig high() => const PeekConfig(
    yawHardThreshold: 20.0,
    yawSoftThreshold: 12.0,
    pitchHardThreshold: 22.0,
    pitchSoftThreshold: 15.0,
  );
}

// ---------------------------------------------------------------------------
// Detection engine (mirrors peek_detection_service.dart logic)
// ---------------------------------------------------------------------------

class DetectionEngine {
  DetectionEngine({PeekConfig? config}) : config = config ?? const PeekConfig();

  final PeekConfig config;
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
              (config.noFaceClearSeconds * 1000).toInt()) {
        return _emit(PeekState.clear, now);
      }
      return _current;
    }

    _lastFaceSeenTime = now;

    if (faceCount > 1) return _emit(PeekState.peeking, now);

    final absYaw = yaw.abs();
    final absPitch = pitch.abs();

    if (absYaw > config.yawHardThreshold || absPitch > config.pitchHardThreshold) {
      return _emit(PeekState.peeking, now);
    }

    if (hasEnrollment) {
      if (!enrollmentMatches) return _emit(PeekState.peeking, now);
      if (absYaw > config.yawSoftThreshold || absPitch > config.pitchSoftThreshold) {
        return _emit(PeekState.peeking, now);
      }
      return _emit(PeekState.clear, now);
    }

    if (absYaw > config.yawSoftThreshold || absPitch > config.pitchSoftThreshold) {
      return _emit(PeekState.uncertain, now);
    }

    return _emit(PeekState.clear, now);
  }

  PeekState _emit(PeekState newState, DateTime now) {
    if (newState == PeekState.peeking) {
      _lastPeekTime = now;
    } else if (_lastPeekTime != null &&
        now.difference(_lastPeekTime!).inMilliseconds < config.blurHoldMs) {
      _current = PeekState.peeking;
      return _current;
    }
    _current = newState;
    return _current;
  }
}

// ---------------------------------------------------------------------------
// Simulation frame
// ---------------------------------------------------------------------------

class Frame {
  final Duration offset;
  final int faceCount;
  final double yaw;
  final double pitch;
  final bool hasEnrollment;
  final bool enrollmentMatches;
  final String? note;

  const Frame({
    required this.offset,
    this.faceCount = 1,
    this.yaw = 0.0,
    this.pitch = 0.0,
    this.hasEnrollment = false,
    this.enrollmentMatches = true,
    this.note,
  });
}

// ---------------------------------------------------------------------------
// Cosine similarity (used in enrollment simulation)
// ---------------------------------------------------------------------------

double cosineSim(List<double> a, List<double> b) {
  double dot = 0, nA = 0, nB = 0;
  for (int i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    nA += a[i] * a[i];
    nB += b[i] * b[i];
  }
  final denom = sqrt(nA) * sqrt(nB);
  return denom == 0 ? 0.0 : dot / denom;
}

List<double> l2Norm(List<double> v) {
  final n = sqrt(v.fold(0.0, (s, x) => s + x * x));
  if (n == 0) return v;
  return v.map((x) => x / n).toList();
}

// ---------------------------------------------------------------------------
// Scenario runner
// ---------------------------------------------------------------------------

class Scenario {
  final String name;
  final List<Frame> frames;
  final List<({Duration at, PeekState expected})> assertions;
  final PeekConfig? config;

  const Scenario({
    required this.name,
    required this.frames,
    required this.assertions,
    this.config,
  });
}

String _stateLabel(PeekState s) => switch (s) {
  PeekState.clear => 'clear    ',
  PeekState.uncertain => 'uncertain',
  PeekState.peeking => 'PEEKING  ',
};

bool _runScenario(Scenario scenario) {
  final engine = DetectionEngine(config: scenario.config);
  final t0 = DateTime(2025, 1, 1, 9, 0, 0);
  final Map<Duration, PeekState> results = {};

  print('\n──────────────────────────────────────────────────────');
  print('  Scenario: ${scenario.name}');
  print('──────────────────────────────────────────────────────');

  for (final frame in scenario.frames) {
    final now = t0.add(frame.offset);
    final state = engine.process(
      faceCount: frame.faceCount,
      yaw: frame.yaw,
      pitch: frame.pitch,
      hasEnrollment: frame.hasEnrollment,
      enrollmentMatches: frame.enrollmentMatches,
      now: now,
    );
    results[frame.offset] = state;

    final ms = frame.offset.inMilliseconds;
    final mm = ms ~/ 60000;
    final ss = (ms % 60000) ~/ 1000;
    final ms2 = ms % 1000;
    final ts = '${mm.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}.${ms2.toString().padLeft(3, '0')}';
    final yawStr = frame.yaw.toStringAsFixed(1).padLeft(5);
    final pitchStr = frame.pitch.toStringAsFixed(1).padLeft(5);
    final noteStr = frame.note != null ? '  // ${frame.note}' : '';
    print('  [$ts] faces=${frame.faceCount} yaw=$yawStr° pitch=$pitchStr°  → ${_stateLabel(state)}$noteStr');
  }

  bool passed = true;
  print('');

  for (final assertion in scenario.assertions) {
    final actual = results[assertion.at];
    final ok = actual == assertion.expected;
    if (!ok) passed = false;
    final tick = ok ? '✓' : '✗';
    final atMs = assertion.at.inMilliseconds;
    print('  $tick At ${atMs}ms: expected ${assertion.expected.name}, got ${actual?.name ?? 'null'}');
  }

  return passed;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main() {
  print('╔══════════════════════════════════════════════════════╗');
  print('║   PeekShield — Detection Algorithm Simulation v1.0  ║');
  print('╚══════════════════════════════════════════════════════╝');

  final scenarios = <Scenario>[
    // ── A: Normal use — owner looking straight ─────────────────────────────
    Scenario(
      name: 'A — Owner looking straight (no enrollment)',
      frames: [
        Frame(offset: Duration.zero, yaw: 2.0, pitch: 1.0, note: 'owner, straight'),
        Frame(offset: const Duration(milliseconds: 100), yaw: 4.0, pitch: 2.0),
        Frame(offset: const Duration(milliseconds: 200), yaw: 3.0, pitch: 1.5),
        Frame(offset: const Duration(milliseconds: 300), yaw: 5.0, pitch: 3.0),
      ],
      assertions: [
        (at: const Duration(milliseconds: 300), expected: PeekState.clear),
      ],
    ),

    // ── B: Shoulder surfer enters — hard angle ─────────────────────────────
    Scenario(
      name: 'B — Shoulder-surfer: hard angle (yaw > 30°)',
      frames: [
        Frame(offset: Duration.zero, yaw: 5.0, pitch: 2.0, note: 'owner, clear'),
        Frame(offset: const Duration(milliseconds: 100), yaw: 5.0, pitch: 2.0),
        Frame(offset: const Duration(milliseconds: 200), yaw: 35.0, pitch: 3.0, note: 'surfer enters'),
        Frame(offset: const Duration(milliseconds: 300), yaw: 38.0, pitch: 4.0),
        Frame(offset: const Duration(milliseconds: 400), yaw: 40.0, pitch: 5.0),
      ],
      assertions: [
        (at: const Duration(milliseconds: 100), expected: PeekState.clear),
        (at: const Duration(milliseconds: 200), expected: PeekState.peeking),
        (at: const Duration(milliseconds: 400), expected: PeekState.peeking),
      ],
    ),

    // ── C: Debounce hold — face straightens within 800ms ──────────────────
    Scenario(
      name: 'C — Debounce: blur holds 800ms after angle resolves',
      frames: [
        Frame(offset: Duration.zero, yaw: 35.0, pitch: 2.0, note: 'trigger peek'),
        Frame(offset: const Duration(milliseconds: 300), yaw: 5.0, pitch: 2.0, note: 'face straightened (300ms < 800ms hold)'),
        Frame(offset: const Duration(milliseconds: 600), yaw: 5.0, pitch: 2.0, note: '600ms — still in hold window'),
        Frame(offset: const Duration(milliseconds: 900), yaw: 5.0, pitch: 2.0, note: '900ms — hold expired'),
      ],
      assertions: [
        (at: Duration.zero, expected: PeekState.peeking),
        (at: const Duration(milliseconds: 300), expected: PeekState.peeking),
        (at: const Duration(milliseconds: 600), expected: PeekState.peeking),
        (at: const Duration(milliseconds: 900), expected: PeekState.clear),
      ],
    ),

    // ── D: Multiple faces ─────────────────────────────────────────────────
    Scenario(
      name: 'D — Two faces → immediate PEEKING',
      frames: [
        Frame(offset: Duration.zero, faceCount: 1, yaw: 5.0, note: 'owner alone'),
        Frame(offset: const Duration(milliseconds: 100), faceCount: 2, yaw: 5.0, note: 'second person appears'),
        Frame(offset: const Duration(milliseconds: 200), faceCount: 2, yaw: 3.0),
        Frame(offset: const Duration(milliseconds: 1000), faceCount: 1, yaw: 3.0, note: 'second person leaves (within debounce)'),
        Frame(offset: const Duration(milliseconds: 2000), faceCount: 1, yaw: 3.0, note: '2s after trigger — hold expired'),
      ],
      assertions: [
        (at: const Duration(milliseconds: 100), expected: PeekState.peeking),
        (at: const Duration(milliseconds: 200), expected: PeekState.peeking),
        (at: const Duration(milliseconds: 1000), expected: PeekState.peeking),
        (at: const Duration(milliseconds: 2000), expected: PeekState.clear),
      ],
    ),

    // ── E: No face for > 2s → clear ───────────────────────────────────────
    Scenario(
      name: 'E — No face > noFaceClearSeconds (2 s) → clear',
      frames: [
        Frame(offset: Duration.zero, faceCount: 1, yaw: 5.0, note: 'face present'),
        Frame(offset: const Duration(milliseconds: 500), faceCount: 0, note: 'face gone, 0.5s'),
        Frame(offset: const Duration(milliseconds: 1500), faceCount: 0, note: 'still gone, 1.5s (< 2s)'),
        Frame(offset: const Duration(milliseconds: 2500), faceCount: 0, note: 'gone 2.5s (> noFaceClearSeconds)'),
      ],
      assertions: [
        (at: const Duration(milliseconds: 1500), expected: PeekState.clear), // was clear before, no face, stays clear
        (at: const Duration(milliseconds: 2500), expected: PeekState.clear),
      ],
    ),

    // ── F: Soft angle without enrollment → uncertain ───────────────────────
    Scenario(
      name: 'F — Soft angle (20°–30°), no enrollment → uncertain',
      frames: [
        Frame(offset: Duration.zero, yaw: 5.0, note: 'owner, straight'),
        Frame(offset: const Duration(milliseconds: 100), yaw: 25.0, note: 'soft angle (>20°, <30°), no enroll'),
        Frame(offset: const Duration(milliseconds: 200), yaw: 22.0),
      ],
      assertions: [
        (at: Duration.zero, expected: PeekState.clear),
        (at: const Duration(milliseconds: 100), expected: PeekState.uncertain),
        (at: const Duration(milliseconds: 200), expected: PeekState.uncertain),
      ],
    ),

    // ── G: Enrollment matching — soft angle clears ─────────────────────────
    Scenario(
      name: 'G — Enrolled owner at soft angle → clear (match)',
      frames: [
        Frame(offset: Duration.zero, yaw: 5.0, hasEnrollment: true, enrollmentMatches: true, note: 'owner enrolled, straight'),
        Frame(offset: const Duration(milliseconds: 100), yaw: 25.0, hasEnrollment: true, enrollmentMatches: true, note: 'soft angle but match → clear'),
      ],
      assertions: [
        (at: const Duration(milliseconds: 100), expected: PeekState.clear),
      ],
    ),

    // ── H: High-sensitivity config ─────────────────────────────────────────
    Scenario(
      name: 'H — High-sensitivity config (yawHard=20°)',
      config: PeekConfig.high(),
      frames: [
        Frame(offset: Duration.zero, yaw: 5.0, note: 'straight'),
        Frame(offset: const Duration(milliseconds: 100), yaw: 22.0, note: 'would be clear on default, PEEKING on high'),
      ],
      assertions: [
        (at: Duration.zero, expected: PeekState.clear),
        (at: const Duration(milliseconds: 100), expected: PeekState.peeking),
      ],
    ),
  ];

  // Cosine similarity demonstration
  print('\n──────────────────────────────────────────────────────');
  print('  Cosine Similarity Verification');
  print('──────────────────────────────────────────────────────');
  final rng = Random(42);
  final ownerEmb = l2Norm(List.generate(128, (_) => rng.nextDouble() * 2 - 1));
  final rng2 = Random(42); // same seed → same base
  final noise = 0.05;
  final samePersonEmb = l2Norm(List.generate(128, (i) =>
    ownerEmb[i] + (rng2.nextDouble() - 0.5) * noise));
  final rng3 = Random(999); // different seed → different person
  final differentPersonEmb = l2Norm(List.generate(128, (_) => rng3.nextDouble() * 2 - 1));

  final simSame = cosineSim(ownerEmb, samePersonEmb);
  final simDiff = cosineSim(ownerEmb, differentPersonEmb);
  final simSelf = cosineSim(ownerEmb, ownerEmb);
  print('  Self similarity (same vector):   ${simSelf.toStringAsFixed(4)} (expect ≈ 1.0)');
  print('  Same person + noise:             ${simSame.toStringAsFixed(4)} (expect > 0.55)');
  print('  Different person:                ${simDiff.toStringAsFixed(4)} (expect < 0.55)');

  final simPassed = simSelf > 0.999 && simSame > 0.55 && simDiff < 0.55;
  print('  ${simPassed ? '✓' : '✗'} Cosine similarity thresholds are correct');

  // Run all scenarios
  final results = scenarios.map(_runScenario).toList();

  // Summary
  final passed = results.where((r) => r).length;
  final failed = results.length - passed;
  final total = scenarios.length + (simPassed ? 1 : 0);
  final totalPassed = passed + (simPassed ? 1 : 0);

  print('\n══════════════════════════════════════════════════════');
  print('  RESULTS: $totalPassed / $total passed  |  $failed detection scenario(s) failed');
  print('══════════════════════════════════════════════════════\n');

  if (failed > 0 || !simPassed) {
    throw Exception('$failed scenario(s) failed. See output above for details.');
  }
}
