import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/providers/screen_capture_provider.dart';
import 'address_tile.dart';

// ── Re-export screen capture provider so address_tile.dart can import it ────

export '../../../core/providers/screen_capture_provider.dart';

// ── PeekState value enum (thin wrapper — avoids importing the core package
//    directly into UI widgets that only care about the boolean outcome) ───────

/// Simplified peek state consumed by UI widgets.
///
/// Maps to the richer `PeekState` enum produced by the core detection service.
enum PeekStateValue { clear, uncertain, peeking }

/// A [StreamProvider] that exposes the current peek-detection state.
///
/// In production this would be backed by a running [PeekDetectionService].
/// Here we emit a static [PeekStateValue.clear] stream so the wallet page
/// renders fully with no blur in isolation; the host app wires the real
/// detection stream via a provider override in its `ProviderScope`.
final peekStateProvider = StreamProvider.autoDispose<PeekStateValue>((ref) {
  // Default: always clear.  Override in ProviderScope at app root once
  // the camera & detection pipeline is started.
  return Stream.value(PeekStateValue.clear);
});

// ── Network enum ──────────────────────────────────────────────────────────────

enum WalletNetwork { ethereum, bitcoin, solana, other }

WalletNetwork _networkFromString(String s) {
  return switch (s) {
    'ethereum' => WalletNetwork.ethereum,
    'bitcoin' => WalletNetwork.bitcoin,
    'solana' => WalletNetwork.solana,
    _ => WalletNetwork.other,
  };
}

String _networkToString(WalletNetwork n) {
  return switch (n) {
    WalletNetwork.ethereum => 'ethereum',
    WalletNetwork.bitcoin => 'bitcoin',
    WalletNetwork.solana => 'solana',
    WalletNetwork.other => 'other',
  };
}

// ── Data model ────────────────────────────────────────────────────────────────

/// Represents a single crypto wallet entry stored in secure storage.
///
/// [seedPhrase] is nullable — most entries won't expose the seed phrase unless
/// the owner explicitly added it.  It is the highest-sensitivity field and is
/// only shown behind a tap-to-reveal protected dialog.
class WalletEntry {
  final String id;
  final String label;
  final String address;
  final String balance;
  final WalletNetwork network;
  final String? seedPhrase;

  const WalletEntry({
    required this.id,
    required this.label,
    required this.address,
    required this.balance,
    required this.network,
    this.seedPhrase,
  });

  // ── Serialisation ──────────────────────────────────────────────────────────

  factory WalletEntry.fromJson(Map<String, dynamic> json) {
    return WalletEntry(
      id: json['id'] as String,
      label: json['label'] as String,
      address: json['address'] as String,
      balance: json['balance'] as String,
      network: _networkFromString(json['network'] as String? ?? 'other'),
      seedPhrase: json['seedPhrase'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'address': address,
        'balance': balance,
        'network': _networkToString(network),
        if (seedPhrase != null) 'seedPhrase': seedPhrase,
      };

  WalletEntry copyWith({
    String? id,
    String? label,
    String? address,
    String? balance,
    WalletNetwork? network,
    String? seedPhrase,
  }) {
    return WalletEntry(
      id: id ?? this.id,
      label: label ?? this.label,
      address: address ?? this.address,
      balance: balance ?? this.balance,
      network: network ?? this.network,
      seedPhrase: seedPhrase ?? this.seedPhrase,
    );
  }
}

// ── Demo data ─────────────────────────────────────────────────────────────────

const List<WalletEntry> _demoEntries = [
  WalletEntry(
    id: 'demo_btc',
    label: 'Main Bitcoin Wallet',
    address: '1A1zP1eP5QGefi2DMPTfTL5SLmv7Divf Nc',
    balance: '0.08472 BTC',
    network: WalletNetwork.bitcoin,
  ),
  WalletEntry(
    id: 'demo_eth',
    label: 'Primary Ethereum',
    address: '0x742d35Cc6634C0532925a3b844Bc454e4438f44e',
    balance: '1.3402 ETH',
    network: WalletNetwork.ethereum,
  ),
];

// ── Secure storage key ────────────────────────────────────────────────────────

const String _storageKey = 'peek_shield_wallets';
const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
  aOptions: AndroidOptions(
    encryptedSharedPreferences: true,
  ),
);

// ── Provider ──────────────────────────────────────────────────────────────────

final walletProvider =
    StateNotifierProvider<WalletNotifier, List<WalletEntry>>(
  (ref) => WalletNotifier()..load(),
);

// ── Notifier ──────────────────────────────────────────────────────────────────

class WalletNotifier extends StateNotifier<List<WalletEntry>> {
  WalletNotifier() : super(const []);

