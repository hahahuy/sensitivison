/// Unit tests for [CreditCard] model helpers and [CardForm] validators.
///
/// These are pure-function tests — no Flutter widgets, no platform channels.
/// They cover:
///   • CreditCard.last4, maskedNumber, formattedNumber
///   • CreditCard serialisation (toJson / fromJson round-trip)
///   • CreditCard.copyWith
///   • Luhn algorithm (_luhnCheck)
///   • Expiry validation (_validExpiry)
///
/// Run with:
///   flutter test app/test/credit_card_model_test.dart
library;

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Inline copies of the private helpers from credit_card_vault_page.dart and
// card_form.dart so we can test them without importing Flutter widgets.
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
  final String number;
  final String expiry;
  final String cvv;
  final String label;

  CreditCard copyWith({
    String? id,
    String? holderName,
    String? number,
    String? expiry,
    String? cvv,
    String? label,
  }) => CreditCard(
    id: id ?? this.id,
    holderName: holderName ?? this.holderName,
    number: number ?? this.number,
    expiry: expiry ?? this.expiry,
    cvv: cvv ?? this.cvv,
    label: label ?? this.label,
  );

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
    final buf = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) buf.write(' ');
      buf.write(digits[i]);
    }
    return buf.toString();
  }
}

bool luhnCheck(String number) {
  final digits = number.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 13 || digits.length > 19) return false;
  int sum = 0;
  bool alternate = false;
  for (int i = digits.length - 1; i >= 0; i--) {
    int n = int.parse(digits[i]);
    if (alternate) {
      n *= 2;
      if (n > 9) n -= 9;
    }
    sum += n;
    alternate = !alternate;
  }
  return sum % 10 == 0;
}

