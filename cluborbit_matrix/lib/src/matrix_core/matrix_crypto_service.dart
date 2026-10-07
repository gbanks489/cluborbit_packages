import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'matrix_low_level_client.dart';
import 'native/frb_generated.dart' show CluborbitMatrixNative;
import 'native/lib.dart' as native;

/// Bridges the native Rust crypto engine (cluborbit_matrix_native, see rust/src/lib.rs) into the
/// existing REST-based Matrix client — drives the outgoing-requests pump, feeds `/sync` data in,
/// and provides encrypt/decrypt for room events. Mirrors cluborbit-web's chatService.js lifecycle;
/// that file is the reference behavior each method here is meant to match.
class MatrixCryptoService {
  MatrixCryptoService(this._client);

  final MatrixLowLevelClient _client;
  native.CryptoSession? _session;

  bool get isReady => _session != null;

  /// True when this launch created a brand-new store (first run, or the old one was set aside),
  /// meaning any message decrypted before now was decrypted without this store's keys.
  bool createdFreshStore = false;

  static Future<void>? _nativeInit;

  static Future<void> _ensureNativeInitialized() =>
      _nativeInit ??= CluborbitMatrixNative.init().catchError((Object e) {
        _nativeInit = null;
        throw e;
      });

  /// Opens (or creates) this device's persistent, encrypted-at-rest crypto store and immediately
  /// drains whatever outgoing requests that produces — this is where the very first device-key
  /// upload happens, making this device discoverable by other clients (like cluborbit-web) for
  /// the first time. Must be called after login, once currentUserId/currentDeviceId are set.
  /// `passphrase` encrypts the on-disk store; pass the account password, the same way
  /// chatService.js derives its secret-storage key from it, so there's nothing new to remember.
  Future<void> initialize({required String passphrase}) async {
    final userId = _client.currentUserId;
    final deviceId = _client.currentDeviceId;
    if (userId == null ||
        userId.isEmpty ||
        deviceId == null ||
        deviceId.isEmpty) {
      throw StateError('Cannot initialize crypto before logging in.');
    }
    final timer = Stopwatch()..start();
    void lap(String phase) {
      debugPrint('[crypto] timing: $phase at ${timer.elapsedMilliseconds} ms');
    }

    final supportDir = await getApplicationSupportDirectory();
    final storePath = '${supportDir.path}/matrix-crypto/$userId';
    // A closed-app push may be decrypting with this store right now (see
    // BackgroundNotificationDecryptor); two open sessions would each cache Olm state and could
    // overwrite the other's ratchet progress, so let it finish first.
    await waitForBackgroundStoreUse();
    try {
      await _ensureNativeInitialized();
      Future<native.CryptoSession> open() => native.CryptoSession.create(
        userId: userId,
        deviceId: deviceId,
        storePath: storePath,
        passphrase: passphrase,
      );
      createdFreshStore = !await Directory(storePath).exists();
      try {
        _session = await open();
      } catch (e) {
        createdFreshStore = true;
        // A store created for a different device (or passphrase) can't be reopened. Move it aside
        // (kept, not deleted) and start a fresh one; room keys come back from the key backup.
        debugPrint(
          '[crypto] could not open store (${e is native.CryptoError ? e.message : e}); moving it aside and starting fresh',
        );
        final dir = Directory(storePath);
        if (await dir.exists()) {
          await dir.rename(
            '$storePath.old-${DateTime.now().millisecondsSinceEpoch}',
          );
        }
        _session = await open();
      }
      debugPrint(
        '[crypto] session created for $userId/$deviceId at $storePath',
      );
      lap('store opened (fresh=$createdFreshStore)');
    } catch (e, st) {
      debugPrint('[crypto] FAILED to create session: $e\n$st');
      rethrow;
    }
    await drainOutgoingRequests();
    lap('initial outgoing-requests drain');
    final restoredCrossSigning = await _restoreFromSecretStorage(
      password: passphrase,
    );
    lap('SSSS + key backup restore (crossSigning=$restoredCrossSigning)');
    if (!restoredCrossSigning) {
      await bootstrapCrossSigning(password: passphrase);
      lap('cross-signing bootstrap');
    }
    // In the background: the first run on an existing install uploads the whole backlog, which
    // mustn't hold up decrypting (callers wait for initialize before decrypting anything).
    unawaited(() async {
      await _ensureKeyBackup(passphrase);
      lap('key backup ensured');
      // Upload whatever this store holds that the backup doesn't yet (keys received/created while
      // no backup was active, e.g. by an older build that never uploaded).
      await backupRoomKeys();
      lap('room keys backed up');
    }());
  }

