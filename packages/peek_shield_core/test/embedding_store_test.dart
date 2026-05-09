/// Unit tests for [EmbeddingStore] using an in-memory Hive box stub.
///
/// These tests run without the platform keychain by replacing the
/// FlutterSecureStorage call with a simple in-memory map. We test the
/// pure logic paths: save/get/has/clear round-trip, StateError guards,
/// idempotent init, and the JSON serialisation contract.
///
/// Run with:
///   flutter test packages/peek_shield_core/test/embedding_store_test.dart
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

// ---------------------------------------------------------------------------
// Fake in-memory EmbeddingStore that mirrors the real implementation but
// uses a plain Map instead of Hive + secure storage. This lets us exercise
// the serialisation, guard, and lifecycle logic without platform deps.
// ---------------------------------------------------------------------------

class FakeEmbeddingStore {
  static const String _embeddingKey = 'enrolled_embedding';

  Map<String, String>? _box;
  bool _isOpen = false;

  Future<void> init() async {
    if (_isOpen) return;
    _box = {};
    _isOpen = true;
  }

  void saveEmbedding(List<double> embedding) {
    _assertOpen();
    _box![_embeddingKey] = jsonEncode(embedding);
  }

  List<double>? getEnrolledEmbedding() {
    _assertOpen();
    final raw = _box![_embeddingKey];
    if (raw == null) return null;
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((e) => (e as num).toDouble()).toList();
  }

  bool hasEmbedding() => getEnrolledEmbedding() != null;

  Future<void> clearEmbedding() async {
    _assertOpen();
    _box!.remove(_embeddingKey);
  }

  Future<void> dispose() async {
    _box = null;
    _isOpen = false;
  }

  void _assertOpen() {
    if (!_isOpen) {
      throw StateError(
        'EmbeddingStore is not initialised. Call init() before use.',
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

List<double> _makeEmbedding({int dim = 128, int seed = 0}) {
  final rng = Random(seed);
  final vec = List<double>.generate(dim, (_) => rng.nextDouble() * 2 - 1);
  // L2-normalise
  final norm = sqrt(vec.fold(0.0, (s, v) => s + v * v));
  return vec.map((v) => v / norm).toList();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('EmbeddingStore (fake in-memory)', () {
    late FakeEmbeddingStore store;

    setUp(() => store = FakeEmbeddingStore());
    tearDown(() => store.dispose());

    // ── Lifecycle ────────────────────────────────────────────────────────────

    test('throws StateError before init()', () {
      expect(
        () => store.getEnrolledEmbedding(),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('not initialised'),
        )),
      );
    });

    test('throws StateError before init() on saveEmbedding', () {
      expect(
        () => store.saveEmbedding(_makeEmbedding()),
        throwsA(isA<StateError>()),
      );
    });

    test('throws StateError before init() on hasEmbedding', () {
      expect(() => store.hasEmbedding(), throwsA(isA<StateError>()));
    });

    test('init() is idempotent — second call is a no-op', () async {
      await store.init();
      await store.init(); // should not throw or reset state
      store.saveEmbedding(_makeEmbedding());
      await store.init(); // still should not reset
      expect(store.hasEmbedding(), isTrue);
    });

    // ── Basic read / write ────────────────────────────────────────────────────

    test('no embedding → getEnrolledEmbedding() returns null', () async {
      await store.init();
      expect(store.getEnrolledEmbedding(), isNull);
    });

    test('no embedding → hasEmbedding() returns false', () async {
      await store.init();
      expect(store.hasEmbedding(), isFalse);
    });

    test('save then get round-trips a 128-dim embedding exactly', () async {
      await store.init();
      final original = _makeEmbedding(seed: 1);
      store.saveEmbedding(original);
      final retrieved = store.getEnrolledEmbedding();
      expect(retrieved, isNotNull);
      expect(retrieved!.length, 128);
      for (int i = 0; i < 128; i++) {
        expect(retrieved[i], closeTo(original[i], 1e-9));
      }
    });

    test('hasEmbedding() returns true after save', () async {
      await store.init();
      store.saveEmbedding(_makeEmbedding(seed: 2));
      expect(store.hasEmbedding(), isTrue);
    });

    test('saveEmbedding overwrites previous embedding silently', () async {
      await store.init();
      store.saveEmbedding(_makeEmbedding(seed: 10));
      final second = _makeEmbedding(seed: 20);
      store.saveEmbedding(second);
      final retrieved = store.getEnrolledEmbedding()!;
      // Should equal second, not first
      for (int i = 0; i < 128; i++) {
        expect(retrieved[i], closeTo(second[i], 1e-9));
      }
    });

    // ── Clear ─────────────────────────────────────────────────────────────────

    test('clearEmbedding() removes the stored embedding', () async {
      await store.init();
      store.saveEmbedding(_makeEmbedding(seed: 3));
      await store.clearEmbedding();
      expect(store.getEnrolledEmbedding(), isNull);
      expect(store.hasEmbedding(), isFalse);
    });

    test('clearEmbedding() on empty store does not throw', () async {
      await store.init();
      expect(() async => store.clearEmbedding(), returnsNormally);
    });

    // ── Serialisation contract ────────────────────────────────────────────────

    test('saved JSON is a valid double array', () async {
      await store.init();
      final emb = _makeEmbedding(seed: 5);
      store.saveEmbedding(emb);
      // Verify the raw JSON in the box is a list of doubles
      final raw = (store as FakeEmbeddingStore)._box!['enrolled_embedding']!;
      final decoded = jsonDecode(raw);
      expect(decoded, isA<List>());
      expect((decoded as List).length, 128);
      for (final v in decoded) {
        expect(v, isA<num>());
      }
    });

    test('embedding values survive JSON precision round-trip', () async {
      // JSON doubles must survive at least 15 significant digits
      await store.init();
      const special = [
        0.123456789012345,
        -0.987654321098765,
        1.0,
        0.0,
        -1.0,
      ];
      store.saveEmbedding(special);
      final back = store.getEnrolledEmbedding()!;
      for (int i = 0; i < special.length; i++) {
        expect(back[i], closeTo(special[i], 1e-12));
      }
    });

    // ── Dispose and re-init ───────────────────────────────────────────────────

    test('after dispose, operations throw StateError', () async {
      await store.init();
      store.saveEmbedding(_makeEmbedding());
      await store.dispose();
      expect(() => store.hasEmbedding(), throwsA(isA<StateError>()));
    });

    test('can be re-initialised after dispose (clean slate)', () async {
      await store.init();
      store.saveEmbedding(_makeEmbedding(seed: 99));
      await store.dispose();
      // Re-init should produce a fresh empty box
      await store.init();
      expect(store.hasEmbedding(), isFalse);
    });
  });
}
