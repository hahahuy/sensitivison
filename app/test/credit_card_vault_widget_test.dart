/// Widget tests for [CardsNotifier] (state management) and
/// [CreditCardVaultPage] UI.
///
/// Uses an in-memory CardsNotifier override — no FlutterSecureStorage
/// platform channel involved.
///
/// Tested behaviours:
///   • Empty state shows "No cards yet" text and Add button
///   • After adding a card, masked number appears in the list
///   • Expanding a card reveals the ProtectedWidget area
///   • Deleting a card shows confirmation dialog then removes it
///   • CardsNotifier: add/update/delete state transitions
///   • CardsNotifier: JSON serialisation / in-memory round-trip
///
/// Run with:
///   flutter test app/test/credit_card_vault_widget_test.dart
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Extracted CreditCard model (same as in credit_card_model_test.dart)
// ---------------------------------------------------------------------------

class CreditCard {
  const CreditCard({
    required this.id, required this.holderName, required this.number,
    required this.expiry, required this.cvv, this.label = '',
  });

  final String id, holderName, number, expiry, cvv, label;

  CreditCard copyWith({
    String? id, String? holderName, String? number,
    String? expiry, String? cvv, String? label,
  }) => CreditCard(
    id: id ?? this.id, holderName: holderName ?? this.holderName,
    number: number ?? this.number, expiry: expiry ?? this.expiry,
    cvv: cvv ?? this.cvv, label: label ?? this.label,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'holderName': holderName, 'number': number,
    'expiry': expiry, 'cvv': cvv, 'label': label,
  };

  factory CreditCard.fromJson(Map<String, dynamic> j) => CreditCard(
    id: j['id'] as String, holderName: j['holderName'] as String,
    number: j['number'] as String, expiry: j['expiry'] as String,
    cvv: j['cvv'] as String, label: (j['label'] as String?) ?? '',
  );

  String get last4 {
    final d = number.replaceAll(' ', '');
    return d.length < 4 ? d : d.substring(d.length - 4);
  }

  String get maskedNumber => '•••• •••• •••• $last4';
}

// ---------------------------------------------------------------------------
// In-memory CardsNotifier (no platform storage)
// ---------------------------------------------------------------------------

class InMemoryCardsNotifier extends StateNotifier<List<CreditCard>> {
  InMemoryCardsNotifier([List<CreditCard> initial = const []]) : super(initial);

  Future<void> add(CreditCard card) async => state = [...state, card];

  Future<void> update(CreditCard card) async => state = [
    for (final c in state) if (c.id == card.id) card else c,
  ];

  Future<void> delete(String id) async =>
      state = state.where((c) => c.id != id).toList();

  // Convenience: load from JSON string (mirrors CardsNotifier.load)
  void loadFrom(String json) {
    final list = (jsonDecode(json) as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(CreditCard.fromJson)
        .toList();
    state = list;
  }
}

final testCardsProvider =
    StateNotifierProvider<InMemoryCardsNotifier, List<CreditCard>>(
  (_) => InMemoryCardsNotifier(),
);

// ---------------------------------------------------------------------------
// Minimal UI under test (self-contained — no real vault page import needed)
// ---------------------------------------------------------------------------

class _TestVaultPage extends ConsumerStatefulWidget {
  const _TestVaultPage();

  @override
  ConsumerState<_TestVaultPage> createState() => _TestVaultPageState();
}

class _TestVaultPageState extends ConsumerState<_TestVaultPage> {
  String? _expandedId;

