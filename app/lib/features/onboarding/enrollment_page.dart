import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:peek_shield_core/peek_shield_core.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';

/// Live front-camera enrollment screen.
///
/// Shows an animated face-outline guide and lets the user tap to capture
/// their face embedding. On success → navigates to vault home.
/// "Skip" → angle-only detection mode (no enrollment).
class EnrollmentPage extends ConsumerStatefulWidget {
  const EnrollmentPage({super.key});

  @override
  ConsumerState<EnrollmentPage> createState() => _EnrollmentPageState();
}

class _EnrollmentPageState extends ConsumerState<EnrollmentPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  bool _capturing = false;
  String? _errorMessage;
  bool _success = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    setState(() {
      _capturing = true;
      _errorMessage = null;
    });

    try {
      final service = ref.read(enrollmentProvider);
      // enrollmentProvider exposes FaceEnrollmentService
      // This call triggers capture + embedding extraction
      final result = await service.enrollFromLiveCapture();

      if (!mounted) return;

      switch (result) {
        case EnrollmentResult.success:
          setState(() => _success = true);
          await Future.delayed(const Duration(milliseconds: 800));
          if (mounted) context.go(AppRoutes.vault);
        case EnrollmentResult.noFaceDetected:
          setState(() => _errorMessage = 'No face detected. Move closer.');
        case EnrollmentResult.faceNotCentered:
          setState(
            () => _errorMessage = 'Look straight at the camera and try again.',
          );
        case EnrollmentResult.modelError:
          setState(() => _errorMessage = 'Processing error. Please retry.');
      }
    } catch (e) {
      setState(() => _errorMessage = 'Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _skip() => context.go(AppRoutes.vault);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgSurface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              _buildHeader(),
              const SizedBox(height: 48),
              _buildCameraPreview(),
              const SizedBox(height: 32),
              _buildInstructions(),
              const Spacer(),
              _buildActions(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        const Icon(Icons.shield_outlined, color: AppTheme.accentBlue, size: 48),
        const SizedBox(height: 12),
        Text(
          'Set Up Face Recognition',
          style: Theme.of(context).textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'PeekShield will learn your face to detect unauthorized viewers.',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildCameraPreview() {
    return SizedBox(
      width: 260,
      height: 320,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Camera preview placeholder (real preview from CameraService)
          Container(
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.borderSubtle),
            ),
            child: const Center(
              child: Icon(
                Icons.camera_front,
                size: 64,
                color: AppTheme.textMuted,
              ),
            ),
          ),

          // Animated face-outline SVG overlay
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, _) {
              return Transform.scale(
                scale: _pulseAnim.value,
                child: CustomPaint(
                  size: const Size(220, 280),
                  painter: _FaceOutlinePainter(
                    color: _success
                        ? AppTheme.accentGreen
                        : (_errorMessage != null
                            ? AppTheme.accentRed
                            : AppTheme.accentBlue),
                  ),
                ),
              );
            },
          ),

          // Success overlay
          if (_success)
            Container(
              decoration: BoxDecoration(
                color: AppTheme.accentGreen.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Center(
                child: Icon(
                  Icons.check_circle_outline,
                  size: 64,
                  color: AppTheme.accentGreen,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInstructions() {
    if (_errorMessage != null) {
      return Text(
        _errorMessage!,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: AppTheme.accentRed),
        textAlign: TextAlign.center,
      );
    }
    if (_success) {
      return Text(
        'Face enrolled successfully!',
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: AppTheme.accentGreen),
        textAlign: TextAlign.center,
      );
    }
    return Column(
      children: [
        _InstructionRow(
          icon: Icons.straighten,
          text: 'Hold phone at eye level',
        ),
        const SizedBox(height: 8),
        _InstructionRow(
          icon: Icons.face_retouching_natural,
          text: 'Look straight at the camera',
        ),
        const SizedBox(height: 8),
        _InstructionRow(
          icon: Icons.light_mode_outlined,
          text: 'Ensure good lighting',
        ),
      ],
    );
  }

  Widget _buildActions() {
    return Column(
      children: [
        FilledButton(
          onPressed: _capturing ? null : _capture,
          child: _capturing
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Capture My Face'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _skip,
          child: Text(
            'Skip — use angle detection only',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

// ── Instruction row ───────────────────────────────────────────────────────────

class _InstructionRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InstructionRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: AppTheme.textSecondary),
        const SizedBox(width: 8),
        Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

// ── Face outline painter ──────────────────────────────────────────────────────

class _FaceOutlinePainter extends CustomPainter {
  final Color color;
  const _FaceOutlinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final dashPaint = Paint()
      ..color = color.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Oval face outline
    final faceRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.47),
      width: size.width * 0.72,
      height: size.height * 0.78,
    );

    // Draw dashed oval
    _drawDashedOval(canvas, faceRect, dashPaint);

    // Corner arc accents
    final cornerSize = 28.0;
    final corners = [
      // top-left
      Rect.fromLTWH(
        faceRect.left - 4,
        faceRect.top - 4,
        cornerSize,
        cornerSize,
      ),
      // top-right
      Rect.fromLTWH(
        faceRect.right - cornerSize + 4,
        faceRect.top - 4,
        cornerSize,
        cornerSize,
      ),
      // bottom-left
      Rect.fromLTWH(
        faceRect.left - 4,
        faceRect.bottom - cornerSize + 4,
        cornerSize,
        cornerSize,
      ),
      // bottom-right
      Rect.fromLTWH(
        faceRect.right - cornerSize + 4,
        faceRect.bottom - cornerSize + 4,
        cornerSize,
        cornerSize,
      ),
    ];

    final angles = [180.0, 270.0, 90.0, 0.0];
    for (int i = 0; i < corners.length; i++) {
      canvas.drawArc(
        corners[i],
        _degToRad(angles[i]),
        _degToRad(90),
        false,
        paint,
      );
    }
  }

  void _drawDashedOval(Canvas canvas, Rect rect, Paint paint) {
    const dashCount = 32;
    const dashAngle = (2 * 3.14159) / dashCount;
    for (int i = 0; i < dashCount; i += 2) {
      canvas.drawArc(rect, i * dashAngle, dashAngle * 0.8, false, paint);
    }
  }

  double _degToRad(double deg) => deg * (3.14159 / 180.0);

  @override
  bool shouldRepaint(_FaceOutlinePainter oldDelegate) =>
      oldDelegate.color != color;
}
