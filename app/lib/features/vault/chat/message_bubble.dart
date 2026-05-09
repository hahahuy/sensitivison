import 'package:flutter/material.dart';
import 'package:peek_shield_core/peek_shield_core.dart';

import '../../../core/theme/app_theme.dart';
import 'chat_screen.dart' show ChatMessage;

/// A single chat message bubble.
///
/// - Owner messages (`isMe: true`) are right-aligned in [AppTheme.accentBlue].
/// - Peer messages (`isMe: false`) are left-aligned in [AppTheme.bgCardElevated].
///
/// The message text is always wrapped in a [ProtectedWidget] (with
/// `localOverride: false`) so it inherits the global peek state and is blurred
/// whenever PeekShield detects an unauthorised viewer — even if the surrounding
/// [ListView] is already inside a parent [ProtectedWidget].
class MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const MessageBubble({super.key, required this.message});

  // ── Layout constants ────────────────────────────────────────────────────────

  /// Maximum fraction of screen width a bubble may occupy.
  static const double _maxWidthFraction = 0.75;

  static const EdgeInsets _bubblePadding =
      EdgeInsets.symmetric(horizontal: 12, vertical: 8);

  // ── Bubble shape helpers ────────────────────────────────────────────────────

  /// Returns a [BorderRadius] with one squared-off corner:
  /// - `isMe` → bottom-right corner flat (the "tail" side).
  /// - peer  → bottom-left corner flat.
  static BorderRadius _bubbleRadius({required bool isMe}) {
    const Radius full = Radius.circular(18);
    const Radius flat = Radius.circular(4);
    return isMe
        ? const BorderRadius.only(
            topLeft: full,
            topRight: full,
            bottomLeft: full,
            bottomRight: flat,
          )
        : const BorderRadius.only(
            topLeft: full,
            topRight: full,
            bottomLeft: flat,
            bottomRight: full,
          );
  }

  // ── Timestamp formatting ────────────────────────────────────────────────────

  /// Returns a short `HH:mm` string for the message timestamp.
  static String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final maxBubbleWidth = screenWidth * _maxWidthFraction;
    final isMe = message.isMe;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxBubbleWidth),
        child: Container(
          padding: _bubblePadding,
          decoration: BoxDecoration(
            color: isMe ? AppTheme.accentBlue : AppTheme.bgCardElevated,
            borderRadius: _bubbleRadius(isMe: isMe),
            // Subtle border only on peer bubbles so they read against the
            // dark surface background.
            border: isMe
                ? null
                : Border.all(color: AppTheme.borderSubtle, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Sender name (peer only) ─────────────────────────────────
              if (!isMe) ...[
                Text(
                  message.senderName,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 3),
              ],

              // ── Message text (wrapped in ProtectedWidget) ───────────────
              ProtectedWidget(
                localOverride: false,
                child: Text(
                  message.text,
                  style: TextStyle(
                    color: isMe
                        ? AppTheme.textPrimary
                        : AppTheme.textPrimary,
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
              ),

              const SizedBox(height: 4),

              // ── Timestamp + read receipt row ────────────────────────────
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment:
                    isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                children: [
                  Text(
                    _formatTime(message.timestamp),
                    style: TextStyle(
                      color: isMe
                          ? AppTheme.textPrimary.withOpacity(0.55)
                          : AppTheme.textMuted,
                      fontSize: 10,
                    ),
                  ),
                  // ── Double-checkmark read receipt (isMe only) ───────────
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    _DoubleCheck(),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Double checkmark widget ───────────────────────────────────────────────────

/// A compact "double tick" read-receipt icon matching iMessage / WhatsApp
/// conventions, tinted to match the bubble's text style.
class _DoubleCheck extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 11,
      child: CustomPaint(painter: _DoubleCheckPainter()),
    );
  }
}

class _DoubleCheckPainter extends CustomPainter {
  static final Paint _paint = Paint()
    ..color = AppTheme.textPrimary.withOpacity(0.55)
    ..strokeWidth = 1.4
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final double h = size.height;
    final double w = size.width;

    // First tick (left, slightly offset)
    final path1 = Path()
      ..moveTo(0, h * 0.55)
      ..lineTo(w * 0.25, h * 0.95)
      ..lineTo(w * 0.55, h * 0.1);

    // Second tick (right, offset by ~4 logical pixels)
    final path2 = Path()
      ..moveTo(w * 0.32, h * 0.55)
      ..lineTo(w * 0.57, h * 0.95)
      ..lineTo(w, h * 0.1);

    canvas.drawPath(path1, _paint);
    canvas.drawPath(path2, _paint);
  }

  @override
  bool shouldRepaint(_DoubleCheckPainter oldDelegate) => false;
}
