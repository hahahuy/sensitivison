import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:peek_shield_core/src/detection/peek_config.dart';

// ---------------------------------------------------------------------------
// Minimal stub types to test detection logic without real ML dependencies
// ---------------------------------------------------------------------------

enum PeekState { clear, uncertain, peeking }

class FakeDetectionLogic {
  final PeekConfig config;
  DateTime? _lastPeekTime;
  DateTime? _lastFaceSeenTime;
  PeekState _current = PeekState.clear;

  FakeDetectionLogic({this.config = const PeekConfig()});

  PeekState process({
    required int faceCount,
    double yaw = 0.0,
    double pitch = 0.0,
    bool hasEnrollment = false,
    bool enrollmentMatches = true,
    DateTime? now,
  }) {
    final t = now ?? DateTime.now();

    if (faceCount == 0) {
      if (_lastFaceSeenTime != null &&
          t.difference(_lastFaceSeenTime!).inMilliseconds >=
              (config.noFaceClearSeconds * 1000).toInt()) {
        return _emit(PeekState.clear, t);
      }
      return _current;
    }

    _lastFaceSeenTime = t;

    if (faceCount > 1) return _emit(PeekState.peeking, t);

    final absYaw = yaw.abs();
    final absPitch = pitch.abs();

    if (absYaw > config.yawHardThreshold ||
        absPitch > config.pitchHardThreshold) {
      return _emit(PeekState.peeking, t);
    }

    if (hasEnrollment) {
      if (!enrollmentMatches) return _emit(PeekState.peeking, t);
      if (absYaw > config.yawSoftThreshold ||
          absPitch > config.pitchSoftThreshold) {
        return _emit(PeekState.peeking, t);
      }
      return _emit(PeekState.clear, t);
    }

    if (absYaw > config.yawSoftThreshold ||
        absPitch > config.pitchSoftThreshold) {
      return _emit(PeekState.uncertain, t);
    }
    return _emit(PeekState.clear, t);
  }

  PeekState _emit(PeekState newState, DateTime t) {
    if (newState == PeekState.peeking) {
      _lastPeekTime = t;
    } else if (_lastPeekTime != null &&
        t.difference(_lastPeekTime!).inMilliseconds < config.blurHoldMs) {
      // Debounce: stay peeking
      _current = PeekState.peeking;
      return _current;
    }
    _current = newState;
    return _current;
  }
}

void main() {
  group('PeekDetectionService logic', () {
    test('no faces for > noFaceClearSeconds → clear', () {
      final logic = FakeDetectionLogic();
      final t0 = DateTime(2024, 1, 1, 12, 0, 0);
      // First: a face was present
      logic.process(faceCount: 1, now: t0);
      // Now no face, but only 1s elapsed (below 2s threshold)
      final t1 = t0.add(const Duration(seconds: 1));
      final s1 = logic.process(faceCount: 0, now: t1);
      // Still not clear (debounced by noFaceClearSeconds)
      final t2 = t0.add(const Duration(seconds: 3));
      final s2 = logic.process(faceCount: 0, now: t2);
      expect(s2, PeekState.clear);
    });

    test('multiple faces → peeking immediately', () {
      final logic = FakeDetectionLogic();
      final s = logic.process(faceCount: 2);
      expect(s, PeekState.peeking);
    });

    test('yaw > yawHardThreshold → peeking', () {
      final logic = FakeDetectionLogic();
      final s = logic.process(faceCount: 1, yaw: 35.0);
      expect(s, PeekState.peeking);
    });

    test('pitch > pitchHardThreshold → peeking', () {
      final logic = FakeDetectionLogic();
      final s = logic.process(faceCount: 1, pitch: 40.0);
      expect(s, PeekState.peeking);
    });

    test('yaw between soft and hard, no enrollment → uncertain', () {
      final logic = FakeDetectionLogic();
      final s = logic.process(faceCount: 1, yaw: 25.0, hasEnrollment: false);
      expect(s, PeekState.uncertain);
    });

    test('straight gaze, no enrollment → clear', () {
      final logic = FakeDetectionLogic();
      final s = logic.process(faceCount: 1, yaw: 5.0, pitch: 3.0);
      expect(s, PeekState.clear);
    });

    test('enrollment present and matching → clear even at soft angle', () {
      final logic = FakeDetectionLogic();
      final s = logic.process(
        faceCount: 1,
        yaw: 15.0,
        hasEnrollment: true,
        enrollmentMatches: true,
      );
      expect(s, PeekState.clear);
    });

    test('enrollment present but not matching → peeking', () {
      final logic = FakeDetectionLogic();
      final s = logic.process(
        faceCount: 1,
        yaw: 5.0,
        hasEnrollment: true,
        enrollmentMatches: false,
      );
      expect(s, PeekState.peeking);
    });

    test('debounce: clear after peeking holds blur for blurHoldMs', () {
      final logic = FakeDetectionLogic();
      final t0 = DateTime(2024, 1, 1, 12, 0, 0);
      // Trigger peek
      logic.process(faceCount: 1, yaw: 35.0, now: t0);
      // 400ms later (within 800ms hold) — face straightened
      final t1 = t0.add(const Duration(milliseconds: 400));
      final s1 = logic.process(faceCount: 1, yaw: 5.0, now: t1);
      expect(s1, PeekState.peeking); // still held
      // 900ms after trigger — hold expired
      final t2 = t0.add(const Duration(milliseconds: 900));
      final s2 = logic.process(faceCount: 1, yaw: 5.0, now: t2);
      expect(s2, PeekState.clear);
    });
  });
}
