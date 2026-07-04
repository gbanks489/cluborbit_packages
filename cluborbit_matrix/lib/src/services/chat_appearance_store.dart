import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class ChatAppearanceRecord {
  const ChatAppearanceRecord({
    required this.chatKey,
    required this.myBubbleColorValue,
    required this.otherBubbleColorValue,
    required this.messageTextColorValue,
    required this.messageFontFamily,
    this.backgroundImageUrl,
  });

  final String chatKey;
  final int myBubbleColorValue;
  final int otherBubbleColorValue;
  final int messageTextColorValue;
  final String messageFontFamily;
  final String? backgroundImageUrl;
}

class ChatAppearanceStore {
  factory ChatAppearanceStore() => _instance;

  ChatAppearanceStore._();

  static final ChatAppearanceStore _instance = ChatAppearanceStore._();

  static const String _databaseFileName = 'playerchat_local_preferences.db';
  static const String _tableName = 'chat_appearance_preferences';

  Database? _database;
  Future<Database>? _openingDatabase;
  final Map<String, ChatAppearanceRecord> _cache =
      <String, ChatAppearanceRecord>{};
  bool _cacheLoaded = false;
  Future<void>? _warmingCache;

  Future<ChatAppearanceRecord?> load(String chatKey) async {
    final normalizedKey = chatKey.trim();
    if (normalizedKey.isEmpty) {
      return null;
    }

    final cached = _cache[normalizedKey];
    if (cached != null) {
      return cached;
    }
    if (_cacheLoaded) {
      return null;
    }

    final database = await _openDatabase();
    await _ensureTableExists(database);
    List<Map<String, Object?>> rows;
    try {
      rows = await database.query(
        _tableName,
        where: 'chat_key = ?',
        whereArgs: <Object?>[normalizedKey],
        limit: 1,
      );
    } on sqflite.DatabaseException catch (error) {
      if (!_isMissingTableError(error)) {
        rethrow;
      }
      await _ensureTableExists(database);
      rows = await database.query(
        _tableName,
        where: 'chat_key = ?',
        whereArgs: <Object?>[normalizedKey],
        limit: 1,
      );
    }
    if (rows.isEmpty) {
      return null;
    }

    final row = rows.first;
    final record = ChatAppearanceRecord(
      chatKey: normalizedKey,
      myBubbleColorValue: _asInt(row['my_bubble_color']) ?? 0,
      otherBubbleColorValue: _asInt(row['other_bubble_color']) ?? 0,
      messageTextColorValue: _asInt(row['message_text_color']) ?? 0,
      messageFontFamily: (row['message_font_family'] ?? '').toString().trim(),
      backgroundImageUrl: _asTrimmedString(row['background_image_url']),
    );
    _cache[normalizedKey] = record;
    return record;
  }

  Future<void> warmCache() async {
    if (_cacheLoaded) {
      return;
    }
    if (_warmingCache != null) {
      return _warmingCache!;
    }

    _warmingCache = _loadAllIntoCache();
    try {
      await _warmingCache!;
    } finally {
      _warmingCache = null;
    }
  }

  Future<void> save(ChatAppearanceRecord record) async {
    final normalizedKey = record.chatKey.trim();
    if (normalizedKey.isEmpty) {
      return;
    }

    final database = await _openDatabase();
    await _ensureTableExists(database);
    try {
      await database.insert(_tableName, <String, Object?>{
        'chat_key': normalizedKey,
        'my_bubble_color': record.myBubbleColorValue,
        'other_bubble_color': record.otherBubbleColorValue,
        'message_text_color': record.messageTextColorValue,
        'message_font_family': record.messageFontFamily,
        'background_image_url': record.backgroundImageUrl,
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } on sqflite.DatabaseException catch (error) {
      if (!_isMissingTableError(error)) {
        rethrow;
      }
      await _ensureTableExists(database);
      await database.insert(_tableName, <String, Object?>{
        'chat_key': normalizedKey,
        'my_bubble_color': record.myBubbleColorValue,
        'other_bubble_color': record.otherBubbleColorValue,
        'message_text_color': record.messageTextColorValue,
        'message_font_family': record.messageFontFamily,
        'background_image_url': record.backgroundImageUrl,
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    _cache[normalizedKey] = record;
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
          await database.execute(_createTableIfNotExistsSql);
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
          await database.execute(_createTableIfNotExistsSql);
        },
      ),
    );
  }

  Future<void> _loadAllIntoCache() async {
    final database = await _openDatabase();
    await _ensureTableExists(database);
    List<Map<String, Object?>> rows;
    try {
      rows = await database.query(_tableName);
    } on sqflite.DatabaseException catch (error) {
      if (!_isMissingTableError(error)) {
        rethrow;
      }
      await _ensureTableExists(database);
      rows = await database.query(_tableName);
    }
    final nextCache = <String, ChatAppearanceRecord>{};
    for (final row in rows) {
      final rawChatKey = row['chat_key'];
      final chatKey = (rawChatKey ?? '').toString().trim();
      if (chatKey.isEmpty) {
        continue;
      }
      nextCache[chatKey] = ChatAppearanceRecord(
        chatKey: chatKey,
        myBubbleColorValue: _asInt(row['my_bubble_color']) ?? 0,
        otherBubbleColorValue: _asInt(row['other_bubble_color']) ?? 0,
        messageTextColorValue: _asInt(row['message_text_color']) ?? 0,
        messageFontFamily: (row['message_font_family'] ?? '').toString().trim(),
        backgroundImageUrl: _asTrimmedString(row['background_image_url']),
      );
    }
    _cache
      ..clear()
      ..addAll(nextCache);
    _cacheLoaded = true;
  }

  bool get _useFfiDatabase {
    if (kIsWeb) {
      return false;
    }
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  static const String _createTableSql =
      '''
CREATE TABLE $_tableName (
  chat_key TEXT PRIMARY KEY,
  my_bubble_color INTEGER NOT NULL,
  other_bubble_color INTEGER NOT NULL,
  message_text_color INTEGER NOT NULL,
  message_font_family TEXT NOT NULL,
  background_image_url TEXT,
  updated_at_ms INTEGER NOT NULL
)
''';

  static const String _createTableIfNotExistsSql =
      '''
CREATE TABLE IF NOT EXISTS $_tableName (
  chat_key TEXT PRIMARY KEY,
  my_bubble_color INTEGER NOT NULL,
  other_bubble_color INTEGER NOT NULL,
  message_text_color INTEGER NOT NULL,
  message_font_family TEXT NOT NULL,
  background_image_url TEXT,
  updated_at_ms INTEGER NOT NULL
)
''';

  Future<void> _ensureTableExists(Database database) {
    return database.execute(_createTableIfNotExistsSql);
  }

  bool _isMissingTableError(Object error) {
    return error.toString().contains('no such table: $_tableName');
  }

  int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse('$value');
  }

  String? _asTrimmedString(Object? value) {
    final raw = (value ?? '').toString().trim();
    return raw.isEmpty ? null : raw;
  }
}
