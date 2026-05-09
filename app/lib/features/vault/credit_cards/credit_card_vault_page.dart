import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:peek_shield_core/peek_shield_core.dart';

import '../../../core/theme/app_theme.dart';
import 'card_form.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

class CreditCard {
  const CreditCard({
    required this.id,
    required this.holderName,
    required this.number,
    required this.expiry,
    required this.cvv,
    this.label = '',
  });

  final String id;
  final String holderName;
  final String number; // full PAN, stored encrypted by FlutterSecureStorage
  final String expiry; // MM/YY
  final String cvv;
  final String label;

  CreditCard copyWith({
    String? id,
    String? holderName,
    String? number,
    String? expiry,
    String? cvv,
    String? label,
  }) {
    return CreditCard(
      id: id ?? this.id,
      holderName: holderName ?? this.holderName,
      number: number ?? this.number,
      expiry: expiry ?? this.expiry,
      cvv: cvv ?? this.cvv,
      label: label ?? this.label,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'holderName': holderName,
        'number': number,
        'expiry': expiry,
        'cvv': cvv,
        'label': label,
      };

  factory CreditCard.fromJson(Map<String, dynamic> json) => CreditCard(
        id: json['id'] as String,
        holderName: json['holderName'] as String,
        number: json['number'] as String,
        expiry: json['expiry'] as String,
        cvv: json['cvv'] as String,
        label: (json['label'] as String?) ?? '',
      );

  String get last4 {
    final digits = number.replaceAll(' ', '');
    if (digits.length < 4) return digits;
    return digits.substring(digits.length - 4);
  }

  String get maskedNumber => '•••• •••• •••• $last4';

  String get formattedNumber {
    final digits = number.replaceAll(' ', '');
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}

// ---------------------------------------------------------------------------
// State notifier + provider
// ---------------------------------------------------------------------------

const _kStorageKey = 'peek_shield_cards';
const _storage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

final cardsProvider =
    StateNotifierProvider<CardsNotifier, List<CreditCard>>((ref) {
  final notifier = CardsNotifier();
  notifier.load();
  return notifier;
});

class CardsNotifier extends StateNotifier<List<CreditCard>> {
  CardsNotifier() : super([]);

  Future<void> load() async {
    try {
      final raw = await _storage.read(key: _kStorageKey);
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(CreditCard.fromJson)
          .toList();
      state = list;
    } catch (_) {
      state = [];
    }
  }

  Future<void> _persist() async {
    final encoded = jsonEncode(state.map((c) => c.toJson()).toList());
    await _storage.write(key: _kStorageKey, value: encoded);
  }

  Future<void> add(CreditCard card) async {
    state = [...state, card];
    await _persist();
  }

  Future<void> update(CreditCard card) async {
    state = [
      for (final c in state)
        if (c.id == card.id) card else c,
    ];
    await _persist();
  }

  Future<void> delete(String id) async {
    state = state.where((c) => c.id != id).toList();
    await _persist();
  }
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class CreditCardVaultPage extends ConsumerStatefulWidget {
  const CreditCardVaultPage({super.key});

  static const routeName = '/vault/credit-cards';

  @override
  ConsumerState<CreditCardVaultPage> createState() =>
      _CreditCardVaultPageState();
}

class _CreditCardVaultPageState extends ConsumerState<CreditCardVaultPage> {
  String? _expandedId;

  void _toggleExpand(String id) {
    setState(() {
      _expandedId = _expandedId == id ? null : id;
    });
  }

  Future<void> _confirmDelete(BuildContext context, CreditCard card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete card?',
          style: AppTheme.textTheme.titleMedium
              ?.copyWith(color: AppTheme.textPrimary),
        ),
        content: Text(
          'Remove "${card.label.isNotEmpty ? card.label : card.maskedNumber}" from your vault? This cannot be undone.',
          style: AppTheme.textTheme.bodyMedium
              ?.copyWith(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete',
                style: TextStyle(color: AppTheme.accentRed)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(cardsProvider.notifier).delete(card.id);
      if (_expandedId == card.id) {
        setState(() => _expandedId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = ref.watch(cardsProvider);

    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppTheme.bgCard,
        elevation: 0,
        leading: const BackButton(color: AppTheme.textPrimary),
        title: Text(
          'Credit Cards',
          style: AppTheme.textTheme.titleLarge
              ?.copyWith(color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Chip(
              label: Text(
                '${cards.length}',
                style: const TextStyle(
                    color: AppTheme.accentBlue,
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
              backgroundColor: AppTheme.accentBlue.withOpacity(0.12),
              side: BorderSide.none,
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
          ),
        ],
      ),
      body: cards.isEmpty
          ? _EmptyState(
              onAdd: () => _openAddCard(context),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: cards.length,
              itemBuilder: (ctx, i) {
                final card = cards[i];
                final isExpanded = _expandedId == card.id;
                return _CardListTile(
                  card: card,
                  isExpanded: isExpanded,
                  onTap: () => _toggleExpand(card.id),
                  onEdit: () => _openEditCard(context, card),
                  onDelete: () => _confirmDelete(context, card),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddCard(context),
        backgroundColor: AppTheme.accentBlue,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_card_rounded),
        label: const Text('Add Card', fontWeight: FontWeight.w600),
      ),
    );
  }

  void _openAddCard(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const CardForm()),
    );
  }

  void _openEditCard(BuildContext context, CreditCard card) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => CardForm(existingCard: card)),
    );
  }
}

// ---------------------------------------------------------------------------
// _CardListTile
// ---------------------------------------------------------------------------

class _CardListTile extends StatelessWidget {
  const _CardListTile({
    required this.card,
    required this.isExpanded,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final CreditCard card;
  final bool isExpanded;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: AppTheme.accentBlue.withOpacity(0.08),
          highlightColor: AppTheme.accentBlue.withOpacity(0.04),
          child: Column(
            children: [
              // ── Collapsed header ──────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.accentBlue.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.credit_card_rounded,
                        color: AppTheme.accentBlue,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            card.label.isNotEmpty
                                ? card.label
                                : card.holderName,
                            style: AppTheme.textTheme.titleSmall?.copyWith(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            card.maskedNumber,
                            style: AppTheme.textTheme.bodySmall?.copyWith(
                              color: AppTheme.textSecondary,
                              fontFamily: 'monospace',
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 250),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Expanded section ──────────────────────────────────────
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 300),
                crossFadeState: isExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: const SizedBox.shrink(),
                secondChild: ProtectedWidget(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      children: [
                        const Divider(
                            color: AppTheme.bgCardElevated, height: 1),
                        const SizedBox(height: 16),
                        _GlassCard(card: card),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _ActionButton(
                              icon: Icons.copy_rounded,
                              label: 'Copy',
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(
                                      text: card.number.replaceAll(' ', '')),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Card number copied'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            _ActionButton(
                              icon: Icons.edit_rounded,
                              label: 'Edit',
                              onPressed: onEdit,
                            ),
                            const SizedBox(width: 8),
                            _ActionButton(
                              icon: Icons.delete_outline_rounded,
                              label: 'Delete',
                              color: AppTheme.accentRed,
                              onPressed: onDelete,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _GlassCard — glassmorphic credit-card widget
// ---------------------------------------------------------------------------

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.card});

  final CreditCard card;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 85.6 / 53.98, // standard ISO/IEC 7810 ID-1
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            // Background gradient
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1A2A4A), Color(0xFF0D1B35)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),

            // Blur overlay
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.accentBlue.withOpacity(0.18),
                      Colors.white.withOpacity(0.04),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.12),
                    width: 1,
                  ),
                ),
              ),
            ),

            // Decorative circles
            Positioned(
              top: -30,
              right: -20,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.accentBlue.withOpacity(0.15),
                ),
              ),
            ),
            Positioned(
              bottom: -40,
              left: 40,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.accentBlue.withOpacity(0.08),
                ),
              ),
            ),

            // Card content
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: label + chip icon
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        card.label.isNotEmpty ? card.label : 'PeekShield',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1.1,
                        ),
                      ),
                      // EMV chip placeholder
                      Container(
                        width: 32,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Center(
                          child: Icon(Icons.memory_rounded,
                              size: 14, color: Colors.black54),
                        ),
                      ),
                    ],
                  ),

                  const Spacer(),

                  // Full PAN
                  Text(
                    card.formattedNumber,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2.5,
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Bottom row: holder + expiry + CVV
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'CARD HOLDER',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 9,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              card.holderName.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.8,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'EXPIRES',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 9,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            card.expiry,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'CVV',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 9,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            card.cvv,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ActionButton
// ---------------------------------------------------------------------------

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppTheme.accentBlue;
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: effectiveColor.withOpacity(0.1),
        foregroundColor: effectiveColor,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(icon, size: 16),
      label: Text(label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
    );
  }
}

// ---------------------------------------------------------------------------
// _EmptyState
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.accentBlue.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.credit_card_rounded,
                color: AppTheme.accentBlue,
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No cards yet',
              style: AppTheme.textTheme.titleMedium?.copyWith(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the button below to securely store your first credit or debit card.',
              textAlign: TextAlign.center,
              style: AppTheme.textTheme.bodyMedium
                  ?.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: onAdd,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.add_card_rounded),
              label: const Text('Add a Card',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