  bool _backingUp = false;
  bool _backupRequested = false;

  /// Uploads every room key not yet in the active server-side backup, in batches, so a reinstall
  /// (or any new device) can restore the full history. A no-op when no backup is active. Safe to
  /// call often: concurrent calls coalesce into one more pass rather than overlapping uploads.
  Future<void> backupRoomKeys() async {
    final session = _session;
    if (session == null) return;
    if (_backingUp) {
      _backupRequested = true;
      return;
    }
    _backingUp = true;
    var uploadedBatches = 0;
    try {
      do {
        _backupRequested = false;
        // Bounded as a safety net; each batch is up to 100 keys.
        for (var i = 0; i < 200; i++) {
          final request = await session.backupRoomKeys();
          if (request == null) break;
          final responseJson = await _client.sendCryptoRequest(
            method: request.method,
            pathAndQuery: request.path,
            bodyJson: request.bodyJson,
          );
          await session.markRequestAsSent(
            id: request.id,
            kind: request.kind,
            responseJson: responseJson,
          );
          uploadedBatches++;
        }
      } while (_backupRequested && identical(session, _session));
      if (uploadedBatches > 0) {
        final counts = await session.roomKeyCounts();
        debugPrint(
          '[crypto] key backup: uploaded $uploadedBatches batch(es); ${counts.backedUp}/${counts.total} room keys backed up',
        );
      }
    } catch (e) {
      // Retried on the next sync/share; the engine re-offers anything not confirmed as sent.
      debugPrint(
        '[crypto] key backup upload failed: ${e is native.CryptoError ? e.message : e}',
      );
    } finally {
      _backingUp = false;
    }
  }

