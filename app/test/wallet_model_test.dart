/// Unit tests for [WalletEntry] model: serialisation, copyWith, network enum
/// round-trip, and [_SeedPhraseGrid] word-splitting logic.
///
/// Run with:
///   flutter test app/test/wallet_model_test.dart
library;

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Inline mirrors of the pure logic from wallet_page.dart
// ---------------------------------------------------------------------------

enum WalletNetwork { ethereum, bitcoin, solana, other }

WalletNetwork networkFromString(String s) => switch (s) {
  'ethereum' => WalletNetwork.ethereum,
  'bitcoin' => WalletNetwork.bitcoin,
  'solana' => WalletNetwork.solana,
  _ => WalletNetwork.other,
};

String networkToString(WalletNetwork n) => switch (n) {
  WalletNetwork.ethereum => 'ethereum',
  WalletNetwork.bitcoin => 'bitcoin',
  WalletNetwork.solana => 'solana',
  WalletNetwork.other => 'other',
};

class WalletEntry {
  const WalletEntry({
    required this.id,
    required this.label,
    required this.address,
    required this.balance,
    required this.network,
    this.seedPhrase,
  });

  final String id;
  final String label;
  final String address;
  final String balance;
  final WalletNetwork network;
  final String? seedPhrase;

  factory WalletEntry.fromJson(Map<String, dynamic> json) => WalletEntry(
    id: json['id'] as String,
    label: json['label'] as String,
    address: json['address'] as String,
    balance: json['balance'] as String,
    network: networkFromString(json['network'] as String? ?? 'other'),
    seedPhrase: json['seedPhrase'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'address': address,
    'balance': balance,
    'network': networkToString(network),
    if (seedPhrase != null) 'seedPhrase': seedPhrase,
  };

  WalletEntry copyWith({
    String? id, String? label, String? address,
    String? balance, WalletNetwork? network, String? seedPhrase,
  }) => WalletEntry(
    id: id ?? this.id, label: label ?? this.label,
    address: address ?? this.address, balance: balance ?? this.balance,
    network: network ?? this.network, seedPhrase: seedPhrase ?? this.seedPhrase,
  );
}

/// Mirrors _SeedPhraseGrid word-splitting logic.
List<String> splitSeedPhrase(String phrase) =>
    phrase.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── Network enum ───────────────────────────────────────────────────────────

  group('WalletNetwork serialisation', () {
    test('all known networks serialise to their string representation', () {
      expect(networkToString(WalletNetwork.ethereum), 'ethereum');
      expect(networkToString(WalletNetwork.bitcoin), 'bitcoin');
      expect(networkToString(WalletNetwork.solana), 'solana');
      expect(networkToString(WalletNetwork.other), 'other');
    });

    test('all known strings deserialise to correct enum', () {
      expect(networkFromString('ethereum'), WalletNetwork.ethereum);
      expect(networkFromString('bitcoin'), WalletNetwork.bitcoin);
      expect(networkFromString('solana'), WalletNetwork.solana);
      expect(networkFromString('other'), WalletNetwork.other);
    });

    test('unknown string falls back to WalletNetwork.other', () {
      expect(networkFromString('dogecoin'), WalletNetwork.other);
      expect(networkFromString(''), WalletNetwork.other);
    });

    test('round-trip: enum → string → enum is identity', () {
      for (final n in WalletNetwork.values) {
        expect(networkFromString(networkToString(n)), n);
      }
    });
  });

  // ── WalletEntry model ──────────────────────────────────────────────────────

  const btcEntry = WalletEntry(
    id: 'btc_01',
    label: 'Main Bitcoin',
    address: 'bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh',
    balance: '0.42387 BTC',
    network: WalletNetwork.bitcoin,
  );

  const ethWithSeed = WalletEntry(
    id: 'eth_01',
    label: 'DeFi Wallet',
    address: '0x71C7656EC7ab88b098defB751B7401B5f6d8976F',
    balance: '3.14 ETH',
    network: WalletNetwork.ethereum,
    seedPhrase:
        'abandon ability able about above absent absorb abstract absurd abuse access',
  );

