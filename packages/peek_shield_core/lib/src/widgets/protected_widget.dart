import 'package:flutter/widgets.dart';
import 'blur_shield.dart';

/// Public-facing wrapper that protects [child] from shoulder-surfers.
///
/// Wraps [child] in a [BlurShield] that automatically blurs the content
/// when peek detection triggers. This is the primary widget for SDK consumers.
///
/// Example:
/// ```dart
/// ProtectedWidget(
///   child: Text('4111 1111 1111 1111'),
/// )
/// ```
///
/// Use [localOverride] to force-blur a specific widget regardless of the
/// global peek state (e.g., for extra-sensitive fields like CVV).
class ProtectedWidget extends StatelessWidget {
  /// The sensitive content to protect.
  final Widget child;

  /// When `true`, this widget is always blurred regardless of peek state.
  /// Use for highest-sensitivity fields (seed phrases, CVV, etc.).
  final bool localOverride;

  const ProtectedWidget({
    super.key,
    required this.child,
    this.localOverride = false,
  });

  @override
  Widget build(BuildContext context) {
    return BlurShield(
      forceBlur: localOverride,
      child: child,
    );
  }
}
