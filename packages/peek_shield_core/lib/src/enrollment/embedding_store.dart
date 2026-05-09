import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Persistent, AES-encrypted store for face embeddings.
///
/// All data is kept inside a Hive box whose cipher key is itself stored in the
/// platform's secure keychain / keystore via [FlutterSecureStorage].  That
/// means embeddings survive app restarts while remaining inaccessible to other
/// apps or to plain filesystem inspection.
///
/// ## Typical lifecycle
/// ```dart
/// final store = EmbeddingStore();
/// await store.init();            // open / create the encrypted box
/// store.saveEmbedding(vec);      // persist an embedding
/// final vec = store.getEnrolledEmbedding();
/// await store.dispose();         // close the box cleanly
/// ```
class EmbeddingStore {
  // -------------------------------------------------------------------------
  // Constants
  // -------------------------------------------------------------------------

  /// Name of the Hive box that holds the serialised embedding.
  static const String _boxName = 'peek_embeddings';

  /// Key under which the base64-encoded Hive cipher key is stored in the
  /// platform secure storage.
  static const String _secureKeyName = 'peek_shield_hive_key';

  /// Key inside the Hive box that maps to the enrolled embedding JSON string.
  static const String _embeddingKey = 'enrolled_embedding';

  // -------------------------------------------------------------------------
  // State
  // -------------------------------------------------------------------------

  /// The open Hive box.  `null` until [init] completes successfully.
  Box<String>? _box;

  // -------------------------------------------------------------------------
  // Initialisation
  // -------------------------------------------------------------------------

  /// Opens (or creates) the AES-encrypted Hive box.
  ///
  /// Must be called and awaited before any other method.  Safe to call
  /// multiple times — subsequent calls are no-ops when the box is already open.
  ///
  /// The cipher key is stored in the platform keychain with
  /// [KeychainAccessibility.first_unlock_this_device] on iOS so it is
  /// available after the first unlock but never migrated to iCloud backups.
  Future<void> init() async {
    if (_box != null && _box!.isOpen) return;

    const FlutterSecureStorage secureStorage = FlutterSecureStorage(
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
    );

    // Retrieve or create the Hive cipher key.
    String? existingB64Key = await secureStorage.read(key: _secureKeyName);

    final Uint8List keyBytes;

    if (existingB64Key == null) {
      // First run: generate a fresh 256-bit key and persist it.
      final List<int> newKey = Hive.generateSecureKey();
      final String newB64Key = base64UrlEncode(newKey);
      await secureStorage.write(key: _secureKeyName, value: newB64Key);
      keyBytes = Uint8List.fromList(newKey);
    } else {
      keyBytes = base64Url.decode(existingB64Key);
    }

    final HiveAesCipher cipher = HiveAesCipher(keyBytes);

    _box = await Hive.openBox<String>(
      _boxName,
      encryptionCipher: cipher,
    );
  }

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Serialises [embedding] as a JSON array and stores it in the box.
  ///
  /// Any previously stored embedding is silently overwritten.
  ///
  /// Throws a [StateError] if [init] has not been called yet.
  void saveEmbedding(List<double> embedding) {
    _assertOpen();
    final String json = jsonEncode(embedding);
    _box!.put(_embeddingKey, json);
  }

  /// Returns the previously enrolled embedding, or `null` if no embedding
  /// has been stored.
  ///
  /// Throws a [StateError] if [init] has not been called yet.
  List<double>? getEnrolledEmbedding() {
    _assertOpen();
    final String? raw = _box!.get(_embeddingKey);
    if (raw == null) return null;

    final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((e) => (e as num).toDouble()).toList();
  }

  /// Returns `true` when an enrolled embedding is present in the box.
  ///
  /// Equivalent to `getEnrolledEmbedding() != null`.
  ///
  /// Throws a [StateError] if [init] has not been called yet.
  bool hasEmbedding() => getEnrolledEmbedding() != null;

  /// Removes the enrolled embedding from the box.
  ///
  /// Throws a [StateError] if [init] has not been called yet.
  Future<void> clearEmbedding() async {
    _assertOpen();
    await _box!.delete(_embeddingKey);
  }

  /// Closes the underlying Hive box and releases its resources.
  ///
  /// After this call the store must not be used until [init] is called again.
  Future<void> dispose() async {
    if (_box != null && _box!.isOpen) {
      await _box!.close();
    }
    _box = null;
  }

  // -------------------------------------------------------------------------
  // Internal helpers
  // -------------------------------------------------------------------------

  /// Throws [StateError] when the box is not open.
  void _assertOpen() {
    if (_box == null || !_box!.isOpen) {
      throw StateError(
        'EmbeddingStore is not initialised. Call init() before use.',
      );
    }
  }
}