bool validExpiry(String s, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final parts = s.split('/');
  if (parts.length != 2) return false;
  final mm = int.tryParse(parts[0]);
  final yy = int.tryParse(parts[1]);
  if (mm == null || yy == null) return false;
  if (mm < 1 || mm > 12) return false;
  final currentYear = ref.year % 100;
  final currentMonth = ref.month;
  if (yy < currentYear) return false;
  if (yy == currentYear && mm < currentMonth) return false;
  return true;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── CreditCard helpers ────────────────────────────────────────────────────

  group('CreditCard.last4', () {
    test('returns last 4 digits of a 16-digit PAN', () {
      const c = CreditCard(
        id: '1', holderName: 'A', number: '4111111111111111',
        expiry: '12/30', cvv: '123',
      );
      expect(c.last4, '1111');
    });

    test('strips spaces before extracting', () {
      const c = CreditCard(
        id: '1', holderName: 'A', number: '4111 1111 1111 1111',
        expiry: '12/30', cvv: '123',
      );
      expect(c.last4, '1111');
    });

    test('short number returns full number', () {
      const c = CreditCard(
        id: '1', holderName: 'A', number: '123',
        expiry: '12/30', cvv: '123',
      );
      expect(c.last4, '123');
    });

    test('AMEX 15-digit PAN returns last 4', () {
      const c = CreditCard(
        id: '1', holderName: 'A', number: '378282246310005',
        expiry: '12/30', cvv: '1234',
      );
      expect(c.last4, '0005');
    });
  });

  group('CreditCard.maskedNumber', () {
    test('standard Visa format', () {
      const c = CreditCard(
        id: '1', holderName: 'A', number: '4242424242424242',
        expiry: '12/30', cvv: '123',
      );
      expect(c.maskedNumber, '•••• •••• •••• 4242');
    });

    test('masked number always shows exactly 4 trailing digits', () {
      const c = CreditCard(
        id: '1', holderName: 'A', number: '5500005555555559',
        expiry: '12/30', cvv: '123',
      );
      expect(c.maskedNumber, endsWith('5559'));
      expect(c.maskedNumber, startsWith('••••'));
    });
  });

  group('CreditCard.formattedNumber', () {
    test('inserts spaces every 4 digits', () {
      const c = CreditCard(
        id: '1', holderName: 'A', number: '4111111111111111',
        expiry: '12/30', cvv: '123',
      );
      expect(c.formattedNumber, '4111 1111 1111 1111');
    });

    test('idempotent — already-spaced input gives same result', () {
      const c = CreditCard(
        id: '1', holderName: 'A', number: '4111 1111 1111 1111',
        expiry: '12/30', cvv: '123',
      );
      expect(c.formattedNumber, '4111 1111 1111 1111');
    });

    test('15-digit AMEX does not add trailing space', () {
      const c = CreditCard(
        id: '1', holderName: 'A', number: '378282246310005',
        expiry: '12/30', cvv: '1234',
      );
      expect(c.formattedNumber, '3782 8224 6310 005');
      expect(c.formattedNumber, isNot(endsWith(' ')));
    });
  });

  // ── Serialisation ─────────────────────────────────────────────────────────

  group('CreditCard serialisation', () {
    const card = CreditCard(
      id: 'abc123',
      holderName: 'Jane Doe',
      number: '4111111111111111',
      expiry: '03/28',
      cvv: '737',
      label: 'Personal Visa',
    );

    test('toJson contains all fields', () {
      final j = card.toJson();
      expect(j['id'], 'abc123');
      expect(j['holderName'], 'Jane Doe');
      expect(j['number'], '4111111111111111');
      expect(j['expiry'], '03/28');
      expect(j['cvv'], '737');
      expect(j['label'], 'Personal Visa');
    });

    test('fromJson round-trips perfectly', () {
      final encoded = jsonEncode(card.toJson());
      final decoded = CreditCard.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );
      expect(decoded.id, card.id);
      expect(decoded.holderName, card.holderName);
      expect(decoded.number, card.number);
      expect(decoded.expiry, card.expiry);
      expect(decoded.cvv, card.cvv);
      expect(decoded.label, card.label);
    });

    test('fromJson with missing label defaults to empty string', () {
      final json = card.toJson()..remove('label');
      final decoded = CreditCard.fromJson(json);
      expect(decoded.label, '');
    });
  });

  // ── copyWith ──────────────────────────────────────────────────────────────

  group('CreditCard.copyWith', () {
    const original = CreditCard(
      id: 'id1', holderName: 'Alice', number: '4111111111111111',
      expiry: '12/26', cvv: '001', label: 'Work',
    );

    test('unchanged fields are preserved', () {
      final copy = original.copyWith(cvv: '999');
      expect(copy.id, original.id);
      expect(copy.holderName, original.holderName);
      expect(copy.number, original.number);
      expect(copy.expiry, original.expiry);
      expect(copy.label, original.label);
    });

    test('only the specified field changes', () {
      final copy = original.copyWith(holderName: 'Bob');
      expect(copy.holderName, 'Bob');
      expect(copy.cvv, original.cvv);
    });

    test('all fields can be overridden at once', () {
      final copy = original.copyWith(
        id: 'id2', holderName: 'Eve', number: '5500005555555559',
        expiry: '06/29', cvv: '456', label: 'Personal',
      );
      expect(copy.id, 'id2');
      expect(copy.holderName, 'Eve');
      expect(copy.label, 'Personal');
    });
  });

  // ── Luhn check ────────────────────────────────────────────────────────────

  group('luhnCheck', () {
    test('valid Visa test number passes', () {
      expect(luhnCheck('4111111111111111'), isTrue);
    });

    test('valid Mastercard test number passes', () {
      expect(luhnCheck('5500005555555559'), isTrue);
    });

    test('valid AMEX test number passes', () {
      expect(luhnCheck('378282246310005'), isTrue);
    });

    test('valid Discover test number passes', () {
      expect(luhnCheck('6011111111111117'), isTrue);
    });

    test('number with spaces still passes', () {
      expect(luhnCheck('4111 1111 1111 1111'), isTrue);
    });

    test('invalid number fails', () {
      expect(luhnCheck('4111111111111112'), isFalse);
    });

    test('all-zeros fails', () {
      expect(luhnCheck('0000000000000000'), isFalse);
    });

    test('too short (< 13 digits) fails', () {
      expect(luhnCheck('41111111111'), isFalse); // 11 digits
    });

    test('too long (> 19 digits) fails', () {
      expect(luhnCheck('12345678901234567890'), isFalse);
    });

    test('sequential digits (known invalid) fails', () {
      expect(luhnCheck('1234567890123456'), isFalse);
    });

    test('single off-by-one digit fails', () {
      // Change last digit of valid Visa number
      expect(luhnCheck('4111111111111110'), isFalse);
    });
  });

  // ── Expiry validation ──────────────────────────────────────────────────────

  group('validExpiry', () {
    // Use a fixed reference date: March 2025
    final refDate = DateTime(2025, 3, 15);

    test('current month/year is valid', () {
      expect(validExpiry('03/25', now: refDate), isTrue);
    });

    test('future month same year is valid', () {
      expect(validExpiry('12/25', now: refDate), isTrue);
    });

    test('future year is valid', () {
      expect(validExpiry('01/30', now: refDate), isTrue);
    });

    test('last month is expired', () {
      expect(validExpiry('02/25', now: refDate), isFalse);
    });

    test('last year is expired', () {
      expect(validExpiry('12/24', now: refDate), isFalse);
    });

    test('month 0 is invalid', () {
      expect(validExpiry('00/30', now: refDate), isFalse);
    });

    test('month 13 is invalid', () {
      expect(validExpiry('13/30', now: refDate), isFalse);
    });

    test('wrong format (no slash) is invalid', () {
      expect(validExpiry('0325', now: refDate), isFalse);
    });

    test('non-numeric month is invalid', () {
      expect(validExpiry('MM/25', now: refDate), isFalse);
    });

    test('non-numeric year is invalid', () {
      expect(validExpiry('03/YY', now: refDate), isFalse);
    });

    test('extra slashes are invalid', () {
      expect(validExpiry('03/25/2025', now: refDate), isFalse);
    });
  });
}