  /// Loads wallet entries from [FlutterSecureStorage].
  ///
  /// If no entries exist yet, pre-populates with two demo entries and persists
  /// them so the user sees a non-empty vault on first launch.
  Future<void> load() async {
    final String? raw = await _secureStorage.read(key: _storageKey);

    if (raw == null || raw.isEmpty) {
      // First-run: seed with demo entries.
      state = _demoEntries;
      await _persist();
      return;
    }

    try {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      state = decoded
          .map((e) => WalletEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // Corrupted data — reset to demo entries.
      state = _demoEntries;
      await _persist();
    }
  }

  /// Adds a new [WalletEntry] and persists the updated list.
  Future<void> add(WalletEntry entry) async {
    state = [...state, entry];
    await _persist();
  }

  /// Removes the entry with matching [id] and persists the updated list.
  Future<void> delete(String id) async {
    state = state.where((e) => e.id != id).toList();
    await _persist();
  }

  /// Persists the current [state] to secure storage as a JSON array.
  Future<void> _persist() async {
    final String encoded =
        jsonEncode(state.map((e) => e.toJson()).toList());
    await _secureStorage.write(key: _storageKey, value: encoded);
  }
}

// ── Page ──────────────────────────────────────────────────────────────────────

/// Crypto wallet vault page.
///
/// Lists all [WalletEntry] objects stored in [walletProvider].  Each entry is
/// rendered as an [AddressTile] which handles expand/collapse, QR display, and
/// peek-blur protection for the sensitive fields.
///
/// A seed phrase, when present, is accessible via a separate dialog that
/// requires an extra tap-to-reveal step on top of the standard peek overlay.
class WalletPage extends ConsumerStatefulWidget {
  const WalletPage({super.key});

  @override
  ConsumerState<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends ConsumerState<WalletPage> {
  @override
  Widget build(BuildContext context) {
    final wallets = ref.watch(walletProvider);

    return Scaffold(
      backgroundColor: AppTheme.bgSurface,
      appBar: AppBar(
        title: const Text('Crypto Wallet'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, size: 20),
            tooltip: 'All sensitive fields blur on peek detection',
            onPressed: () => _showInfoDialog(context),
          ),
        ],
      ),
      body: wallets.isEmpty
          ? _EmptyState(onAdd: () => _showAddDialog(context))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: wallets.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final entry = wallets[index];
                return _WalletCard(
                  entry: entry,
                  onCopy: () => _copyAddress(entry),
                  onViewSeed: entry.seedPhrase != null
                      ? () => _showSeedPhraseDialog(context, entry)
                      : null,
                  onDelete: () => _confirmDelete(context, entry),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context),
        backgroundColor: AppTheme.accentOrange,
        foregroundColor: AppTheme.textPrimary,
        icon: const Icon(Icons.add),
        label: const Text('Add Wallet'),
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _copyAddress(WalletEntry entry) async {
    await Clipboard.setData(ClipboardData(text: entry.address));
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${entry.label} address copied'),
        backgroundColor: AppTheme.accentOrange,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );

    // Invalidate peek state to trigger a fresh detection cycle — ensures the
    // overlay clears promptly after the user deliberately copies data.
    ref.invalidate(peekStateProvider);
  }

  void _showSeedPhraseDialog(BuildContext context, WalletEntry entry) {
    showDialog<void>(
      context: context,
      builder: (_) => _SeedPhraseDialog(entry: entry),
    );
  }

  void _showAddDialog(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AddWalletSheet(
        onSave: (entry) => ref.read(walletProvider.notifier).add(entry),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WalletEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Delete Wallet Entry'),
        content: Text(
          'Remove "${entry.label}" from your vault? This cannot be undone.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.accentRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(walletProvider.notifier).delete(entry.id);
    }
  }

  void _showInfoDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Peek Protection Active'),
        content: Text(
          'Full addresses, QR codes, balances, and seed phrases are '
          'automatically hidden when PeekShield detects someone looking over '
          'your shoulder or when screen recording is active.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

// ── Wallet card ───────────────────────────────────────────────────────────────

/// Wraps an [AddressTile] and adds a "View Seed Phrase" action + delete button.
class _WalletCard extends StatelessWidget {
  const _WalletCard({
    required this.entry,
    required this.onCopy,
    required this.onDelete,
    this.onViewSeed,
  });

  final WalletEntry entry;
  final VoidCallback onCopy;
  final VoidCallback onDelete;
  final VoidCallback? onViewSeed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AddressTile(entry: entry, onCopy: onCopy),
        if (onViewSeed != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onViewSeed,
                    icon: const Icon(Icons.key_outlined, size: 16),
                    label: const Text('View Seed Phrase'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accentOrange,
                      side:
                          const BorderSide(color: AppTheme.accentOrange, width: 0.8),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: AppTheme.textMuted,
                  tooltip: 'Delete entry',
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ] else ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              color: AppTheme.textMuted,
              tooltip: 'Delete entry',
              onPressed: onDelete,
            ),
          ),
        ],
      ],
    );
  }
}

