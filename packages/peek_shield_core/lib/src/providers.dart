import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'camera/camera_service.dart';
import 'detection/peek_config.dart';
import 'detection/peek_detection_service.dart';
import 'enrollment/embedding_store.dart';
import 'enrollment/face_enrollment_service.dart';

// ── Core service providers ────────────────────────────────────────────────────

/// Provides the [EmbeddingStore] singleton. Must be initialized before use.
final embeddingStoreProvider = Provider<EmbeddingStore>((ref) {
  final store = EmbeddingStore();
  ref.onDispose(store.dispose);
  return store;
});

/// Provides the [FaceEnrollmentService] singleton.
final enrollmentProvider = Provider<FaceEnrollmentService>((ref) {
  final store = ref.watch(embeddingStoreProvider);
  final service = FaceEnrollmentService(store: store);
  ref.onDispose(service.dispose);
  return service;
});

/// Provides the [CameraService] singleton. Starts/stops with the provider.
final cameraServiceProvider = Provider<CameraService>((ref) {
  final service = CameraService();
  ref.onDispose(service.dispose);
  return service;
});

/// Current [PeekConfig]. Override via [peekConfigOverrideProvider] in the app.
final peekConfigProvider = Provider<PeekConfig>((ref) {
  return const PeekConfig();
});

/// Streams [PeekState] from the [PeekDetectionService].
///
/// Auto-disposes and stops the camera stream when no listeners remain.
final peekStateProvider = StreamProvider.autoDispose<PeekState>((ref) {
  final camera = ref.watch(cameraServiceProvider);
  final store = ref.watch(embeddingStoreProvider);
  final config = ref.watch(peekConfigProvider);

  final detector = PeekDetectionService(
    frameStream: camera.frameStream,
    embeddingStore: store,
    config: config,
  );

  camera.start();
  detector.start();

  ref.onDispose(() {
    detector.dispose();
  });

  return detector.peekStream;
});

// ── Screen capture override ───────────────────────────────────────────────────

const _eventChannel = EventChannel('com.peekshield/screen/events');

/// Streams screen-capture state from the native iOS layer.
/// Returns `false` on non-iOS platforms or when the channel is unavailable.
final screenCaptureOverrideProvider = StreamProvider.autoDispose<bool>((ref) {
  try {
    return _eventChannel
        .receiveBroadcastStream()
        .map((event) => event as bool? ?? false);
  } catch (_) {
    return Stream.value(false);
  }
}).select((async) => async.maybeWhen(data: (v) => v, orElse: () => false));