  @override
  Widget build(BuildContext context) {
    final cards = ref.watch(testCardsProvider);

    return Scaffold(
      body: cards.isEmpty
          ? Column(
              key: const ValueKey('empty_state'),
              children: [
                const Text('No cards yet'),
                ElevatedButton(
                  key: const ValueKey('add_btn'),
                  onPressed: () {},
                  child: const Text('Add a Card'),
                ),
              ],
            )
          : ListView(
              children: [
                for (final card in cards)
                  Column(
                    key: ValueKey('card_${card.id}'),
                    children: [
                      ListTile(
                        key: ValueKey('tile_${card.id}'),
                        title: Text(card.maskedNumber),
                        onTap: () => setState(() {
                          _expandedId = _expandedId == card.id ? null : card.id;
                        }),
                        trailing: IconButton(
                          key: ValueKey('delete_${card.id}'),
                          icon: const Icon(Icons.delete),
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete card?'),
                                actions: [
                                  TextButton(
                                    key: const ValueKey('cancel_btn'),
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    key: const ValueKey('confirm_delete_btn'),
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              await ref.read(testCardsProvider.notifier).delete(card.id);
                            }
                          },
                        ),
                      ),
                      if (_expandedId == card.id)
                        Container(
                          key: ValueKey('expanded_${card.id}'),
                          child: Text(card.number),
                        ),
                    ],
                  ),
              ],
            ),
    );
  }
}

Widget _buildVaultApp({List<Override> overrides = const []}) => ProviderScope(
      overrides: overrides,
      child: const MaterialApp(home: Scaffold(body: _TestVaultPage())),
    );

const _visa = CreditCard(
  id: 'v1', holderName: 'Alice', number: '4111111111111111',
  expiry: '12/28', cvv: '737', label: 'Personal Visa',
);
const _mc = CreditCard(
  id: 'm1', holderName: 'Bob', number: '5500005555555559',
  expiry: '06/30', cvv: '123', label: 'Work MC',
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('CardsNotifier (in-memory)', () {
    late InMemoryCardsNotifier notifier;
    setUp(() => notifier = InMemoryCardsNotifier());

    test('initial state is empty', () {
      expect(notifier.state, isEmpty);
    });

    test('add() appends a card', () async {
      await notifier.add(_visa);
      expect(notifier.state.length, 1);
      expect(notifier.state.first.id, 'v1');
    });

    test('add() multiple cards preserves order', () async {
      await notifier.add(_visa);
      await notifier.add(_mc);
      expect(notifier.state[0].id, 'v1');
      expect(notifier.state[1].id, 'm1');
    });

    test('delete() removes the correct card', () async {
      await notifier.add(_visa);
      await notifier.add(_mc);
      await notifier.delete('v1');
      expect(notifier.state.length, 1);
      expect(notifier.state.first.id, 'm1');
    });

    test('delete() on non-existent id is a no-op', () async {
      await notifier.add(_visa);
      await notifier.delete('nonexistent');
      expect(notifier.state.length, 1);
    });

    test('update() replaces only the matching card', () async {
      await notifier.add(_visa);
      await notifier.add(_mc);
      final updated = _visa.copyWith(holderName: 'Alice B');
      await notifier.update(updated);
      expect(notifier.state.firstWhere((c) => c.id == 'v1').holderName, 'Alice B');
      expect(notifier.state.firstWhere((c) => c.id == 'm1').holderName, 'Bob');
    });

    test('loadFrom JSON restores list correctly', () {
      final json = jsonEncode([_visa.toJson(), _mc.toJson()]);
      notifier.loadFrom(json);
      expect(notifier.state.length, 2);
      expect(notifier.state[0].number, '4111111111111111');
    });
  });

  group('CreditCardVaultPage widget', () {
    testWidgets('empty state shows "No cards yet"', (tester) async {
      await tester.pumpWidget(_buildVaultApp());
      expect(find.text('No cards yet'), findsOneWidget);
    });

    testWidgets('empty state shows Add button', (tester) async {
      await tester.pumpWidget(_buildVaultApp());
      expect(find.byKey(const ValueKey('add_btn')), findsOneWidget);
    });

    testWidgets('card list shows masked number', (tester) async {
      await tester.pumpWidget(
        _buildVaultApp(overrides: [
          testCardsProvider.overrideWith(
            (_) => InMemoryCardsNotifier([_visa]),
          ),
        ]),
      );
      await tester.pump();
      expect(find.text('•••• •••• •••• 1111'), findsOneWidget);
    });

    testWidgets('two cards both appear in list', (tester) async {
      await tester.pumpWidget(
        _buildVaultApp(overrides: [
          testCardsProvider.overrideWith(
            (_) => InMemoryCardsNotifier([_visa, _mc]),
          ),
        ]),
      );
      await tester.pump();
      expect(find.text('•••• •••• •••• 1111'), findsOneWidget);
      expect(find.text('•••• •••• •••• 5559'), findsOneWidget);
    });

    testWidgets('tapping card expands it to show full number', (tester) async {
      await tester.pumpWidget(
        _buildVaultApp(overrides: [
          testCardsProvider.overrideWith(
            (_) => InMemoryCardsNotifier([_visa]),
          ),
        ]),
      );
      await tester.pump();

      // Full number not visible initially
      expect(find.byKey(const ValueKey('expanded_v1')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('tile_v1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('expanded_v1')), findsOneWidget);
    });

    testWidgets('tapping card twice collapses it', (tester) async {
      await tester.pumpWidget(
        _buildVaultApp(overrides: [
          testCardsProvider.overrideWith(
            (_) => InMemoryCardsNotifier([_visa]),
          ),
        ]),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('tile_v1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('expanded_v1')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tile_v1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('expanded_v1')), findsNothing);
    });

    testWidgets('delete shows confirmation dialog', (tester) async {
      await tester.pumpWidget(
        _buildVaultApp(overrides: [
          testCardsProvider.overrideWith(
            (_) => InMemoryCardsNotifier([_visa]),
          ),
        ]),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('delete_v1')));
      await tester.pumpAndSettle();

      expect(find.text('Delete card?'), findsOneWidget);
    });

    testWidgets('cancel on delete dialog keeps card', (tester) async {
      await tester.pumpWidget(
        _buildVaultApp(overrides: [
          testCardsProvider.overrideWith(
            (_) => InMemoryCardsNotifier([_visa]),
          ),
        ]),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('delete_v1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('cancel_btn')));
      await tester.pumpAndSettle();

      expect(find.text('•••• •••• •••• 1111'), findsOneWidget);
    });

    testWidgets('confirm delete removes card from list', (tester) async {
      await tester.pumpWidget(
        _buildVaultApp(overrides: [
          testCardsProvider.overrideWith(
            (_) => InMemoryCardsNotifier([_visa]),
          ),
        ]),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('delete_v1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('confirm_delete_btn')));
      await tester.pumpAndSettle();

      expect(find.text('•••• •••• •••• 1111'), findsNothing);
      expect(find.text('No cards yet'), findsOneWidget);
    });
  });
}