// ── Seed phrase dialog ────────────────────────────────────────────────────────

/// Modal dialog for revealing a wallet's seed phrase.
///
/// The content is wrapped in a two-layer protection scheme:
///   1. [_PeekBlurSurface] — blurs whenever a peek is detected (same as
///      [_PeekBlurLayer] in address_tile.dart, implemented inline here so this
///      file is self-contained for the dialog widget).
///   2. A tap-to-reveal gesture — the phrase starts hidden behind a "Tap to
///      reveal" prompt and is only shown after an explicit user tap, adding a
///      second intentional gate on top of peek protection.
class _SeedPhraseDialog extends ConsumerStatefulWidget {
  const _SeedPhraseDialog({required this.entry});

  final WalletEntry entry;

  @override
  ConsumerState<_SeedPhraseDialog> createState() => _SeedPhraseDialogState();
}

class _SeedPhraseDialogState extends ConsumerState<_SeedPhraseDialog> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final bool isCapturing = ref.watch(screenCaptureProvider).maybeWhen(
          data: (v) => v,
          orElse: () => false,
        );
    final PeekStateValue peekState = ref.watch(peekStateProvider).maybeWhen(
          data: (s) => s,
          orElse: () => PeekStateValue.clear,
        );

    final bool shouldBlur =
        isCapturing || peekState == PeekStateValue.peeking;

    // Force hide if a peek is detected even if user tapped reveal.
    final bool showPhrase = _revealed && !shouldBlur;

    return AlertDialog(
      backgroundColor: AppTheme.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Icon(Icons.key, color: AppTheme.accentOrange, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Seed Phrase',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.entry.label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppTheme.accentRed.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: AppTheme.accentRed,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Never share your seed phrase with anyone.',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppTheme.accentRed,
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Seed phrase container — tap to reveal + peek overlay
          GestureDetector(
            onTap: () {
              if (!shouldBlur) setState(() => _revealed = true);
            },
            child: AnimatedCrossFade(
              duration: const Duration(milliseconds: 200),
              crossFadeState: showPhrase
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.bgCardElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: shouldBlur
                        ? AppTheme.accentRed.withOpacity(0.5)
                        : AppTheme.borderSubtle,
                    width: 0.5,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      shouldBlur
                          ? Icons.visibility_off_outlined
                          : Icons.touch_app_outlined,
                      color: shouldBlur
                          ? AppTheme.peekActive
                          : AppTheme.textSecondary,
                      size: 28,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      shouldBlur
                          ? 'Peek detected — hidden'
                          : 'Tap to reveal seed phrase',
                      style:
                          Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: shouldBlur
                                    ? AppTheme.peekActive
                                    : AppTheme.textSecondary,
                              ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              secondChild: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.bgCardElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.accentOrange.withOpacity(0.4),
                    width: 0.8,
                  ),
                ),
                child: _SeedPhraseGrid(
                  phrase: widget.entry.seedPhrase!,
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        if (showPhrase)
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.entry.seedPhrase!));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Seed phrase copied to clipboard'),
                  backgroundColor: AppTheme.accentOrange,
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 2),
                ),
              );
            },
            icon: const Icon(Icons.copy_outlined, size: 16),
            label: const Text('Copy'),
            style: TextButton.styleFrom(
                foregroundColor: AppTheme.accentOrange),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

// ── Seed phrase grid ──────────────────────────────────────────────────────────

/// Splits the seed [phrase] on whitespace and renders each word as a numbered
/// chip in a wrapping grid layout.
class _SeedPhraseGrid extends StatelessWidget {
  const _SeedPhraseGrid({required this.phrase});

  final String phrase;

