import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../detection/peek_detection_service.dart';
import '../providers.dart';

/// Blur overlay widget that reacts to [peekStateProvider].
///
/// Stacks the child under an [AnimatedOpacity] + [BackdropFilter] that
/// activates when [PeekState.peeking] is detected. Also responds to
/// screen-capture events from [screenCaptureProvider] when available.
///
/// Transition: 200ms ease-in-out opacity animation.
/// Blur: [ImageFilter.blur(sigmaX: 25, sigmaY: 25)] + semi-opaque overlay.
/// Shows a lock icon and "PeekShield active" label when blurred.
class BlurShield extends ConsumerStatefulWidget {
  /// The content to protect.
  final Widget child;

  /// When `true`, forces the blur regardless of the detected peek state.
  final bool forceBlur;

  const BlurShield({
    super.key,
    required this.child,
    this.forceBlur = false,
  });

  @override
  ConsumerState<BlurShield> createState() => _BlurShieldState();
}

class _BlurShieldState extends ConsumerState<BlurShield>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _blurOpacity;

  // Red border pulse animation
  late final Animation<Color?> _borderColor;

  bool _isBlurred = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _blurOpacity = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );

    _borderColor = ColorTween(
      begin: Colors.transparent,
      end: const Color(0xFFFF453A),
    ).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateBlurState(bool shouldBlur) {
    if (shouldBlur == _isBlurred) return;
    _isBlurred = shouldBlur;
    if (shouldBlur) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.forceBlur) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateBlurState(true));
    } else {
      final peekAsync = ref.watch(peekStateProvider);
      final isCapturing = ref.watch(screenCaptureOverrideProvider);

      final shouldBlur = widget.forceBlur ||
          isCapturing ||
          peekAsync.maybeWhen(
            data: (state) => state == PeekState.peeking,
            orElse: () => false,
          );

      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _updateBlurState(shouldBlur),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final blurValue = _blurOpacity.value * 25.0;

        return Stack(
          children: [
            widget.child,

            // Blur + frosted overlay
            if (_controller.value > 0)
              Positioned.fill(
                child: AnimatedOpacity(
                  opacity: _blurOpacity.value,
                  duration: const Duration(milliseconds: 200),
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: blurValue,
                        sigmaY: blurValue,
                      ),
                      child: Container(
                        color: const Color(0xFF0A0A0F).withOpacity(0.72),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.shield_outlined,
                                size: 32,
                                color: Colors.white.withOpacity(0.9),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'PeekShield active',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Red border pulse when blurring
            if (_controller.value > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _borderColor,
                    builder: (context, _) => DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: (_borderColor.value ?? Colors.transparent)
                              .withOpacity(_blurOpacity.value * 0.6),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
