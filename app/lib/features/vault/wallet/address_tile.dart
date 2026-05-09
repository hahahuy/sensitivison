import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_theme.dart';
import 'wallet_page.dart';

// ── Network helpers ───────────────────────────────────────────────────────────

Color _networkColor(WalletNetwork network) {
  return switch (network) {
    WalletNetwork.ethereum => AppTheme.accentBlue,
    WalletNetwork.bitcoin => AppTheme.accentOrange,
    WalletNetwork.solana => AppTheme.accentGreen,
    WalletNetwork.other => AppTheme.textMuted,
  };
}

String _networkLabel(WalletNetwork network) {
  return switch (network) {
    WalletNetwork.ethereum => 'Ethereum',
    WalletNetwork.bitcoin => 'Bitcoin',
    WalletNetwork.solana => 'Solana',
    WalletNetwork.other => 'Other',
  };
}

/// Truncates a crypto address to "first6...last4" form for compact display.
String _truncateAddress(String address) {
  if (address.length <= 12) return address;
  return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
}

// ── AddressTile ──────────────────────────────────────────────────────────────

/// A collapsible tile that displays a [WalletEntry]'s address in compact form
/// and, when expanded, reveals the full address, a QR code, network badge, and
/// balance — all wrapped in [_PeekBlurLayer] so sensitive content is blurred
/// whenever a peek is detected.
class AddressTile extends ConsumerStatefulWidget {
  const AddressTile({super.key, required this.entry, this.onCopy});

  final WalletEntry entry;

  /// Optional callback invoked when the copy button is tapped.  The caller
  /// (WalletPage) supplies this so it can show a snackbar and reset peek state.
  final VoidCallback? onCopy;

  @override
  ConsumerState<AddressTile> createState() => _AddressTileState();
}

class _AddressTileState extends ConsumerState<AddressTile> {
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final Color netColor = _networkColor(widget.entry.network);

    return GestureDetector(
      onTap: _toggle,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.borderSubtle, width: 0.5),
        ),
        child: AnimatedCrossFade(
          duration: const Duration(milliseconds: 250),
          crossFadeState:
              _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild: _CollapsedBody(
            entry: widget.entry,
            netColor: netColor,
            onCopy: widget.onCopy,
            onToggle: _toggle,
          ),
          secondChild: _ExpandedBody(
            entry: widget.entry,
            netColor: netColor,
            onCopy: widget.onCopy,
            onToggle: _toggle,
          ),
        ),
      ),
    );
  }
}

// ── Collapsed view ────────────────────────────────────────────────────────────

class _CollapsedBody extends StatelessWidget {
  const _CollapsedBody({
    required this.entry,
    required this.netColor,
    required this.onCopy,
    required this.onToggle,
  });

  final WalletEntry entry;
  final Color netColor;
  final VoidCallback? onCopy;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          // Network colour dot
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: netColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          // Label + truncated address
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.label,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _truncateAddress(entry.address),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontFamily: 'monospace',
                        letterSpacing: 0.5,
                      ),
                ),
              ],
            ),
          ),
          // Copy icon
          IconButton(
            icon: const Icon(Icons.copy_outlined, size: 18),
            color: AppTheme.textSecondary,
            tooltip: 'Copy address',
            onPressed: onCopy,
          ),
          // Expand chevron
          Icon(
            Icons.expand_more,
            color: AppTheme.textMuted,
          ),
        ],
      ),
    );
  }
}

// ── Expanded view ─────────────────────────────────────────────────────────────

class _ExpandedBody extends StatelessWidget {
  const _ExpandedBody({
    required this.entry,
    required this.netColor,
    required this.onCopy,
    required this.onToggle,
  });

  final WalletEntry entry;
  final Color netColor;
  final VoidCallback? onCopy;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row (same as collapsed) ─────────────────────────────
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: netColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  entry.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_outlined, size: 18),
                color: AppTheme.textSecondary,
                tooltip: 'Copy address',
                onPressed: onCopy,
              ),
              Icon(Icons.expand_less, color: AppTheme.textMuted),
            ],
          ),
          const SizedBox(height: 16),

          // ── Full address (protected) ────────────────────────────────────
          Text(
            'Address',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: AppTheme.textMuted),
          ),
          const SizedBox(height: 6),
          _PeekBlurLayer(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.bgCardElevated,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                entry.address,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      letterSpacing: 0.8,
                      color: AppTheme.textPrimary,
                    ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── QR code (protected) ─────────────────────────────────────────
          _PeekBlurLayer(
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: entry.address,
                  version: QrVersions.auto,
                  size: 180,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Network badge ───────────────────────────────────────────────
          Row(
            children: [
              Chip(
                label: Text(
                  _networkLabel(entry.network),
                  style: TextStyle(
                    color: netColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                backgroundColor: netColor.withOpacity(0.12),
                side: BorderSide(color: netColor.withOpacity(0.35), width: 0.5),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Balance (protected) ─────────────────────────────────────────
          Text(
            'Balance',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: AppTheme.textMuted),
          ),
          const SizedBox(height: 6),
          _PeekBlurLayer(
            child: Text(
              entry.balance,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Peek blur layer ───────────────────────────────────────────────────────────

/// Wraps [child] and applies a blur + dim overlay whenever [peekStateProvider]
/// indicates a peek is in progress or [screenCaptureProvider] detects
/// screen recording.
///
/// A tap on the overlay does nothing (content is hidden); it only clears once
/// the peek state resolves back to `PeekState.clear`.
class _PeekBlurLayer extends ConsumerWidget {
  const _PeekBlurLayer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch screen-capture state (returns false when permission is absent or
    // platform channel is unavailable — safe default).
    final isCapturing = ref.watch(screenCaptureProvider).maybeWhen(
          data: (v) => v,
          orElse: () => false,
        );

    // Watch peek state via the provider defined in wallet_page.dart.
    final peekState = ref.watch(peekStateProvider).maybeWhen(
          data: (s) => s,
          orElse: () => null,
        );

    final bool shouldBlur =
        isCapturing || peekState == PeekStateValue.peeking;

    return Stack(
      children: [
        child,
        if (shouldBlur)
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                color: AppTheme.bgCard.withOpacity(0.92),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.visibility_off_outlined,
                        color: AppTheme.peekActive,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Hidden',
                        style:
                            Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: AppTheme.peekActive,
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