  @override
  Widget build(BuildContext context) {
    final List<String> words =
        phrase.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(words.length, (i) {
        return Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: AppTheme.accentOrange.withOpacity(0.25), width: 0.5),
          ),
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '${i + 1}. ',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppTheme.textMuted,
                      ),
                ),
                TextSpan(
                  text: words[i],
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'monospace',
                      ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.account_balance_wallet_outlined,
              size: 64,
              color: AppTheme.accentOrange,
            ),
            const SizedBox(height: 20),
            Text(
              'No wallets yet',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Store your crypto wallet addresses, balances, and seed '
              'phrases securely with peek detection.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add Your First Wallet'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accentOrange,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Add wallet bottom sheet ───────────────────────────────────────────────────

class _AddWalletSheet extends StatefulWidget {
  const _AddWalletSheet({required this.onSave});

  final Future<void> Function(WalletEntry) onSave;

  @override
  State<_AddWalletSheet> createState() => _AddWalletSheetState();
}

class _AddWalletSheetState extends State<_AddWalletSheet> {
  final _formKey = GlobalKey<FormState>();
  final _labelCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _balanceCtrl = TextEditingController();
  final _seedCtrl = TextEditingController();

  WalletNetwork _network = WalletNetwork.ethereum;
  bool _saving = false;

  @override
  void dispose() {
    _labelCtrl.dispose();
    _addressCtrl.dispose();
    _balanceCtrl.dispose();
    _seedCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    final entry = WalletEntry(
      id: 'wallet_${DateTime.now().millisecondsSinceEpoch}',
      label: _labelCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      balance: _balanceCtrl.text.trim().isEmpty
          ? '—'
          : _balanceCtrl.text.trim(),
      network: _network,
      seedPhrase: _seedCtrl.text.trim().isEmpty ? null : _seedCtrl.text.trim(),
    );

    await widget.onSave(entry);

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, mq.viewInsets.bottom + 32),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.borderSubtle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            Text(
              'Add Wallet Entry',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 20),

            // Label
            _SheetField(
              controller: _labelCtrl,
              label: 'Wallet Label',
              hint: 'e.g. Main Ethereum Wallet',
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Label required' : null,
            ),
            const SizedBox(height: 14),

            // Network selector
            DropdownButtonFormField<WalletNetwork>(
              value: _network,
              dropdownColor: AppTheme.bgCardElevated,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: AppTheme.textPrimary),
              decoration: _inputDecoration('Network'),
              items: WalletNetwork.values
                  .map(
                    (n) => DropdownMenuItem(
                      value: n,
                      child: Text(
                        n.name[0].toUpperCase() + n.name.substring(1),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _network = v ?? _network),
            ),
            const SizedBox(height: 14),

            // Address
            _SheetField(
              controller: _addressCtrl,
              label: 'Wallet Address',
              hint: '0x... or 1A1z...',
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Address required' : null,
              maxLines: 2,
            ),
            const SizedBox(height: 14),

            // Balance
            _SheetField(
              controller: _balanceCtrl,
              label: 'Balance (optional)',
              hint: 'e.g. 1.42 ETH',
            ),
            const SizedBox(height: 14),

            // Seed phrase (optional, sensitive)
            _SheetField(
              controller: _seedCtrl,
              label: 'Seed Phrase (optional)',
              hint: 'word1 word2 word3 ...',
              maxLines: 3,
              obscure: true,
            ),
            const SizedBox(height: 8),
            Text(
              'Seed phrase is stored encrypted. Tap "View Seed Phrase" to retrieve it.',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: AppTheme.textMuted),
            ),
            const SizedBox(height: 24),

            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accentOrange,
              ),
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.textPrimary,
                      ),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Input decoration helper ───────────────────────────────────────────────────

InputDecoration _inputDecoration(String label) {
  return InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
    filled: true,
    fillColor: AppTheme.bgCardElevated,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppTheme.borderSubtle, width: 0.5),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppTheme.borderSubtle, width: 0.5),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppTheme.accentOrange, width: 1.2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppTheme.accentRed, width: 0.8),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppTheme.accentRed, width: 1.2),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  );
}

// ── Reusable sheet text field ─────────────────────────────────────────────────

class _SheetField extends StatelessWidget {
  const _SheetField({
    required this.controller,
    required this.label,
    this.hint,
    this.validator,
    this.maxLines = 1,
    this.obscure = false,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? Function(String?)? validator;
  final int maxLines;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: obscure ? 1 : maxLines,
      obscureText: obscure,
      style: Theme.of(context)
          .textTheme
          .bodyLarge
          ?.copyWith(color: AppTheme.textPrimary),
      decoration: _inputDecoration(label).copyWith(hintText: hint),
      validator: validator,
    );
  }
}
