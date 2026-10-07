import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../matrix_core/matrix_crypto_service.dart';
import '../matrix_core/matrix_low_level_client.dart';
import 'chat_secure_storage.dart';
import 'matrix_rest_service.dart';

/// Decrypts the message a chat push points at while the app is closed - the same job WhatsApp /
/// Signal / Element X do in their notification handlers. Android starts the process for the push
/// and runs the Firebase background isolate; this opens a minimal Matrix client plus this device's
/// existing crypto store (no chat list, no sync loop, no store creation), fetches the one event and
/// decrypts it. If its room key hasn't been received yet, it pulls just the pending to-device
/// messages once and retries. The session details it needs are saved by the running app
/// ([saveSession]) each time chat connects.
///
/// Coordination with the full app: while this has the store open it registers
/// [MatrixCryptoService.backgroundStorePortName], and the app's crypto init waits for that to clear
/// before opening the store itself. It also leaves the server's to-device queue un-acknowledged
/// (it never syncs with a `since` token), so the app still receives everything when it next syncs;
/// re-processing an already-imported room key is harmless.
class BackgroundNotificationDecryptor {
  BackgroundNotificationDecryptor._();

  static const String _storageKey = 'co_matrix_background_decrypt';
  static const FlutterSecureStorage _secureStorage = chatSecureStorage;

  /// Only to-device messages (room keys), device-list changes and key counts - no rooms.
  static const Map<String, dynamic> _toDeviceOnlyFilter = {
    'room': {'rooms': <String>[]},
    'presence': {'types': <String>[]},
    'account_data': {'types': <String>[]},
  };

  /// Saves what a closed-app decrypt needs, in encrypted storage. `passphrase` unlocks the crypto
  /// store (the account password - see MatrixCryptoService.initialize).
  static Future<void> saveSession({
    required String homeserver,
    required String accessToken,
    required String userId,
    required String deviceId,
    required String passphrase,
  }) async {
    try {
      await _secureStorage.write(
        key: _storageKey,
        value: jsonEncode({
          'homeserver': homeserver,
          'accessToken': accessToken,
          'userId': userId,
          'deviceId': deviceId,
          'passphrase': passphrase,
        }),
      );
    } catch (e) {
      debugPrint('[push-bg] failed to save session: $e');
    }
  }

  static Future<void> clearSession() async {
    try {
      await _secureStorage.delete(key: _storageKey);
    } catch (_) {}
  }

  /// The notification text for `eventId` (e.g. the message, or "📷 Sent you an image"), or null
  /// when it can't be decrypted within `budget` - the caller then keeps its placeholder.
  static Future<String?> decryptNotificationText({
    required String roomId,
    required String eventId,
    Duration budget = const Duration(seconds: 15),
  }) async {
    return _withSession<String>(
      label: 'decrypt of $eventId',
      budget: budget,
      body: (client, openCrypto) async {
        final event = await client.getEvent(roomId, eventId);
        if ((event['type'] ?? '').toString() != 'm.room.encrypted') {
          return _textFor(event);
        }
        final crypto = await openCrypto();
        if (crypto == null) return null;
        for (var attempt = 1; attempt <= 2; attempt++) {
          try {
            final decrypted = await crypto.decryptRoomEvent(
              roomId: roomId,
              event: event,
            );
            return _textFor(decrypted);
          } catch (e) {
            debugPrint(
              '[push-bg] attempt $attempt: $eventId not decryptable yet: $e',
            );
            if (attempt == 2) break;
            // The push can beat the to-device message carrying this room key: fetch pending
            // to-device traffic (without acknowledging it) so the engine can import the key.
            final sync = await client.sync(filter: _toDeviceOnlyFilter);
            await crypto.processSyncResponse(sync);
          }
        }
        return null;
      },
    );
  }

