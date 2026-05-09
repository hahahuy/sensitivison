import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Platform channel ─────────────────────────────────────────────────────────

const _eventChannel = EventChannel('com.peekshield/screen/events');
const _methodChannel = MethodChannel('com.peekshield/screen');

// ── One-shot query provider ──────────────────────────────────────────────────

/// Returns whether the screen is currently being captured (screen recording,
/// mirroring, etc.) via a one-shot platform method call.
final isScreenCapturingProvider = FutureProvider<bool>((ref) async {
  final result = await _methodChannel.invokeMethod<bool>('isCapturing');
  return result ?? false;
});

// ── Streaming provider ───────────────────────────────────────────────────────

/// Streams real-time screen-capture state changes via
/// `UIScreen.capturedDidChangeNotification` (iOS).
///
/// Emits `true` when screen recording / mirroring starts, `false` when it ends.
/// The first event is the current state at subscription time.
final screenCaptureProvider = StreamProvider.autoDispose<bool>((ref) {
  return _eventChannel
      .receiveBroadcastStream()
      .map((event) => event as bool? ?? false);
});
