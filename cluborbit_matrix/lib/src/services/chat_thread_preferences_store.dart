import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class ChatThreadPreferencesSnapshot {
  const ChatThreadPreferencesSnapshot({
    required this.mutedRoomIds,
    required this.pinnedRoomIds,
    required this.forcedUnreadRoomIds,
  });

  final Set<String> mutedRoomIds;
  final Set<String> pinnedRoomIds;
  final Set<String> forcedUnreadRoomIds;
}

class ChatThreadPreferencesStore {
  factory ChatThreadPreferencesStore() => _instance;

  ChatThreadPreferencesStore._();

  static final ChatThreadPreferencesStore _instance =
      ChatThreadPreferencesStore._();

  static const String _databaseFileName = 'playerchat_local_preferences.db';
  static const String _tableName = 'chat_thread_preferences';

  Database? _database;
  Future<Database>? _openingDatabase;
  final Map<String, _ThreadPreferenceRow> _cache =
      <String, _ThreadPreferenceRow>{};
  bool _cacheLoaded = false;

  Future<ChatThreadPreferencesSnapshot> loadAll() async {
    if (_cacheLoaded) {
      return _snapshotFromCache();
    }
    final database = await _openDatabase();
    final rows = await database.query(_tableName);
    final nextCache = <String, _ThreadPreferenceRow>{};
    for (final row in rows) {
      final roomId = (row['room_id'] ?? '').toString().trim();
      if (roomId.isEmpty) {
        continue;
      }
      nextCache[roomId] = _ThreadPreferenceRow(
        muted: _asBool(row['muted']),
        pinned: _asBool(row['pinned']),
        forcedUnread: _asBool(row['forced_unread']),
      );
    }
    _cache
      ..clear()
      ..addAll(nextCache);
    _cacheLoaded = true;
    return _snapshotFromCache();
  }

  Future<void> setMuted(String roomId, bool muted) {
    return _upsertRoom(roomId, (current) => current.copyWith(muted: muted));
  }

  Future<void> setPinned(String roomId, bool pinned) {
    return _upsertRoom(roomId, (current) => current.copyWith(pinned: pinned));
  }

  Future<void> setForcedUnread(String roomId, bool forcedUnread) {
    return _upsertRoom(
      roomId,
      (current) => current.copyWith(forcedUnread: forcedUnread),
    );
  }

  Future<void> removeRoom(String roomId) async {
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty) {
      return;
    }
    final database = await _openDatabase();
    await database.delete(
      _tableName,
      where: 'room_id = ?',
      whereArgs: <Object?>[normalizedRoomId],
    );
    _cache.remove(normalizedRoomId);
  }

  Future<void> _upsertRoom(
    String roomId,
    _ThreadPreferenceRow Function(_ThreadPreferenceRow current) update,
  ) async {
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty) {
      return;
    }

    final current = _cache[normalizedRoomId] ?? const _ThreadPreferenceRow();
    final next = update(current);

    if (!next.hasAnyPreference) {
      await removeRoom(normalizedRoomId);
      return;
    }

    final database = await _openDatabase();
    await database.insert(_tableName, <String, Object?>{
      'room_id': normalizedRoomId,
      'muted': next.muted ? 1 : 0,
      'pinned': next.pinned ? 1 : 0,
      'forced_unread': next.forcedUnread ? 1 : 0,
      'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    _cache[normalizedRoomId] = next;
  }

  ChatThreadPreferencesSnapshot _snapshotFromCache() {
    final muted = <String>{};
    final pinned = <String>{};
    final forcedUnread = <String>{};

    _cache.forEach((roomId, row) {
      if (row.muted) {
        muted.add(roomId);
      }
      if (row.pinned) {
        pinned.add(roomId);
      }
      if (row.forcedUnread) {
        forcedUnread.add(roomId);
      }
    });

    return ChatThreadPreferencesSnapshot(
      mutedRoomIds: muted,
      pinnedRoomIds: pinned,
      forcedUnreadRoomIds: forcedUnread,
    );
  }

  Future<Database> _openDatabase() async {
    if (_database != null) {
      return _database!;
    }
    if (_openingDatabase != null) {
      return _openingDatabase!;
    }

    _openingDatabase = _createDatabase();
    final database = await _openingDatabase!;
    _database = database;
    _openingDatabase = null;
    return database;
  }

  Future<Database> _createDatabase() async {
    if (!_useFfiDatabase) {
      final databaseDirectory = await sqflite.getDatabasesPath();
      final databasePath = path.join(databaseDirectory, _databaseFileName);
      return sqflite.openDatabase(
        databasePath,
        version: 1,
        onCreate: (database, version) async {
          await database.execute(_createTableSql);
        },
        onOpen: (database) async {
          await database.execute(_createTableSql);
        },
      );
    }

    sqfliteFfiInit();
    final supportDirectory = await getApplicationSupportDirectory();
    final databasePath = path.join(supportDirectory.path, _databaseFileName);

    return databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, version) async {
          await database.execute(_createTableSql);
        },
        onOpen: (database) async {
          await database.execute(_createTableSql);
        },
      ),
    );
  }

  bool get _useFfiDatabase {
    if (kIsWeb) {
      return false;
    }
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  static const String _createTableSql =
      '''
CREATE TABLE IF NOT EXISTS $_tableName (
  room_id TEXT PRIMARY KEY,
  muted INTEGER NOT NULL,
  pinned INTEGER NOT NULL,
  forced_unread INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
)
''';

  bool _asBool(Object? value) {
    if (value is bool) {
      return value;
    }
    final asInt = int.tryParse('$value');
    return asInt == 1;
  }
}

class _ThreadPreferenceRow {
  const _ThreadPreferenceRow({
    this.muted = false,
    this.pinned = false,
    this.forcedUnread = false,
  });

  final bool muted;
  final bool pinned;
  final bool forcedUnread;

  bool get hasAnyPreference => muted || pinned || forcedUnread;

  _ThreadPreferenceRow copyWith({
    bool? muted,
    bool? pinned,
    bool? forcedUnread,
  }) {
    return _ThreadPreferenceRow(
      muted: muted ?? this.muted,
      pinned: pinned ?? this.pinned,
      forcedUnread: forcedUnread ?? this.forcedUnread,
    );
  }
}