  /// Sends a notification inline reply while the app is closed: encrypted exactly like a message
  /// sent from the chat screen (room key shared with every member device first), or plain in an
  /// unencrypted room, then marks the room read up to `readUpToEventId`. Returns whether it sent.
  static Future<bool> sendReply({
    required String roomId,
    required String text,
    String? readUpToEventId,
    Duration budget = const Duration(seconds: 25),
  }) async {
    final eventId = await _withSession<String>(
      label: 'reply to $roomId',
      budget: budget,
      // The store may be briefly held by a notification decrypt; wait for it.
      waitForStore: true,
      body: (client, openCrypto) async {
        final content = {'msgtype': 'm.text', 'body': text};
        String sentId;
        if (await _isRoomEncrypted(client, roomId)) {
          final crypto = await openCrypto();
          if (crypto == null) return null;
          final members = await client.sendCryptoRequest(
            method: 'GET',
            pathAndQuery:
                '/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/joined_members',
            bodyJson: '',
          );
          final joined = (jsonDecode(members) as Map)['joined'];
          final memberIds = joined is Map
              ? joined.keys.map((k) => k.toString()).toList()
              : <String>[];
          await crypto.prepareRoomForEncryption(roomId, memberIds);
          final encrypted = await crypto.encryptRoomEvent(
            roomId: roomId,
            eventType: 'm.room.message',
            content: content,
          );
          sentId = await client.sendCallEvent(
            roomId: roomId,
            eventType: 'm.room.encrypted',
            content: encrypted,
          );
        } else {
          sentId = await client.sendCallEvent(
            roomId: roomId,
            eventType: 'm.room.message',
            content: content,
          );
        }
        final readTo = (readUpToEventId ?? '').trim();
        if (readTo.isNotEmpty) {
          try {
            await client.sendCryptoRequest(
              method: 'POST',
              pathAndQuery:
                  '/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/read_markers',
              bodyJson: jsonEncode({'m.fully_read': readTo, 'm.read': readTo}),
            );
          } catch (_) {}
        }
        return sentId;
      },
    );
    return eventId != null;
  }

  static Future<bool> _isRoomEncrypted(
    MatrixLowLevelClient client,
    String roomId,
  ) async {
    try {
      await client.sendCryptoRequest(
        method: 'GET',
        pathAndQuery:
            '/_matrix/client/v3/rooms/${Uri.encodeComponent(roomId)}/state/m.room.encryption',
        bodyJson: '',
      );
      return true;
    } on StateError catch (e) {
      if (e.message.contains('[M_NOT_FOUND]')) return false;
      rethrow;
    }
  }

  /// Loads the saved session, takes the store lock (see the class doc) and runs `body` with a
  /// minimal client; `openCrypto` opens this device's existing store on demand. Always releases
  /// the store and the lock. Null if there's no session, the lock is busy, or anything fails.
  static Future<T?> _withSession<T>({
    required String label,
    required Duration budget,
    required Future<T?> Function(
      MatrixLowLevelClient client,
      Future<MatrixCryptoService?> Function() openCrypto,
    )
    body,
    bool waitForStore = false,
  }) async {
    final port = ReceivePort();
    var registered = IsolateNameServer.registerPortWithName(
      port.sendPort,
      MatrixCryptoService.backgroundStorePortName,
    );
    if (!registered && waitForStore) {
      await MatrixCryptoService.waitForBackgroundStoreUse(
        timeout: const Duration(seconds: 10),
      );
      registered = IsolateNameServer.registerPortWithName(
        port.sendPort,
        MatrixCryptoService.backgroundStorePortName,
      );
    }
    if (!registered) {
      // Another background task holds the store; don't open a second session on it.
      port.close();
      debugPrint('[push-bg] $label skipped: crypto store busy');
      return null;
    }
    MatrixCryptoService? crypto;
    try {
      return await () async {
        final raw = await _secureStorage.read(key: _storageKey);
        if (raw == null || raw.isEmpty) {
          debugPrint('[push-bg] no saved session; open the app once to enable');
          return null;
        }
        final saved = jsonDecode(raw) as Map<String, dynamic>;
        String field(String key) => (saved[key] ?? '').toString().trim();
        final homeserver = field('homeserver');
        final accessToken = field('accessToken');
        final userId = field('userId');
        final deviceId = field('deviceId');
        final passphrase = field('passphrase');
        if ([
          homeserver,
          accessToken,
          userId,
          deviceId,
          passphrase,
        ].any((value) => value.isEmpty)) {
          return null;
        }
        final client = MatrixLowLevelClient(homeserver: homeserver)
          ..restoreSession(
            accessToken: accessToken,
            userId: userId,
            deviceId: deviceId,
          );
        return body(client, () async {
          if (crypto != null) return crypto;
          final opened = MatrixCryptoService(client);
          if (!await opened.openExistingStore(passphrase: passphrase)) {
            return null;
          }
          return crypto = opened;
        });
      }().timeout(budget);
    } catch (e) {
      debugPrint('[push-bg] $label failed: $e');
      return null;
    } finally {
      crypto?.close();
      IsolateNameServer.removePortNameMapping(
        MatrixCryptoService.backgroundStorePortName,
      );
      port.close();
    }
  }

  static String? _textFor(Map<String, dynamic> event) {
    final content = event['content'];
    if (content is! Map) return null;
    return MatrixRestService.notificationTextForContent(
      content.map((key, value) => MapEntry(key.toString(), value)),
    );
  }
}
