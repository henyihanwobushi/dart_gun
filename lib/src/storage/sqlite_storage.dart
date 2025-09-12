import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'storage_adapter.dart';
import '../data/metadata_manager.dart';
 // For FFI database factory

/// SQLite storage adapter for Gun Dart
/// Provides persistent storage using SQLite database
class SQLiteStorage implements StorageAdapter {
  Database? _db;
  final String _dbName;
  final String _tableName = 'gun_data';
  bool _initialized = false;

  /// Create SQLite storage with custom database name
  SQLiteStorage([this._dbName = 'dart_gun.db']);

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final databasesPath = await getDatabasesPath();
      final path = join(databasesPath, _dbName);

      _db = await openDatabase(
        path,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE $_tableName (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');

          // Create index for faster lookups
          await db.execute(
              'CREATE INDEX idx_updated_at ON $_tableName (updated_at)');
        },
      );

      _initialized = true;
    } catch (e) {
      throw StateError('Failed to initialize SQLite storage: $e');
    }
  }

  @override
  Future<void> put(String key, Map<String, dynamic> data) async {
    _ensureInitialized();

    // Get existing data for metadata merging
    final existing = await get(key);

    Map<String, dynamic> nodeData;
    if (MetadataManager.isValidNode(data)) {
      // Data already has valid metadata
      if (existing != null && MetadataManager.isValidNode(existing)) {
        // Merge with existing data using HAM conflict resolution
        nodeData = MetadataManager.mergeNodes(existing, data);
      } else {
        nodeData = data;
      }
    } else {
      // Add metadata to raw data
      final nodeId = MetadataManager.generateNodeId(key);
      nodeData = MetadataManager.addMetadata(
        nodeId: nodeId,
        data: data,
        existingMetadata:
            existing != null ? MetadataManager.extractMetadata(existing) : null,
      );
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final value = jsonEncode(nodeData);

    await _db!.insert(
      _tableName,
      {
        'key': key,
        'value': value,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<Map<String, dynamic>?> get(String key) async {
    _ensureInitialized();

    final result = await _db!.query(
      _tableName,
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );

    if (result.isEmpty) return null;

    final valueStr = result.first['value'] as String;
    return jsonDecode(valueStr) as Map<String, dynamic>;
  }

  @override
  Future<void> delete(String key) async {
    _ensureInitialized();

    await _db!.delete(
      _tableName,
      where: 'key = ?',
      whereArgs: [key],
    );
  }

  @override
  Future<bool> exists(String key) async {
    _ensureInitialized();

    final result = await _db!.query(
      _tableName,
      columns: ['key'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );

    return result.isNotEmpty;
  }

  @override
  Future<List<String>> keys([String? pattern]) async {
    _ensureInitialized();

    List<Map<String, Object?>> result;

    if (pattern != null) {
      // Use LIKE for pattern matching
      result = await _db!.query(
        _tableName,
        columns: ['key'],
        where: 'key LIKE ?',
        whereArgs: ['%$pattern%'],
        orderBy: 'key',
      );
    } else {
      result = await _db!.query(
        _tableName,
        columns: ['key'],
        orderBy: 'key',
      );
    }

    return result.map((row) => row['key'] as String).toList();
  }

  @override
  Future<void> clear() async {
    _ensureInitialized();
    await _db!.delete(_tableName);
  }

  @override
  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
    _initialized = false;
  }

  /// Get all entries with pagination
  Future<List<Map<String, dynamic>>> getAllEntries({
    int? limit,
    int? offset,
    String? orderBy,
  }) async {
    _ensureInitialized();

    final result = await _db!.query(
      _tableName,
      limit: limit,
      offset: offset,
      orderBy: orderBy ?? 'updated_at DESC',
    );

    return result.map((row) {
      return {
        'key': row['key'],
        'data': jsonDecode(row['value'] as String),
        'created_at': row['created_at'],
        'updated_at': row['updated_at'],
      };
    }).toList();
  }

  /// Get entries modified since a timestamp
  Future<List<Map<String, dynamic>>> getModifiedSince(int timestamp) async {
    _ensureInitialized();

    final result = await _db!.query(
      _tableName,
      where: 'updated_at > ?',
      whereArgs: [timestamp],
      orderBy: 'updated_at ASC',
    );

    return result.map((row) {
      return {
        'key': row['key'],
        'data': jsonDecode(row['value'] as String),
        'created_at': row['created_at'],
        'updated_at': row['updated_at'],
      };
    }).toList();
  }

  /// Get database statistics
  Future<Map<String, dynamic>> getStats() async {
    _ensureInitialized();

    final countResult =
        await _db!.rawQuery('SELECT COUNT(*) as count FROM $_tableName');
    final sizeResult = await _db!.rawQuery('PRAGMA page_size');
    final pageCountResult = await _db!.rawQuery('PRAGMA page_count');

    final count = Sqflite.firstIntValue(countResult) ?? 0;
    final pageSize = Sqflite.firstIntValue(sizeResult) ?? 0;
    final pageCount = Sqflite.firstIntValue(pageCountResult) ?? 0;

    return {
      'entryCount': count,
      'databaseSize': pageSize * pageCount,
      'pageSize': pageSize,
      'pageCount': pageCount,
    };
  }

  /// Optimize database (VACUUM)
  Future<void> optimize() async {
    _ensureInitialized();
    await _db!.execute('VACUUM');
  }

  void _ensureInitialized() {
    if (!_initialized || _db == null) {
      throw StateError(
          'SQLiteStorage not initialized. Call initialize() first.');
    }
  }

  /// Get the database path
  Future<String> get databasePath async {
    final databasesPath = await getDatabasesPath();
    return join(databasesPath, _dbName);
  }
}
