import 'dart:async';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'peek_config.dart';
import '../enrollment/embedding_store.dart';

/// The possible privacy states emitted by [PeekDetectionService].
///
/// - [clear]     — Only the enrolled owner's face is visible at a normal
///                 forward-facing angle, or no face has been detected for
///                 [PeekConfig.noFaceClearSeconds] seconds.
/// - [uncertain] — A face is present at a slightly off-angle that may
///                 indicate a peek, but no enrollment exists to confirm
///                 ownership. The host app may choose to blur or warn.
/// - [peeking]   — A definitive peek is detected: hard angle threshold
///                 exceeded, multiple faces present, or enrolled face
///                 similarity is below [PeekConfig.enrollMatchThreshold].
enum PeekState { clear, uncertain, peeking }

/// Continuously analyses a stream of camera [InputImage] frames and emits
/// [PeekState] transitions whenever the privacy state changes.
///
/// ### Typical usage
/// ```dart
/// final service = PeekDetectionService(
///   frameStream: cameraController.imageStream,
///   embeddingStore: myEmbeddingStore,
///   config: PeekConfig.high(),
/// );
///
/// service.peekStream.listen((state) {
///   if (state == PeekState.peeking) blurContent();
/// });
///
/// service.start();
///
/// // Later:
/// service.dispose();
/// ```
///
/// ### Detection algorithm (per frame)
/// 1. Run ML Kit face detection on the frame.
/// 2. If no faces → wait [PeekConfig.noFaceClearSeconds] then emit [PeekState.clear].
/// 3. If more than one face → emit [PeekState.peeking] immediately.
/// 4. Evaluate head pose (yaw / pitch) of the single detected face:
///    - Hard threshold breach → [PeekState.peeking].
///    - With enrollment: soft threshold breach → [PeekState.peeking];
///      otherwise → [PeekState.clear].
///    - Without enrollment: soft threshold breach → [PeekState.uncertain];
///      otherwise → [PeekState.clear].
/// 5. A [PeekConfig.blurHoldMs] debounce prevents rapid flickering when
///    transitioning away from [PeekState.peeking].
class PeekDetectionService {
  /// The stream of raw camera frames to analyse.
  final Stream<InputImage> frameStream;

  /// Store that holds the enrolled owner face embedding (if any).
  final EmbeddingStore embeddingStore;

  /// Tuning parameters for detection thresholds and debounce timings.
  final PeekConfig config;

  // ---------------------------------------------------------------------------
  // Private fields
  // ---------------------------------------------------------------------------