  /// Makes sure a server-side key backup is active, creating one (and, for an account that has
  /// never had it, password-derived secret storage to hold its key) when there is none - the
  /// equivalent of cluborbit-web's bootstrapSecretStorage({setupNewKeyBackup: !existingBackup}).
  /// Uses the same password-derived secret-storage scheme as the web, so either client restores
  /// from what the other created. Conservative by design: any failed read aborts rather than being
  /// mistaken for "missing" (which would replace existing secret storage or backups), and an
  /// existing secret storage the password can't unlock is left untouched.
  Future<void> _ensureKeyBackup(String password) async {
    final session = _session;
    if (session == null) return;
    try {
      if (await session.isKeyBackupEnabled()) {
        final counts = await session.roomKeyCounts();
        debugPrint(
          '[crypto] key backup active; ${counts.backedUp}/${counts.total} room keys backed up',
        );
        return;
      }

      // 1. The secret-storage key that protects the backup key.
      final String keyId;
      final Uint8List masterKey;
      final defaultKey = await _client.getAccountDataStrict(
        'm.secret_storage.default_key',
      );
      final existingKeyId = (defaultKey?['key'] as String?)?.trim() ?? '';
      if (existingKeyId.isNotEmpty) {
        final derived = await _deriveVerifiedMasterKey(password);
        if (derived == null) {
          debugPrint(
            '[crypto] key backup: secret storage exists but the password does not unlock it; not touching it',
          );
          return;
        }
        (keyId, masterKey) = derived;
      } else {
        final created = await native.ssssCreateKeyFromPassphrase(
          passphrase: password,
        );
        keyId = created.keyId;
        masterKey = Uint8List.fromList(created.masterKey);
        await _client.setAccountData('m.secret_storage.key.$keyId', {
          'algorithm': 'm.secret_storage.v1.aes-hmac-sha2',
          'passphrase': {
            'algorithm': 'm.pbkdf2',
            'salt': created.salt,
            'iterations': created.iterations,
            'bits': 256,
          },
          'iv': created.checkIv,
          'mac': created.checkMac,
        });
        // Store the cross-signing identity too, so other devices can recover it (as the web does).
        final crossSigning = await session.exportCrossSigningKeys();
        final secrets = <String, String?>{
          'm.cross_signing.master': crossSigning?.masterKey,
          'm.cross_signing.self_signing': crossSigning?.selfSigningKey,
          'm.cross_signing.user_signing': crossSigning?.userSigningKey,
        };
        for (final entry in secrets.entries) {
          final value = entry.value;
          if (value != null && value.isNotEmpty) {
            await _storeSecret(entry.key, value, keyId, masterKey);
          }
        }
        // Only now make it the default, once everything under it is in place.
        await _client.setAccountData('m.secret_storage.default_key', {
          'key': keyId,
        });
        debugPrint('[crypto] key backup: created secret storage key $keyId');
      }

      // 2. Reuse the server's current backup if its key is in secret storage.
      final storedBackupKey = await _readSecretStrict(
        'm.megolm_backup.v1',
        keyId,
        masterKey,
      );
      final currentVersion = await _getBackupVersionStrict();
      if (storedBackupKey != null && currentVersion != null) {
        final activated = await session.enableKeyBackupFromSecret(
          decryptionKeyBase64: storedBackupKey,
          versionInfoJson: currentVersion,
        );
        if (activated) {
          debugPrint(
            '[crypto] key backup: activated existing backup version ${(jsonDecode(currentVersion) as Map)['version']}',
          );
          return;
        }
      }

      // 3. No backup, or one whose key nobody can recover (so it can never be restored from
      // anyway): create a new version and keep its key in secret storage.
      final created = await session.newKeyBackup();
      await _client.sendCryptoRequest(
        method: 'POST',
        pathAndQuery: '/_matrix/client/v3/room_keys/version',
        bodyJson: created.createVersionBodyJson,
      );
      await _storeSecret(
        'm.megolm_backup.v1',
        created.decryptionKeyBase64,
        keyId,
        masterKey,
      );
      final newVersion = await _getBackupVersionStrict();
      if (newVersion == null) {
        debugPrint(
          '[crypto] key backup: created a version but cannot read it back',
        );
        return;
      }
      final activated = await session.enableKeyBackupFromSecret(
        decryptionKeyBase64: created.decryptionKeyBase64,
        versionInfoJson: newVersion,
      );
      debugPrint(
        '[crypto] key backup: created new backup version ${(jsonDecode(newVersion) as Map)['version']}, activated=$activated',
      );
    } catch (e) {
      debugPrint(
        '[crypto] key backup setup failed (will retry next launch): ${e is native.CryptoError ? e.message : e}',
      );
    }
  }

  /// `GET /room_keys/version` body, or null only when the account has no backup (404).
  Future<String?> _getBackupVersionStrict() async {
    try {
      return await _client.sendCryptoRequest(
        method: 'GET',
        pathAndQuery: '/_matrix/client/v3/room_keys/version',
        bodyJson: '',
      );
    } on StateError catch (e) {
      if (e.message.contains('[M_NOT_FOUND]')) return null;
      rethrow;
    }
  }

  /// A secret's plaintext, or null only when it isn't stored under `keyId`; throws if the read
  /// itself fails.
  Future<String?> _readSecretStrict(
    String secretType,
    String keyId,
    Uint8List masterKey,
  ) async {
    final data = await _client.getAccountDataStrict(secretType);
    final payload = (data?['encrypted'] as Map?)?[keyId] as Map?;
    final iv = payload?['iv'] as String?;
    final ciphertext = payload?['ciphertext'] as String?;
    final mac = payload?['mac'] as String?;
    if (iv == null || ciphertext == null || mac == null) return null;
    try {
      return await native.ssssDecryptSecret(
        masterKey: masterKey,
        secretName: secretType,
        ivBase64: iv,
        ciphertextBase64: ciphertext,
        macBase64: mac,
      );
    } catch (_) {
      return null;
    }
  }