  group('WalletEntry.toJson', () {
    test('contains all required fields', () {
      final j = btcEntry.toJson();
      expect(j['id'], 'btc_01');
      expect(j['label'], 'Main Bitcoin');
      expect(j['address'], 'bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh');
      expect(j['balance'], '0.42387 BTC');
      expect(j['network'], 'bitcoin');
    });

    test('seedPhrase is omitted when null', () {
      final j = btcEntry.toJson();
      expect(j.containsKey('seedPhrase'), isFalse);
    });

    test('seedPhrase is included when present', () {
      final j = ethWithSeed.toJson();
      expect(j['seedPhrase'], contains('abandon'));
    });
  });

  group('WalletEntry.fromJson round-trip', () {
    test('entry without seed phrase survives round-trip', () {
      final encoded = jsonEncode(btcEntry.toJson());
      final decoded = WalletEntry.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );
      expect(decoded.id, btcEntry.id);
      expect(decoded.label, btcEntry.label);
      expect(decoded.address, btcEntry.address);
      expect(decoded.balance, btcEntry.balance);
      expect(decoded.network, btcEntry.network);
      expect(decoded.seedPhrase, isNull);
    });

    test('entry with seed phrase survives round-trip', () {
      final decoded = WalletEntry.fromJson(
        jsonDecode(jsonEncode(ethWithSeed.toJson())) as Map<String, dynamic>,
      );
      expect(decoded.seedPhrase, ethWithSeed.seedPhrase);
    });

    test('missing network field defaults to other', () {
      final json = btcEntry.toJson()..remove('network');
      final decoded = WalletEntry.fromJson(json);
      expect(decoded.network, WalletNetwork.other);
    });

    test('list of entries survives JSON array round-trip', () {
      final entries = [btcEntry, ethWithSeed];
      final encoded = jsonEncode(entries.map((e) => e.toJson()).toList());
      final decoded = (jsonDecode(encoded) as List<dynamic>)
          .map((e) => WalletEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      expect(decoded.length, 2);
      expect(decoded[0].id, 'btc_01');
      expect(decoded[1].id, 'eth_01');
    });
  });

  group('WalletEntry.copyWith', () {
    test('unchanged fields are preserved', () {
      final copy = btcEntry.copyWith(balance: '1.0 BTC');
      expect(copy.id, btcEntry.id);
      expect(copy.label, btcEntry.label);
      expect(copy.address, btcEntry.address);
      expect(copy.network, btcEntry.network);
      expect(copy.balance, '1.0 BTC');
    });

    test('network can be changed', () {
      final copy = btcEntry.copyWith(network: WalletNetwork.ethereum);
      expect(copy.network, WalletNetwork.ethereum);
    });

    test('seedPhrase can be added to a previously seed-less entry', () {
      final copy = btcEntry.copyWith(seedPhrase: 'word1 word2 word3');
      expect(copy.seedPhrase, 'word1 word2 word3');
    });
  });

  // ── Seed phrase splitting ──────────────────────────────────────────────────

  group('splitSeedPhrase', () {
    test('12-word phrase returns 12 tokens', () {
      const phrase =
          'abandon ability able about above absent absorb abstract absurd abuse access accident';
      expect(splitSeedPhrase(phrase).length, 12);
    });

    test('24-word phrase returns 24 tokens', () {
      final phrase = List.generate(24, (i) => 'word${i + 1}').join(' ');
      expect(splitSeedPhrase(phrase).length, 24);
    });

    test('leading and trailing whitespace is trimmed', () {
      const phrase = '  word1  word2  word3  ';
      expect(splitSeedPhrase(phrase), ['word1', 'word2', 'word3']);
    });

    test('multiple spaces between words treated as single separator', () {
      const phrase = 'abandon   ability   able';
      expect(splitSeedPhrase(phrase), ['abandon', 'ability', 'able']);
    });

    test('newlines and tabs are treated as whitespace separators', () {
      const phrase = 'word1\nword2\tword3';
      expect(splitSeedPhrase(phrase), ['word1', 'word2', 'word3']);
    });

    test('empty string returns empty list', () {
      expect(splitSeedPhrase(''), isEmpty);
    });

    test('whitespace-only string returns empty list', () {
      expect(splitSeedPhrase('   \t\n  '), isEmpty);
    });

    test('word order is preserved', () {
      const phrase = 'alpha beta gamma delta';
      final words = splitSeedPhrase(phrase);
      expect(words[0], 'alpha');
      expect(words[3], 'delta');
    });
  });
}
