/// PeekShield Core SDK
///
/// Provides front-camera peek detection, face enrollment, and blur widgets
/// for Flutter iOS applications.
///
/// Quick start:
/// ```dart
/// // 1. Wrap your app in ProviderScope
/// // 2. Wrap sensitive widgets:
/// ProtectedWidget(
///   child: Text('4111 1111 1111 1111'),
/// )
/// ```
library peek_shield_core;

export 'src/camera/camera_service.dart';
export 'src/detection/peek_config.dart';
export 'src/detection/peek_detection_service.dart' show PeekState;
export 'src/enrollment/embedding_store.dart';
export 'src/enrollment/face_enrollment_service.dart'
    show FaceEnrollmentService, EnrollmentResult;
export 'src/widgets/blur_shield.dart';
export 'src/widgets/protected_widget.dart';
export 'src/providers.dart';
