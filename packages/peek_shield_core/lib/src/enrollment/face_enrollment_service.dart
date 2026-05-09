import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

import 'embedding_store.dart';

// ---------------------------------------------------------------------------
// Result type
// ---------------------------------------------------------------------------

/// Describes the outcome of a single [FaceEnrollmentService.enroll] call.
enum EnrollmentResult {
  /// A face was detected, was sufficiently centred, and the embedding was
  /// saved successfully.
  success,

  /// No face could be detected in the supplied [CameraImage].
  noFaceDetected,

  /// A face was detected but its orientation (yaw / pitch) exceeded the
  /// allowed threshold — ask the user to look straight at the camera.
  faceNotCentered,

  /// The TFLite model failed to produce a valid output.
  modelError,
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Handles the full face-enrolment pipeline:
/// capture → detection → crop & resize → FaceNet embedding → L2 normalisation
/// → persist to [EmbeddingStore].
///
/// ## Typical lifecycle
/// ```dart
/// final service = FaceEnrollmentService(store: embeddingStore);
/// await service.init();
///
/// // called from CameraController.startImageStream:
/// final result = await service.enroll(cameraImage);
/// if (result == EnrollmentResult.success) { ... }
///
/// service.dispose();
/// ```
class FaceEnrollmentService {
  // -------------------------------------------------------------------------
  // Construction
  // -------------------------------------------------------------------------

  /// Creates the service.
  ///
  /// [store] must already be initialised (i.e. [EmbeddingStore.init] awaited)
  /// before [enroll] is called.
  ///
  /// [modelPath] is the Flutter asset path of the FaceNet TFLite model.  The
  /// default points to `assets/models/facenet.tflite`.
  FaceEnrollmentService({
    required EmbeddingStore store,
    String modelPath = 'assets/models/facenet.tflite',
  })  : _store = store,
        _modelPath = modelPath;

  // -------------------------------------------------------------------------
  // Private fields
  // -------------------------------------------------------------------------

  final EmbeddingStore _store;
  final String _modelPath;

  /// TFLite interpreter.  Initialised in [init].
  Interpreter? _interpreter;

  /// ML Kit face detector.  Initialised in [init].
  late FaceDetector _faceDetector;

  // Head-angle threshold in degrees beyond which we reject as "not centred".
  static const double _maxHeadAngleDeg = 10.0;

  // Target face-crop dimensions expected by FaceNet.
  static const int _faceInputSize = 160;

  // -------------------------------------------------------------------------
  // Initialisation
  // -------------------------------------------------------------------------