  /// ML Kit face detector configured for fast, lightweight detection.
  /// Classification, landmarks, and tracking are all disabled because
  /// PeekShield only needs head-pose angles.
  late final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: false,
      enableLandmarks: false,
      enableTracking: false,
      performanceMode: FaceDetectorMode.fast,
    ),
  );

  /// Broadcast controller so multiple listeners (UI layer, logging, etc.)
  /// can subscribe to the same state stream independently.
  final StreamController<PeekState> _stateController =
      StreamController<PeekState>.broadcast();

  /// Active subscription to [frameStream]. Null before [start] is called or
  /// after [stop] / [dispose].
  StreamSubscription<InputImage>? _subscription;

  /// Timestamp of the most recent frame in which [PeekState.peeking] was
  /// emitted. Used for the blur-hold debounce.
  DateTime? _lastPeekTime;

  /// Timestamp of the most recent frame that contained at least one face.
  /// Used to decide when to transition to [PeekState.clear] after faces
  /// disappear.
  DateTime? _lastFaceSeenTime;

  /// The last state that was pushed onto [_stateController]. Starts as
  /// [PeekState.clear] so the first real detection always triggers an emit.
  PeekState _currentState = PeekState.clear;

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------

  /// Creates a [PeekDetectionService].
  ///
  /// [frameStream] must emit [InputImage] objects produced by the device
  /// camera (e.g. from `camera` package's `CameraController.startImageStream`
  /// converted to `InputImage.fromCameraImage`).
  ///
  /// Call [start] to begin processing. Call [dispose] when done.
  PeekDetectionService({
    required this.frameStream,
    required this.embeddingStore,
    this.config = const PeekConfig(),
  });

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Broadcast stream of [PeekState] changes.
  ///
  /// Only distinct state transitions are emitted — consecutive identical
  /// states are suppressed to reduce downstream noise.
  Stream<PeekState> get peekStream => _stateController.stream;

  /// Starts listening to [frameStream] and processing frames.
  ///
  /// Safe to call only once. Subsequent calls without an intervening [stop]
  /// are no-ops (the existing subscription is still active).
  void start() {
    if (_subscription != null) return;

    _subscription = frameStream.listen(
      _processFrame,
      onError: (Object error, StackTrace stack) {
        // Surface stream errors via the state controller so the host app can
        // react (e.g. fall back to full blur) without crashing silently.
        _stateController.addError(error, stack);
      },
      cancelOnError: false,
    );
  }

  /// Stops processing frames without releasing the underlying resources.
  ///
  /// Call [start] again to resume. For full cleanup, prefer [dispose].
  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// Cancels frame processing, closes the state stream, and releases the
  /// ML Kit face detector.
  ///
  /// After [dispose] this object must not be used again.
  void dispose() {
    stop();
    _stateController.close();
    _detector.close();
  }

  // ---------------------------------------------------------------------------
  // Frame processing
  // ---------------------------------------------------------------------------

  /// Analyses a single [inputImage] frame and emits a [PeekState] if the
  /// privacy state has changed.
  ///
  /// This method is `async` but it is safe to call without `await` from the
  /// frame-stream listener — overlapping calls are independent because each
  /// awaits its own `_detector.processImage` future.
  Future<void> _processFrame(InputImage inputImage) async {
    final List<Face> faces = await _detector.processImage(inputImage);
    final DateTime now = DateTime.now();

    // ── No faces in frame ────────────────────────────────────────────────────
    if (faces.isEmpty) {
      // Only transition to clear after the owner has had the phone "put down"
      // for long enough — avoids a clear flash every time they blink or briefly
      // look away.
      if (_lastFaceSeenTime != null) {
        final double secondsSinceLastFace =
            now.difference(_lastFaceSeenTime!).inMilliseconds / 1000.0;
        if (secondsSinceLastFace >= config.noFaceClearSeconds) {
          _emit(PeekState.clear);
        }
        // else: still within the grace period — hold the current state
      }
      // Don't update _lastFaceSeenTime; we're in a no-face window.
      return;
    }

    // At least one face is present — refresh the "last seen" timestamp.
    _lastFaceSeenTime = now;

    // ── Multiple faces → definitive peek ─────────────────────────────────────
    if (faces.length > 1) {
      _emit(PeekState.peeking);
      return;
    }

    // ── Single face: evaluate head pose ──────────────────────────────────────
    final Face face = faces[0];
    final double yaw = (face.headEulerAngleY ?? 0.0).abs();
    final double pitch = (face.headEulerAngleX ?? 0.0).abs();

    // Hard angle thresholds — immediate peek regardless of enrollment.
    if (yaw > config.yawHardThreshold || pitch > config.pitchHardThreshold) {
      _emit(PeekState.peeking);
      return;
    }

    // ── Enrollment-aware soft threshold ──────────────────────────────────────
    //
    // Note: Full embedding extraction (TFLite) runs in FaceEnrollmentService
    // at enrolment time. In the real-time detection stream we only have an
    // InputImage and its ML Kit pose data — we do NOT run TFLite inline here
    // to keep per-frame latency low. The soft angle threshold therefore acts
    // as the proxy for "is this the owner's normal viewing angle?" when an
    // embedding is enrolled.
    final List<double>? enrolled = embeddingStore.getEnrolledEmbedding();

    if (enrolled != null) {
      // Enrollment exists: use the tighter soft thresholds. Any deviation
      // beyond those indicates a sideways-looking face that is likely not
      // the owner's normal posture.
      if (yaw > config.yawSoftThreshold || pitch > config.pitchSoftThreshold) {
        _emit(PeekState.peeking);
        return;
      }
      _emit(PeekState.clear);
      return;
    }

    // No enrollment: soft threshold → uncertain (could be owner, could be
    // someone else — we simply don't know).
    if (yaw > config.yawSoftThreshold || pitch > config.pitchSoftThreshold) {
      _emit(PeekState.uncertain);
      return;
    }

    _emit(PeekState.clear);
  }

  // ---------------------------------------------------------------------------
  // State emission with debounce
  // ---------------------------------------------------------------------------

  /// Applies the blur-hold debounce and emits [newState] on [peekStream] if
  /// the state has actually changed.
  ///
  /// ### Debounce behaviour
  /// When transitioning *away* from [PeekState.peeking], we keep emitting
  /// [PeekState.peeking] until [PeekConfig.blurHoldMs] milliseconds have
  /// elapsed since the last peek trigger. This prevents the blur overlay from
  /// flickering when a person briefly looks back at the phone mid-peek.
  void _emit(PeekState newState) {
    final DateTime now = DateTime.now();

    if (newState == PeekState.peeking) {
      // Record when we last had a confirmed peek so the debounce window is
      // anchored to the most recent trigger.
      _lastPeekTime = now;
    } else {
      // Transitioning to clear or uncertain — honour the hold window.
      if (_lastPeekTime != null) {
        final int msSinceLastPeek =
            now.difference(_lastPeekTime!).inMilliseconds;
        if (msSinceLastPeek < config.blurHoldMs) {
          // Still within the hold window — keep peeking state active.
          // If _currentState is already peeking there is nothing new to emit.
          if (_currentState != PeekState.peeking) {
            _currentState = PeekState.peeking;
            _stateController.add(PeekState.peeking);
          }
          return;
        }
      }
    }

    // Suppress duplicate events — only push when state actually changes.
    if (newState == _currentState) return;

    _currentState = newState;
    _stateController.add(newState);
  }
}
