import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Manages the front-facing camera and converts raw [CameraImage] frames into
/// [InputImage] objects suitable for ML Kit face detection.
///
/// Usage:
/// ```dart
/// final service = CameraService();
/// await service.start();
/// service.frameStream.listen((inputImage) { /* run detector */ });
/// // …
/// service.dispose();
/// ```
///
/// Frame throttling is built in: only every 3rd frame is forwarded to
/// [frameStream], keeping CPU load reasonable on mid-range devices.
class CameraService with WidgetsBindingObserver {
  // -------------------------------------------------------------------------
  // Private state
  // -------------------------------------------------------------------------

  CameraController? _controller;
  StreamController<InputImage>? _streamController;

  /// Monotonically increasing frame counter used for throttling.
  int _frameCount = 0;

  /// Whether the camera is currently streaming frames.
  bool _isRunning = false;

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// A broadcast [Stream] of [InputImage] frames captured from the front
  /// camera.
  ///
  /// Subscribe before calling [start]. The stream stays open for the lifetime
  /// of this service; individual errors (e.g. a bad frame) are forwarded as
  /// stream errors rather than fatal exceptions so the subscription is not
  /// cancelled.
  Stream<InputImage> get frameStream {
    _streamController ??= StreamController<InputImage>.broadcast();
    return _streamController!.stream;
  }

  /// Initialises and starts the front camera, then begins streaming frames to
  /// [frameStream].
  ///
  /// Safe to call multiple times: a no-op if the camera is already running.
  /// Throws a [StateError] if no front camera is found on the device.
  Future<void> start() async {
    if (_isRunning) return;

    // Ensure the stream controller exists before we start pushing frames.
    _streamController ??= StreamController<InputImage>.broadcast();

    final List<CameraDescription> cameras = await availableCameras();
    final CameraDescription? frontCamera = cameras.firstWhereOrNull(
      (c) => c.lensDirection == CameraLensDirection.front,
    );

    if (frontCamera == null) {
      throw StateError('No front camera found on this device.');
    }

    _controller = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.bgra8888, // iOS-native format
    );

    try {
      await _controller!.initialize();
    } on CameraException catch (e) {
      _streamController!.addError(e);
      return;
    }

    _isRunning = true;
    WidgetsBinding.instance.addObserver(this);

    await _controller!.startImageStream((CameraImage image) {
      _frameCount++;

      // Process every 3rd frame to balance accuracy and CPU load.
      if (_frameCount % 3 != 0) return;

      try {
        final InputImage inputImage = _convertToInputImage(image);
        _streamController!.sink.add(inputImage);
      } catch (e, stackTrace) {
        // Forward conversion errors as stream errors without killing the stream.
        _streamController!.addError(e, stackTrace);
      }
    });
  }

  /// Stops the image stream without disposing the camera controller or
  /// closing [frameStream].
  ///
  /// Call [start] again to resume streaming.
  void stop() {
    if (!_isRunning) return;
    _controller?.stopImageStream();
    _isRunning = false;
  }

  /// Permanently tears down the camera, closes [frameStream], and removes
  /// this observer from the [WidgetsBinding].
  ///
  /// After calling [dispose] the instance must not be reused.
  void dispose() {
    stop();
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _controller = null;
    _streamController?.close();
    _streamController = null;
  }

  // -------------------------------------------------------------------------
  // WidgetsBindingObserver
  // -------------------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        // Release the camera when the app is backgrounded so iOS can
        // hand it to other apps (e.g. FaceID, other camera users).
        if (_isRunning) {
          stop();
          // Remember that we were running so we can resume.
          _isRunning = false;
        }
      case AppLifecycleState.resumed:
        // Only auto-restart if we were running before backgrounding.
        if (!_isRunning) {
          // Re-start asynchronously; ignore errors here – subscribers will
          // receive them via the stream if anything goes wrong.
          start().catchError((Object e) {
            debugPrint('[CameraService] Failed to restart on resume: $e');
          });
        }
      default:
        break;
    }
  }

  // -------------------------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------------------------

  /// Converts a raw [CameraImage] (BGRA8888) into an [InputImage] for ML Kit.
  ///
  /// Throws if the image has no planes.
  InputImage _convertToInputImage(CameraImage image) {
    assert(image.planes.isNotEmpty, 'CameraImage has no planes');

    final plane = image.planes[0];

    final metadata = InputImageMetadata(
      format: InputImageFormat.bgra8888,
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: InputImageRotation.rotation0deg,
      bytesPerRow: plane.bytesPerRow,
    );

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: metadata,
    );
  }
}

// ---------------------------------------------------------------------------
// Extension helper — replaces the removed `Iterable.firstWhereOrNull`
// for older SDK configs that may not include it.
// ---------------------------------------------------------------------------

extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