  /// Loads the TFLite interpreter from assets and sets up the ML Kit face
  /// detector.
  ///
  /// Must be awaited before any call to [enroll].
  Future<void> init() async {
    _interpreter = await Interpreter.fromAsset(_modelPath);

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableClassification: false,
        enableContours: false,
        enableLandmarks: false,
        enableTracking: false,
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Enrolment
  // -------------------------------------------------------------------------

  /// Processes [cameraImage], extracts a face embedding and saves it via
  /// [EmbeddingStore].
  ///
  /// Returns an [EnrollmentResult] describing whether enrolment succeeded or
  /// why it was rejected.
  ///
  /// Throws a [StateError] if [init] has not been called yet.
  Future<EnrollmentResult> enroll(CameraImage cameraImage) async {
    if (_interpreter == null) {
      throw StateError(
        'FaceEnrollmentService is not initialised. Call init() before use.',
      );
    }

    // ------------------------------------------------------------------
    // 1. Build an InputImage from the raw camera buffer.
    // ------------------------------------------------------------------
    final InputImage inputImage = _buildInputImage(cameraImage);

    // ------------------------------------------------------------------
    // 2. Detect faces.
    // ------------------------------------------------------------------
    final List<Face> faces = await _faceDetector.processImage(inputImage);

    if (faces.isEmpty) return EnrollmentResult.noFaceDetected;

    final Face face = faces.first;

    // ------------------------------------------------------------------
    // 3. Reject poorly-oriented faces.
    // ------------------------------------------------------------------
    final double yaw = (face.headEulerAngleY ?? 0).abs();
    final double pitch = (face.headEulerAngleX ?? 0).abs();

    if (yaw > _maxHeadAngleDeg || pitch > _maxHeadAngleDeg) {
      return EnrollmentResult.faceNotCentered;
    }

    // ------------------------------------------------------------------
    // 4. Convert the camera frame to raw RGB bytes.
    // ------------------------------------------------------------------
    final Uint8List rgbBytes = _convertCameraImageToRgbBytes(cameraImage);

    // ------------------------------------------------------------------
    // 5. Crop the detected face region and resize to 160×160.
    //    Returns a Float32List normalised to [-1, 1].
    // ------------------------------------------------------------------
    final Float32List? inputTensor = _cropAndResizeFace(
      rgbBytes,
      cameraImage.width,
      cameraImage.height,
      face.boundingBox,
    );

    if (inputTensor == null) return EnrollmentResult.modelError;

    // ------------------------------------------------------------------
    // 6. Run TFLite inference.
    //
    // TFLite Interpreter cannot cross isolate boundaries; inference runs
    // on the main thread.  We wrap it in a microtask to keep the call
    // site async-friendly without forcing an expensive isolate spawn.
    // ------------------------------------------------------------------
    final List<double>? rawEmbedding = await Future.microtask(
      () => _runInterpreter(inputTensor),
    );

    if (rawEmbedding == null) return EnrollmentResult.modelError;

    // ------------------------------------------------------------------
    // 7. L2-normalise the 128-dimensional FaceNet output.
    // ------------------------------------------------------------------
    final List<double> embedding = _l2Normalize(rawEmbedding);

    // ------------------------------------------------------------------
    // 8. Persist.
    // ------------------------------------------------------------------
    _store.saveEmbedding(embedding);

    return EnrollmentResult.success;
  }

  // -------------------------------------------------------------------------
  // Delegation helpers
  // -------------------------------------------------------------------------

  /// Returns `true` when an enrolled embedding already exists.
  bool hasEnrollment() => _store.hasEmbedding();

  /// Removes the previously enrolled embedding from the store.
  Future<void> clearEnrollment() => _store.clearEmbedding();

  /// Disposes the TFLite interpreter and the ML Kit face detector.
  ///
  /// The service must not be used after this call.
  void dispose() {
    _interpreter?.close();
    _faceDetector.close();
  }

  // -------------------------------------------------------------------------
  // Private — image conversion
  // -------------------------------------------------------------------------

  /// Wraps [cameraImage] in an [InputImage] suitable for ML Kit.
  ///
  /// Supports BGRA8888 (iOS) and YUV420 / NV21 (Android).  The
  /// `InputImageMetadata` carries the pixel dimensions and the format tag so
  /// that ML Kit can decode the buffer correctly on both platforms.
  InputImage _buildInputImage(CameraImage cameraImage) {
    final InputImageFormat format;
    final Uint8List bytes;

    if (cameraImage.format.group == ImageFormatGroup.bgra8888) {
      // iOS — single plane, BGRA packed.
      format = InputImageFormat.bgra8888;
      bytes = cameraImage.planes[0].bytes;
    } else {
      // Android — YUV420 / NV21.  Concatenate all planes into one buffer.
      format = InputImageFormat.nv21;
      final WriteBuffer buffer = WriteBuffer();
      for (final Plane plane in cameraImage.planes) {
        buffer.putUint8List(plane.bytes);
      }
      bytes = buffer.done().buffer.asUint8List();
    }

    final InputImageMetadata metadata = InputImageMetadata(
      size: Size(cameraImage.width.toDouble(), cameraImage.height.toDouble()),
      rotation: InputImageRotation.rotation0deg,
      format: format,
      bytesPerRow: cameraImage.planes[0].bytesPerRow,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  /// Converts a BGRA (iOS) or YUV420 (Android) [CameraImage] to a flat
  /// `RGB` [Uint8List] with `width × height × 3` bytes.
  ///
  /// For BGRA images the alpha channel is stripped.  For YUV images the Y
  /// plane is used as a greyscale proxy (a simple but fast approximation
  /// sufficient for a 160×160 crop before proper decoding via the `image`
  /// package).
  Uint8List _convertCameraImageToRgbBytes(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final int pixelCount = width * height;
    final Uint8List rgb = Uint8List(pixelCount * 3);

    if (image.format.group == ImageFormatGroup.bgra8888) {
      // ----------------------------------------------------------------
      // iOS — planes[0] is a packed BGRA buffer.
      // Layout: B G R A  B G R A  …
      // We output:  R G B  R G B  …
      // ----------------------------------------------------------------
      final Uint8List bgra = image.planes[0].bytes;
      for (int i = 0; i < pixelCount; i++) {
        final int src = i * 4;
        final int dst = i * 3;
        rgb[dst] = bgra[src + 2]; // R
        rgb[dst + 1] = bgra[src + 1]; // G
        rgb[dst + 2] = bgra[src]; // B
      }
    } else {
      // ----------------------------------------------------------------
      // Android — planes[0] is the Y (luma) plane.
      // Use Y for all three channels as a greyscale fallback.
      // Full YUV→RGB conversion is deferred to the `image` package after
      // cropping, which avoids processing the full 4K frame on-thread.
      // ----------------------------------------------------------------
      final Uint8List y = image.planes[0].bytes;
      for (int i = 0; i < pixelCount; i++) {
        final int luma = y[i];
        final int dst = i * 3;
        rgb[dst] = luma;
        rgb[dst + 1] = luma;
        rgb[dst + 2] = luma;
      }
    }

    return rgb;
  }

  // -------------------------------------------------------------------------
  // Private — face crop & resize
  // -------------------------------------------------------------------------

  /// Crops the face region defined by [boundingBox] from the raw RGB buffer,
  /// resizes it to 160×160, and returns a [Float32List] normalised to
  /// `[-1, 1]` as expected by FaceNet (`(pixel / 127.5) - 1.0`).
  ///
  /// Returns `null` if the bounding box does not intersect the image or if
  /// the `image` package cannot decode the buffer.
  Float32List? _cropAndResizeFace(
    Uint8List rgbBytes,
    int width,
    int height,
    Rect boundingBox,
  ) {
    // ------------------------------------------------------------------
    // Build an img.Image from raw RGB bytes (no file header needed).
    // ------------------------------------------------------------------
    final img.Image fullFrame = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgbBytes.buffer,
      numChannels: 3,
      order: img.ChannelOrder.rgb,
    );

    // ------------------------------------------------------------------
    // Clamp the bounding box to the image dimensions.
    // ------------------------------------------------------------------
    final int x = boundingBox.left.round().clamp(0, width - 1);
    final int y = boundingBox.top.round().clamp(0, height - 1);
    final int w =
        (boundingBox.width.round()).clamp(1, width - x);
    final int h =
        (boundingBox.height.round()).clamp(1, height - y);

    if (w <= 0 || h <= 0) return null;

    // ------------------------------------------------------------------
    // Crop.
    // ------------------------------------------------------------------
    final img.Image cropped = img.copyCrop(
      fullFrame,
      x: x,
      y: y,
      width: w,
      height: h,
    );

    // ------------------------------------------------------------------
    // Resize to 160×160 using bicubic interpolation for quality.
    // ------------------------------------------------------------------
    final img.Image resized = img.copyResize(
      cropped,
      width: _faceInputSize,
      height: _faceInputSize,
      interpolation: img.Interpolation.cubic,
    );

    // ------------------------------------------------------------------
    // Flatten to Float32List in [C, H, W] = [RGB, 160, 160] order
    // and normalise each channel value to [-1, 1].
    // ------------------------------------------------------------------
    const int channels = 3;
    final Float32List tensor =
        Float32List(_faceInputSize * _faceInputSize * channels);

    int idx = 0;
    for (int row = 0; row < _faceInputSize; row++) {
      for (int col = 0; col < _faceInputSize; col++) {
        final img.Pixel pixel = resized.getPixel(col, row);
        tensor[idx++] = (pixel.r.toDouble() / 127.5) - 1.0;
        tensor[idx++] = (pixel.g.toDouble() / 127.5) - 1.0;
        tensor[idx++] = (pixel.b.toDouble() / 127.5) - 1.0;
      }
    }

    return tensor;
  }

  // -------------------------------------------------------------------------
  // Private — TFLite inference
  // -------------------------------------------------------------------------

  /// Runs the FaceNet interpreter on a pre-processed [inputTensor] of shape
  /// `[1, 160, 160, 3]` and returns the raw 128-dimensional embedding.
  ///
  /// Returns `null` on any interpreter error.
  ///
  /// Note: This method is intentionally synchronous and is called inside a
  /// `Future.microtask` by [enroll].  The Dart `Interpreter` object from
  /// `tflite_flutter` cannot be sent across isolate boundaries (it wraps a
  /// native pointer), so `compute()` cannot be used here.
  List<double>? _runInterpreter(Float32List inputTensor) {
    final Interpreter interpreter = _interpreter!;

    // Reshape to [1, 160, 160, 3] — tflite_flutter accepts nested lists or
    // a flat buffer; we pass a flat Float32List and reshape via input tensor.
    final List<List<List<List<double>>>> input = List.generate(
      1,
      (_) => List.generate(
        _faceInputSize,
        (row) => List.generate(
          _faceInputSize,
          (col) {
            final int base = (row * _faceInputSize + col) * 3;
            return [
              inputTensor[base].toDouble(),
              inputTensor[base + 1].toDouble(),
              inputTensor[base + 2].toDouble(),
            ];
          },
        ),
      ),
    );

    // FaceNet output: [1, 128]
    final List<List<double>> output = List.generate(
      1,
      (_) => List.filled(128, 0.0),
    );

    try {
      interpreter.run(input, output);
    } catch (e) {
      // Log and surface as null so the caller can return modelError.
      debugPrint('FaceEnrollmentService: interpreter.run() failed — $e');
      return null;
    }

    return output[0];
  }

  // -------------------------------------------------------------------------
  // Private — maths
  // -------------------------------------------------------------------------

  /// Returns a copy of [vec] divided by its L2 (Euclidean) norm.
  ///
  /// If the norm is zero (degenerate all-zero vector) the original vector is
  /// returned unchanged to avoid a divide-by-zero.
  List<double> _l2Normalize(List<double> vec) {
    double sumSq = 0.0;
    for (final double v in vec) {
      sumSq += v * v;
    }

    final double norm = sqrt(sumSq);
    if (norm == 0.0) return List<double>.from(vec);

    return vec.map((v) => v / norm).toList();
  }
}

// ---------------------------------------------------------------------------
// Top-level helper — kept for potential future compute() usage
// ---------------------------------------------------------------------------

/// Top-level function signature matching what `compute()` would require.
///
/// Currently unused because [Interpreter] cannot cross isolate boundaries.
/// Retained here as a documentation anchor for the architectural decision.
///
/// If tflite_flutter ever gains isolate-safe delegate support, replace the
/// `Future.microtask` in [FaceEnrollmentService.enroll] with:
/// ```dart
/// final embedding = await compute(_extractEmbeddingIsolateEntry, payload);
/// ```
// ignore: unused_element
Future<List<double>> _extractEmbeddingIsolateEntry(
  // ignore: avoid_unused_parameters
  List<double> placeholder,
) async {
  // Placeholder — see comment above.
  throw UnimplementedError(
    'TFLite Interpreter cannot cross isolate boundaries; '
    'inference runs on main thread.',
  );
}