  /// Encrypts and stores one secret under `keyId`, keeping any copies under other keys.
  Future<void> _storeSecret(
    String secretType,
    String value,
    String keyId,
    Uint8List masterKey,
  ) async {
    final encrypted = await native.ssssEncryptSecret(
      masterKey: masterKey,
      secretName: secretType,
      plaintext: value,
    );
    final existing = await _client.getAccountDataStrict(secretType);
    final byKey = Map<String, dynamic>.from(
      (existing?['encrypted'] as Map?) ?? const {},
    );
    byKey[keyId] = {
      'iv': encrypted.iv,
      'ciphertext': encrypted.ciphertext,
      'mac': encrypted.mac,
    };
    await _client.setAccountData(secretType, {'encrypted': byKey});
  }

  /// Name registered with IsolateNameServer while a background isolate has the store open.
  static const String backgroundStorePortName = 'cluborbit_bg_crypto_store';

  /// Waits (bounded) until no background isolate is using the crypto store.
  static Future<void> waitForBackgroundStoreUse({
    Duration timeout = const Duration(seconds: 25),
  }) async {
    if (IsolateNameServer.lookupPortByName(backgroundStorePortName) == null) {
      return;
    }
    debugPrint(
      '[crypto] waiting for background notification decrypt to finish',
    );
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (IsolateNameServer.lookupPortByName(backgroundStorePortName) == null) {
        return;
      }
    }
    debugPrint(
      '[crypto] background decrypt still running after $timeout; continuing',
    );
  }

  /// Opens this device's EXISTING store only - for decrypting a notification while the app is
  /// closed. Unlike [initialize] it never creates or replaces a store (a new store would mint new
  /// identity keys for a device others already know - see [hasStoreForUser]) and skips the slow
  /// secret-storage / key-backup / cross-signing steps. Returns false if there's no usable store.
  Future<bool> openExistingStore({required String passphrase}) async {
    final userId = _client.currentUserId;
    final deviceId = _client.currentDeviceId;
    if (userId == null ||
        userId.isEmpty ||
        deviceId == null ||
        deviceId.isEmpty) {
      return false;
    }
    final supportDir = await getApplicationSupportDirectory();
    final storePath = '${supportDir.path}/matrix-crypto/$userId';
    if (!await Directory(storePath).exists()) return false;
    try {
      await _ensureNativeInitialized();
      _session = await native.CryptoSession.create(
        userId: userId,
        deviceId: deviceId,
        storePath: storePath,
        passphrase: passphrase,
      );
      return true;
    } catch (e) {
      debugPrint('[crypto] background open of existing store failed: $e');
      _session = null;
      return false;
    }
  }

  /// Whether a crypto store already exists for this account on this device — `username` is the
  /// login localpart (or a full `@user:server` ID). A saved device ID must never be paired with a
  /// brand-new store: that mints new identity keys for a device other clients already know, and
  /// matrix-sdk-crypto (on web too) permanently ignores an Ed25519 change for a known device, so they
  /// keep sharing room keys to the old identity and nothing sent from here decrypts for them.
  static Future<bool> hasStoreForUser(String username) async {
    try {
      final dir = Directory(
        '${(await getApplicationSupportDirectory()).path}/matrix-crypto',
      );
      if (!await dir.exists()) return false;
      final normalized = username.trim().toLowerCase();
      final prefix = normalized.startsWith('@') ? normalized : '@$normalized:';
      await for (final entry in dir.list(followLinks: false)) {
        final name = entry.uri.pathSegments
            .where((s) => s.isNotEmpty)
            .last
            .toLowerCase();
        if (name.contains('.old-')) continue;
        if (normalized.startsWith('@')
            ? name == prefix
            : name.startsWith(prefix))
          return true;
      }
      return false;
    } catch (_) {
      // Can't tell — keep the saved device rather than piling up new ones.
      return true;
    }
  }

  /// Whether the Ed25519 key the homeserver publishes for this device differs from the local
  /// store's — the broken state hasStoreForUser() prevents, but one a device can already be in (a
  /// store moved aside in initialize(), or keys uploaded by an earlier crypto implementation). False
  /// when the server has no keys for the device yet.
  Future<bool> hasMismatchedDeviceKeys() async {
    final session = _session;
    final userId = _client.currentUserId;
    final deviceId = _client.currentDeviceId;
    if (session == null ||
        userId == null ||
        deviceId == null ||
        deviceId.isEmpty)
      return false;
    final local = await session.identityKeys();
    final responseJson = await _client.sendCryptoRequest(
      method: 'POST',
      pathAndQuery: '/_matrix/client/v3/keys/query',
      bodyJson: jsonEncode({
        'device_keys': {
          userId: [deviceId],
        },
      }),
    );
    final response = jsonDecode(responseJson);
    final deviceKeys = response is Map ? response['device_keys'] : null;
    final userDevices = deviceKeys is Map ? deviceKeys[userId] : null;
    final device = userDevices is Map ? userDevices[deviceId] : null;
    final keys = device is Map ? device['keys'] : null;
    final published = keys is Map ? keys['ed25519:$deviceId'] : null;
    return published is String &&
        published.isNotEmpty &&
        published != local.ed25519;
  }

  /// Drops the open session (closing its store) so `initialize` can run again for a new device.
  void close() {
    _session?.dispose();
    _session = null;
  }

  /// Recovers this account's existing 4S-protected secrets (cross-signing private keys, key
  /// backup decryption key) using the account password — matching cluborbit-web's
  /// `crypto.bootstrapSecretStorage()` call in chatService.js, which derives the same recovery key
  /// deterministically from the same password, so this unlocks the exact secrets web already
  /// stored rather than a separate/incompatible 4S setup. Returns whether cross-signing keys were
  /// recovered this way (so `initialize` knows whether it still needs to fall back to
  /// `bootstrapCrossSigning`, which would otherwise generate a NEW identity that conflicts with
  /// the one already published). Best-effort throughout — an account that has never set up 4S
  /// (no `m.secret_storage.default_key`), or one whose secrets don't decrypt with this password's
  /// derived key, is a normal, silent case: this just does nothing.
  Future<bool> _restoreFromSecretStorage({required String password}) async {
    final session = _session;
    if (session == null) return false;
    try {
      final derived = await _deriveVerifiedMasterKey(password);
      if (derived == null) return false;
      final (keyId, masterKey) = derived;

      final crossSigningRestored = await _restoreCrossSigning(
        session,
        keyId,
        masterKey,
      );
      await _restoreKeyBackup(session, keyId, masterKey);
      return crossSigningRestored;
    } catch (e, st) {
      debugPrint('[crypto] SSSS restore failed: $e\n$st');
      return false;
    }
  }

  /// Fetches this account's default 4S key info and derives + verifies the master key from the
  /// password against it — returns null (rather than throwing) for every "can't recover this way"
  /// case: no 4S set up, this key isn't password-based, or the password doesn't produce a key
  /// matching the published check value.
  Future<(String, Uint8List)?> _deriveVerifiedMasterKey(String password) async {
    final defaultKeyData = await _client.getAccountData(
      'm.secret_storage.default_key',
    );
    final keyId = (defaultKeyData?['key'] as String?)?.trim();
    if (keyId == null || keyId.isEmpty) return null;

    final keyInfo = await _client.getAccountData('m.secret_storage.key.$keyId');
    if (keyInfo == null ||
        keyInfo['algorithm'] != 'm.secret_storage.v1.aes-hmac-sha2')
      return null;

    final passphraseInfo = keyInfo['passphrase'] as Map?;
    if (passphraseInfo == null || passphraseInfo['algorithm'] != 'm.pbkdf2')
      return null;
    final salt = passphraseInfo['salt'] as String?;
    final iterations = passphraseInfo['iterations'] as int?;
    final checkIv = keyInfo['iv'] as String?;
    final checkMac = keyInfo['mac'] as String?;
    if (salt == null ||
        iterations == null ||
        checkIv == null ||
        checkMac == null)
      return null;

    final masterKey = await native.ssssDeriveMasterKey(
      passphrase: password,
      salt: salt,
      iterations: iterations,
    );
    final valid = await native.ssssCheckMasterKey(
      masterKey: masterKey,
      checkIvBase64: checkIv,
      expectedMacBase64: checkMac,
    );
    return valid ? (keyId, masterKey) : null;
  }

  /// Decrypts one 4S-protected secret (e.g. "m.cross_signing.master") — null if it isn't stored
  /// under this key id, or fails to decrypt (a corrupt payload, or — since callers already verified
  /// the master key itself — something that shouldn't happen in practice).
  Future<String?> _decryptStoredSecret(
    String secretType,
    String keyId,
    Uint8List masterKey,
  ) async {
    final data = await _client.getAccountData(secretType);
    final payload = (data?['encrypted'] as Map?)?[keyId] as Map?;
    final iv = payload?['iv'] as String?;
    final ciphertext = payload?['ciphertext'] as String?;
    final mac = payload?['mac'] as String?;
    if (iv == null || ciphertext == null || mac == null) return null;
    try {
      return await native.ssssDecryptSecret(
        masterKey: masterKey,
        secretName: secretType,
        ivBase64: iv,
        ciphertextBase64: ciphertext,
        macBase64: mac,
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> _restoreCrossSigning(
    native.CryptoSession session,
    String keyId,
    Uint8List masterKey,
  ) async {
    final master = await _decryptStoredSecret(
      'm.cross_signing.master',
      keyId,
      masterKey,
    );
    final selfSigning = await _decryptStoredSecret(
      'm.cross_signing.self_signing',
      keyId,
      masterKey,
    );
    final userSigning = await _decryptStoredSecret(
      'm.cross_signing.user_signing',
      keyId,
      masterKey,
    );
    if (master == null && selfSigning == null && userSigning == null)
      return false;
    try {
      return await session.importCrossSigningKeys(
        masterKey: master,
        selfSigningKey: selfSigning,
        userSigningKey: userSigning,
      );
    } catch (_) {
      return false;
    }
  }

  /// Activates this account's existing server-side key backup (if any) and pulls in every session
  /// key it holds — this is what makes message history from before this device existed readable.
  /// Never creates a NEW backup version: doing so would orphan every other device's (like
  /// cluborbit-web's) already-uploaded backup, so this only ever joins one that already exists.
  Future<void> _restoreKeyBackup(
    native.CryptoSession session,
    String keyId,
    Uint8List masterKey,
  ) async {
    final decryptionKeyBase64 = await _decryptStoredSecret(
      'm.megolm_backup.v1',
      keyId,
      masterKey,
    );
    if (decryptionKeyBase64 == null) {
      debugPrint(
        '[crypto] key backup: no m.megolm_backup.v1 secret in 4S, skipping',
      );
      return;
    }
    try {
      final versionInfoJson = await _client.sendCryptoRequest(
        method: 'GET',
        pathAndQuery: '/_matrix/client/v3/room_keys/version',
        bodyJson: '',
      );
      final activated = await session.enableKeyBackupFromSecret(
        decryptionKeyBase64: decryptionKeyBase64,
        versionInfoJson: versionInfoJson,
      );
      debugPrint(
        '[crypto] key backup: activated=$activated, version info=$versionInfoJson',
      );
      if (!activated) return;

      final versionInfo = jsonDecode(versionInfoJson) as Map;
      final version = versionInfo['version'] as String;
      // Skip the (growing) full download when this store already holds every key the backup has
      // - keys imported from or uploaded to this backup count as backed up locally.
      final serverCount = versionInfo['count'];
      if (!createdFreshStore && serverCount is int) {
        final local = await session.roomKeyCounts();
        if (local.backedUp >= serverCount) {
          debugPrint(
            '[crypto] key backup: up to date ($serverCount keys in backup, ${local.backedUp} here); skipping download',
          );
          return;
        }
      }
      final keysResponseJson = await _client.sendCryptoRequest(
        method: 'GET',
        pathAndQuery:
            '/_matrix/client/v3/room_keys/keys?version=${Uri.encodeQueryComponent(version)}',
        bodyJson: '',
      );
      final imported = await session.importRoomKeysFromBackup(
        keysResponseJson: keysResponseJson,
      );
      final counts = await session.roomKeyCounts();
      debugPrint(
        '[crypto] key backup: restored $imported room keys from backup version $version (store now has ${counts.total}, ${counts.backedUp} backed up)',
      );
    } catch (e) {
      // Best-effort — see initialize()'s doc comment on this class's general failure handling.
      debugPrint(
        '[crypto] key backup restore FAILED: ${e is native.CryptoError ? e.message : e}',
      );
    }
  }

  /// Publishes this account's cross-signing identity (master/self-signing/user-signing keys), the
  /// same one-time step cluborbit-web's chatService.js does via `crypto.bootstrapCrossSigning()` —
  /// once done, this device shows up as cross-signed/verified to other users instead of relying on
  /// per-device trust-on-first-use. A no-op once already done for this account (checked first, so
  /// this is cheap to call on every login). Best-effort: cross-signing isn't required for basic
  /// encrypt/decrypt to work, so a failure here (an unusual UIA flow this homeserver demands, a
  /// transient network error) is swallowed rather than blocking the rest of crypto init.
  Future<void> bootstrapCrossSigning({required String password}) async {
    final session = _session;
    if (session == null) return;
    try {
      if (await session.isCrossSigningReady()) return;
      final bootstrap = await session.bootstrapCrossSigning(password: password);
      final requests = <native.PendingRequest>[
        if (bootstrap.uploadKeysReq != null) bootstrap.uploadKeysReq!,
        bootstrap.uploadSigningKeysReq,
        bootstrap.uploadSignaturesReq,
      ];
      for (final request in requests) {
        final responseJson = await _client.sendCryptoRequest(
          method: request.method,
          pathAndQuery: request.path,
          bodyJson: request.bodyJson,
        );
        await session.markRequestAsSent(
          id: request.id,
          kind: request.kind,
          responseJson: responseJson,
        );
      }
    } catch (_) {
      // See doc comment — best-effort, non-fatal.
    }
  }

  /// Sends every request the crypto engine currently has queued, feeding each response back in —
  /// repeats until nothing's left, since handling one response can produce more requests (e.g. a
  /// keys_query response discovering a new device can trigger a keys_claim for it).
  Future<void> drainOutgoingRequests() async {
    final session = _session;
    if (session == null) return;
    // Bounded, not `while (true)`, purely as a safety net against a bug causing an infinite
    // request/response cycle — 10 rounds is far more than any real exchange should ever need.
    for (var round = 0; round < 10; round++) {
      final requests = await session.outgoingRequests();
      if (requests.isEmpty) return;
      for (final request in requests) {
        try {
          final responseJson = await _client.sendCryptoRequest(
            method: request.method,
            pathAndQuery: request.path,
            bodyJson: request.bodyJson,
          );
          await session.markRequestAsSent(
            id: request.id,
            kind: request.kind,
            responseJson: responseJson,
          );
        } catch (_) {
          // Best-effort — a failed request (rate limiting, a transient network error) just means
          // it's handed back again on the next drainOutgoingRequests() call, rather than blocking
          // every other request in this batch.
        }
      }
    }
  }

  /// Feeds one `/sync` response's crypto-relevant pieces into the engine — call this after every
  /// successful sync poll, with the same raw JSON map MatrixLowLevelClient.sync() returns.
  Future<void> processSyncResponse(Map<String, dynamic> syncResponse) async {
    final session = _session;
    if (session == null) return;

    final toDeviceEvents =
        ((syncResponse['to_device'] as Map?)?['events'] as List?)
            ?.map((e) => jsonEncode(e))
            .toList() ??
        const <String>[];

    final deviceLists = syncResponse['device_lists'] as Map?;
    final changed =
        (deviceLists?['changed'] as List?)?.cast<String>() ?? const <String>[];
    final left =
        (deviceLists?['left'] as List?)?.cast<String>() ?? const <String>[];

    final rawKeyCounts =
        (syncResponse['device_one_time_keys_count'] as Map?) ?? const {};
    final keyCounts = rawKeyCounts.entries
        .map((e) => (e.key.toString(), BigInt.from((e.value as num).toInt())))
        .toList();

    await session.receiveSyncChanges(
      toDeviceEventsJson: toDeviceEvents,
      changedDeviceUsers: changed,
      leftDeviceUsers: left,
      oneTimeKeyCounts: keyCounts,
    );

    await drainOutgoingRequests();
    // Room keys arrive as to-device messages; back up any this sync delivered.
    if (toDeviceEvents.isNotEmpty) unawaited(backupRoomKeys());
  }

  /// Prepares a room for encrypted sending — ensures 1-to-1 sessions with every member's devices
  /// and shares (or rotates) the room's Megolm session, draining the resulting requests
  /// (keys_claim, to_device) as it goes. Call this before the first `encryptRoomEvent` for a
  /// room, and again whenever the membership list changes.
  Future<void> prepareRoomForEncryption(
    String roomId,
    List<String> memberUserIds,
  ) async {
    final session = _session;
    if (session == null) return;
    // Track the members first so their device lists get queried (the drain sends the keys_query);
    // otherwise the machine never learns about their devices and shares the key with nobody.
    await session.updateTrackedUsers(userIds: memberUserIds);
    await drainOutgoingRequests();
    // The keys_claim that sets up Olm sessions with devices we haven't talked to yet is handed back
    // only here, never via outgoingRequests — skipping it means shareRoomKey silently withholds the
    // key from those devices (e.g. a new web session), which then show "unable to decrypt".
    final claim = await session.ensureSessionsForUsers(userIds: memberUserIds);
    if (claim != null) {
      try {
        final responseJson = await _client.sendCryptoRequest(
          method: claim.method,
          pathAndQuery: claim.path,
          bodyJson: claim.bodyJson,
        );
        await session.markRequestAsSent(
          id: claim.id,
          kind: claim.kind,
          responseJson: responseJson,
        );
      } catch (e) {
        debugPrint('[crypto] keys_claim for $roomId failed: $e');
      }
    }
    // The to-device messages carrying the room key are likewise handed back only here. Unsent, the
    // key never leaves this device and recipients can't decrypt anything it sends.
    final shareRequests = await session.shareRoomKey(
      roomId: roomId,
      userIds: memberUserIds,
    );
    for (final request in shareRequests) {
      try {
        final responseJson = await _client.sendCryptoRequest(
          method: request.method,
          pathAndQuery: request.path,
          bodyJson: request.bodyJson,
        );
        await session.markRequestAsSent(
          id: request.id,
          kind: request.kind,
          responseJson: responseJson,
        );
      } catch (e) {
        debugPrint('[crypto] room key share for $roomId failed: $e');
      }
    }
    await drainOutgoingRequests();
    // Sharing may have created a new outbound session (whose key this device also keeps).
    unawaited(backupRoomKeys());
  }

  /// Megolm-encrypts a plaintext event for a room — `prepareRoomForEncryption` must have been
  /// called for this room first. Returns the content to send as an `m.room.encrypted` event.
  Future<Map<String, dynamic>> encryptRoomEvent({
    required String roomId,
    required String eventType,
    required Map<String, dynamic> content,
  }) async {
    final session = _session;
    if (session == null) throw StateError('Crypto session not initialized.');
    final resultJson = await session.encryptRoomEvent(
      roomId: roomId,
      eventType: eventType,
      contentJson: jsonEncode(content),
    );
    return jsonDecode(resultJson) as Map<String, dynamic>;
  }

  /// Decrypts an `m.room.encrypted` timeline event — pass the full raw event map exactly as
  /// received (type, sender, content, etc., not just the content). Returns the decrypted
  /// plaintext event content.
  Future<Map<String, dynamic>> decryptRoomEvent({
    required String roomId,
    required Map<String, dynamic> event,
  }) async {
    final session = _session;
    if (session == null) throw StateError('Crypto session not initialized.');
    try {
      final resultJson = await session.decryptRoomEvent(
        roomId: roomId,
        eventJson: jsonEncode(event),
      );
      return jsonDecode(resultJson) as Map<String, dynamic>;
    } catch (e) {
      debugPrint(
        '[crypto] decryptRoomEvent FAILED for ${event['event_id']} in $roomId: ${e is native.CryptoError ? e.message : e}',
      );
      rethrow;
    }
  }
}
