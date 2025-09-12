import 'package:flutter_test/flutter_test.dart';
import 'package:gun_dart/src/storage/sqlite_storage.dart';
import 'package:gun_dart/src/data/metadata_manager.dart';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  // Initialize sqflite for testing
  setUpAll(() {
    // Initialize FFI for testing on desktop platforms
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('SQLiteStorage Tests', () {
    late SQLiteStorage storage;
    final testDbName = 'test_gun_dart_${DateTime.now().millisecondsSinceEpoch}.db';

    Future<void> _deleteDbFiles(String dbPath) async {
      try {
        final mainFile = File(dbPath);
        final walFile = File('${dbPath}-wal');
        final shmFile = File('${dbPath}-shm');
        if (await mainFile.exists()) {
          await mainFile.delete();
        }
        if (await walFile.exists()) {
          await walFile.delete();
        }
        if (await shmFile.exists()) {
          await shmFile.delete();
        }
      } catch (_) {
        // Ignore cleanup errors
      }
    }

    setUp(() async {
      storage = SQLiteStorage(testDbName);
      await storage.initialize();
    });

    tearDown(() async {
      await storage.close();
      // Clean up test database file
      try {
        final dbPath = await storage.databasePath;
        await _deleteDbFiles(dbPath);
      } catch (e) {
        // Ignore cleanup errors
      }
    });

    tearDownAll(() async {
      // Sweep and remove any leftover test databases created by this suite
      try {
        final baseDir = Directory('.dart_tool/sqflite_common_ffi/databases');
        if (await baseDir.exists()) {
          await for (final entity in baseDir.list(recursive: false, followLinks: false)) {
            if (entity is File) {
              final name = entity.uri.pathSegments.isNotEmpty ? entity.uri.pathSegments.last : '';
              if (name.startsWith('test_gun_dart_') || name.startsWith('custom_test_')) {
                try { await entity.delete(); } catch (_) {}
              }
            }
          }
        }
      } catch (_) {
        // Ignore sweep errors
      }
    });

    group('Basic CRUD Operations', () {
      test('should initialize storage successfully', () async {
        final newStorage = SQLiteStorage('init_test.db');
        await newStorage.initialize();
        
        expect(newStorage, isNotNull);
        
        // Should be idempotent
        await newStorage.initialize();
        
        await newStorage.close();
      });

      test('should store and retrieve simple data', () async {
        final data = {'name': 'Alice', 'age': 30};
        await storage.put('user:alice', data);

        final retrieved = await storage.get('user:alice');
        expect(retrieved, isNotNull);
        expect(retrieved!['name'], equals('Alice'));
        expect(retrieved['age'], equals(30));
        
        // Should have metadata
        expect(retrieved['_'], isA<Map<String, dynamic>>());
        final metadata = retrieved['_'] as Map<String, dynamic>;
        expect(metadata['#'], isNotNull);
        expect(metadata['>'], isA<Map<String, dynamic>>());
      });

      test('should store and retrieve complex nested data', () async {
        final data = {
          'user': {
            'profile': {
              'name': 'Bob',
              'contact': {
                'email': 'bob@example.com',
                'phone': '123-456-7890'
              }
            },
            'preferences': {
              'theme': 'dark',
              'notifications': true
            }
          },
          'tags': ['developer', 'flutter', 'dart']
        };

        await storage.put('complex:data', data);
        final retrieved = await storage.get('complex:data');

        expect(retrieved, isNotNull);
        expect(retrieved!['user']['profile']['name'], equals('Bob'));
        expect(retrieved['user']['profile']['contact']['email'], equals('bob@example.com'));
        expect(retrieved['tags'], equals(['developer', 'flutter', 'dart']));
        expect(retrieved['user']['preferences']['theme'], equals('dark'));
      });

      test('should return null for non-existent keys', () async {
        final result = await storage.get('nonexistent:key');
        expect(result, isNull);
      });

      test('should check if keys exist', () async {
        expect(await storage.exists('test:key'), isFalse);

        await storage.put('test:key', {'value': 'test'});
        expect(await storage.exists('test:key'), isTrue);

        await storage.delete('test:key');
        expect(await storage.exists('test:key'), isFalse);
      });

      test('should delete data correctly', () async {
        await storage.put('delete:me', {'data': 'to_delete'});
        expect(await storage.exists('delete:me'), isTrue);

        await storage.delete('delete:me');
        expect(await storage.exists('delete:me'), isFalse);
        expect(await storage.get('delete:me'), isNull);
      });

      test('should clear all data', () async {
        await storage.put('key1', {'data': 'value1'});
        await storage.put('key2', {'data': 'value2'});
        await storage.put('key3', {'data': 'value3'});

        final keysBefore = await storage.keys();
        expect(keysBefore.length, equals(3));

        await storage.clear();

        final keysAfter = await storage.keys();
        expect(keysAfter.length, equals(0));
      });

      test('should list all keys', () async {
        await storage.put('user:alice', {'name': 'Alice'});
        await storage.put('user:bob', {'name': 'Bob'});
        await storage.put('post:1', {'title': 'Hello World'});

        final allKeys = await storage.keys();
        expect(allKeys.length, equals(3));
        expect(allKeys, contains('user:alice'));
        expect(allKeys, contains('user:bob'));
        expect(allKeys, contains('post:1'));
        expect(allKeys, isA<List<String>>());
      });

      test('should filter keys by pattern', () async {
        await storage.put('user:alice', {'name': 'Alice'});
        await storage.put('user:bob', {'name': 'Bob'});
        await storage.put('post:1', {'title': 'Hello'});
        await storage.put('post:2', {'title': 'World'});

        final userKeys = await storage.keys('user');
        expect(userKeys.length, equals(2));
        expect(userKeys, contains('user:alice'));
        expect(userKeys, contains('user:bob'));

        final postKeys = await storage.keys('post');
        expect(postKeys.length, equals(2));
        expect(postKeys, contains('post:1'));
        expect(postKeys, contains('post:2'));

        final aliceKeys = await storage.keys('alice');
        expect(aliceKeys.length, equals(1));
        expect(aliceKeys, contains('user:alice'));
      });

      test('should close storage properly', () async {
        await storage.put('test:key', {'data': 'test'});
        expect(await storage.get('test:key'), isNotNull);

        await storage.close();

        // Should not be able to perform operations after close
        expect(() async => await storage.get('test:key'), 
               throwsA(isA<StateError>()));
      });
    });

    group('Metadata and CRDT Operations', () {
      test('should add metadata to raw data', () async {
        final rawData = {'name': 'Charlie', 'age': 25};
        await storage.put('user:charlie', rawData);

        final retrieved = await storage.get('user:charlie');
        expect(retrieved, isNotNull);
        expect(retrieved!['name'], equals('Charlie'));
        expect(retrieved['age'], equals(25));
        
        // Should have Gun metadata
        expect(retrieved['_'], isA<Map<String, dynamic>>());
        final metadata = retrieved['_'] as Map<String, dynamic>;
        expect(metadata['#'], isNotNull);
        expect(metadata['>'], isA<Map<String, dynamic>>());
        
        // Timestamp metadata for each field
        final timestamps = metadata['>'] as Map<String, dynamic>;
        expect(timestamps['name'], isA<num>());
        expect(timestamps['age'], isA<num>());
      });

      test('should preserve existing metadata when updating', () async {
        // First put with raw data
        await storage.put('user:dave', {'name': 'Dave'});
        final first = await storage.get('user:dave');
        final firstMetadata = first!['_'] as Map<String, dynamic>;
        final firstTimestamps = firstMetadata['>'] as Map<String, dynamic>;
        final nameTimestamp = firstTimestamps['name'];

        // Wait a bit to ensure different timestamp
        await Future.delayed(Duration(milliseconds: 5));

        // Update with additional data
        await storage.put('user:dave', {'name': 'Dave', 'age': 35});
        final updated = await storage.get('user:dave');
        
        expect(updated!['name'], equals('Dave'));
        expect(updated['age'], equals(35));
        
        final updatedMetadata = updated['_'] as Map<String, dynamic>;
        final updatedTimestamps = updatedMetadata['>'] as Map<String, dynamic>;
        
        // Name timestamp should be preserved (not updated since value didn't change)
        expect(updatedTimestamps['name'], equals(nameTimestamp));
        // Age should have a new timestamp
        expect(updatedTimestamps['age'], isA<num>());
      });

      test('should merge nodes with valid metadata', () async {
        // Create first node with metadata
        final nodeId = MetadataManager.generateNodeId('merge:test');
        final firstData = MetadataManager.addMetadata(
          nodeId: nodeId,
          data: {'name': 'Eve', 'score': 100},
        );
        await storage.put('merge:test', firstData);

        // Wait to ensure different timestamps
        await Future.delayed(Duration(milliseconds: 5));

        // Update with newer data (should win for conflicting fields)
        final secondData = MetadataManager.addMetadata(
          nodeId: nodeId,
          data: {'score': 150, 'level': 'advanced'},
        );
        await storage.put('merge:test', secondData);

        final merged = await storage.get('merge:test');
        expect(merged!['name'], equals('Eve'));  // Preserved from first
        expect(merged['score'], equals(150));    // Updated to newer value
        expect(merged['level'], equals('advanced')); // New field added
      });

      test('should handle concurrent updates correctly', () async {
        final key = 'concurrent:test';
        final baseData = {'counter': 0};
        await storage.put(key, baseData);

        // Simulate concurrent updates
        final futures = <Future>[];
        for (int i = 1; i <= 5; i++) {
          futures.add(() async {
            final current = await storage.get(key);
            final updated = Map<String, dynamic>.from(current!);
            updated['counter'] = i;
            updated['update_$i'] = 'value_$i';
            await storage.put(key, updated);
          }());
        }

        await Future.wait(futures);

        final final_ = await storage.get(key);
        expect(final_, isNotNull);
        expect(final_!['counter'], isA<int>());
        expect(final_['counter'], greaterThanOrEqualTo(1));
        expect(final_['counter'], lessThanOrEqualTo(5));
        
        // Should have some update fields
        final keys = final_.keys.where((k) => k.startsWith('update_')).toList();
        expect(keys.length, greaterThan(0));
      });
    });

    group('SQLite-Specific Features', () {
      test('should get all entries with pagination', () async {
        // Add test data
        for (int i = 1; i <= 10; i++) {
          await storage.put('item:$i', {'value': i, 'name': 'Item $i'});
        }

        // Get all entries
        final allEntries = await storage.getAllEntries();
        expect(allEntries.length, equals(10));

        // Test pagination
        final firstPage = await storage.getAllEntries(limit: 3, offset: 0);
        expect(firstPage.length, equals(3));

        final secondPage = await storage.getAllEntries(limit: 3, offset: 3);
        expect(secondPage.length, equals(3));

        // Each entry should have key, data, created_at, updated_at
        final entry = firstPage.first;
        expect(entry.keys, containsAll(['key', 'data', 'created_at', 'updated_at']));
        expect(entry['key'], isA<String>());
        expect(entry['data'], isA<Map<String, dynamic>>());
        expect(entry['created_at'], isA<int>());
        expect(entry['updated_at'], isA<int>());
      });

      test('should get entries modified since timestamp', () async {
        // Add initial data
        await storage.put('old:item', {'value': 'old'});
        final timestamp = DateTime.now().millisecondsSinceEpoch;

        // Wait a bit
        await Future.delayed(Duration(milliseconds: 10));

        // Add new data
        await storage.put('new:item1', {'value': 'new1'});
        await storage.put('new:item2', {'value': 'new2'});

        // Get entries modified since timestamp
        final modified = await storage.getModifiedSince(timestamp);
        expect(modified.length, equals(2));

        final keys = modified.map((e) => e['key'] as String).toList();
        expect(keys, contains('new:item1'));
        expect(keys, contains('new:item2'));
        expect(keys, isNot(contains('old:item')));
      });

      test('should provide database statistics', () async {
        // Add some data
        for (int i = 1; i <= 5; i++) {
          await storage.put('stats:$i', {'data': 'value$i'});
        }

        final stats = await storage.getStats();
        expect(stats, isA<Map<String, dynamic>>());
        expect(stats['entryCount'], equals(5));
        expect(stats['databaseSize'], isA<int>());
        expect(stats['pageSize'], isA<int>());
        expect(stats['pageCount'], isA<int>());
        expect(stats['databaseSize'], greaterThan(0));
      });

      test('should optimize database', () async {
        // Add and delete some data to create fragmentation
        for (int i = 1; i <= 100; i++) {
          await storage.put('temp:$i', {'data': 'value$i'});
        }
        for (int i = 1; i <= 50; i++) {
          await storage.delete('temp:$i');
        }

        // Get stats before optimization
        // Get stats before optimization (currently unused)
        // final statsBefore = await storage.getStats();
        
        // Optimize
        await storage.optimize();
        
        // Get stats after optimization
        final statsAfter = await storage.getStats();
        
        expect(statsAfter['entryCount'], equals(50));
        expect(statsAfter, isA<Map<String, dynamic>>());
        expect(statsAfter['databaseSize'], isA<int>());
      });

      test('should provide database path', () async {
        final path = await storage.databasePath;
        expect(path, isA<String>());
        expect(path, contains(testDbName));
        expect(path.endsWith('.db'), isTrue);
      });

      test('should handle custom database names', () async {
        final customName = 'custom_test_${DateTime.now().millisecondsSinceEpoch}.db';
        final customStorage = SQLiteStorage(customName);
        
        try {
          await customStorage.initialize();
          final path = await customStorage.databasePath;
          expect(path, contains(customName));
          
          await customStorage.put('test', {'data': 'custom'});
          final retrieved = await customStorage.get('test');
          expect(retrieved!['data'], equals('custom'));
        } finally {
          await customStorage.close();
          // Delete custom database files
          try {
            final customPath = await customStorage.databasePath;
            await _deleteDbFiles(customPath);
          } catch (_) {}
        }
      });
    });

    group('Error Handling and Edge Cases', () {
      test('should throw error when not initialized', () async {
        final uninitStorage = SQLiteStorage('uninit_test.db');
        
        expect(() async => await uninitStorage.put('key', {'data': 'value'}),
               throwsA(isA<StateError>()));
        expect(() async => await uninitStorage.get('key'),
               throwsA(isA<StateError>()));
        expect(() async => await uninitStorage.exists('key'),
               throwsA(isA<StateError>()));
        expect(() async => await uninitStorage.keys(),
               throwsA(isA<StateError>()));
      });

      test('should handle empty and null values gracefully', () async {
        // Empty map
        await storage.put('empty', {});
        final empty = await storage.get('empty');
        expect(empty, isNotNull);
        expect(empty!.keys.length, equals(1)); // Only metadata
        expect(empty['_'], isNotNull);

        // Keys with special characters
        await storage.put('key:with/special\\chars', {'value': 'test'});
        final special = await storage.get('key:with/special\\chars');
        expect(special!['value'], equals('test'));

        // Very long key
        final longKey = 'key:' + 'x' * 1000;
        await storage.put(longKey, {'data': 'long_key_test'});
        final longResult = await storage.get(longKey);
        expect(longResult!['data'], equals('long_key_test'));
      });

      test('should handle large data objects', () async {
        // Create large data object
        final largeData = <String, dynamic>{};
        for (int i = 0; i < 1000; i++) {
          largeData['field_$i'] = 'This is a test value for field $i with some extra text to make it larger';
        }

        await storage.put('large:data', largeData);
        final retrieved = await storage.get('large:data');
        
        expect(retrieved, isNotNull);
        expect(retrieved!.keys.length, equals(1001)); // 1000 fields + metadata
        expect(retrieved['field_0'], equals('This is a test value for field 0 with some extra text to make it larger'));
        expect(retrieved['field_999'], equals('This is a test value for field 999 with some extra text to make it larger'));
      });

      test('should handle Unicode and special characters in data', () async {
        final unicodeData = {
          'emoji': '🚀🌟💫',
          'chinese': '你好世界',
          'arabic': 'مرحبا بالعالم',
          'russian': 'Привет мир',
          'japanese': 'こんにちは世界',
          'special': 'Special chars: !@#\$%^&*()_+-=[]{}|;:,.<>?'
        };

        await storage.put('unicode:test', unicodeData);
        final retrieved = await storage.get('unicode:test');

        expect(retrieved!['emoji'], equals('🚀🌟💫'));
        expect(retrieved['chinese'], equals('你好世界'));
        expect(retrieved['arabic'], equals('مرحبا بالعالم'));
        expect(retrieved['russian'], equals('Привет мир'));
        expect(retrieved['japanese'], equals('こんにちは世界'));
        expect(retrieved['special'], equals('Special chars: !@#\$%^&*()_+-=[]{}|;:,.<>?'));
      });

      test('should handle data type preservation', () async {
        final mixedData = {
          'string': 'hello',
          'integer': 42,
          'double': 3.14159,
          'boolean_true': true,
          'boolean_false': false,
          'null_value': null,
          'list': [1, 2, 'three', true, null],
          'nested_map': {
            'inner_string': 'inner_value',
            'inner_number': 123,
            'inner_list': ['a', 'b', 'c']
          }
        };

        await storage.put('types:test', mixedData);
        final retrieved = await storage.get('types:test');

        expect(retrieved!['string'], equals('hello'));
        expect(retrieved['integer'], equals(42));
        expect(retrieved['double'], equals(3.14159));
        expect(retrieved['boolean_true'], equals(true));
        expect(retrieved['boolean_false'], equals(false));
        expect(retrieved['null_value'], isNull);
        expect(retrieved['list'], equals([1, 2, 'three', true, null]));
        expect(retrieved['nested_map']['inner_string'], equals('inner_value'));
        expect(retrieved['nested_map']['inner_number'], equals(123));
        expect(retrieved['nested_map']['inner_list'], equals(['a', 'b', 'c']));
      });

      test('should handle database reopening', () async {
        // Store some data
        await storage.put('persist:test', {'value': 'persistent'});
        // Database path extracted but not used in this test
        // final dbPath = await storage.databasePath;
        
        // Close storage
        await storage.close();
        
        // Create new storage instance with same database
        final newStorage = SQLiteStorage(testDbName);
        await newStorage.initialize();
        
        try {
          // Should be able to read previously stored data
          final retrieved = await newStorage.get('persist:test');
          expect(retrieved!['value'], equals('persistent'));
        } finally {
          await newStorage.close();
        }
      });
    });

    group('Performance and Scalability', () {
      test('should handle batch operations efficiently', () async {
        final stopwatch = Stopwatch()..start();
        
        // Insert 1000 records
        for (int i = 0; i < 1000; i++) {
          await storage.put('batch:$i', {
            'id': i,
            'name': 'Item $i',
            'description': 'This is item number $i in the batch test',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
        }
        
        stopwatch.stop();
        final insertTime = stopwatch.elapsedMilliseconds;
        
        // Should complete in reasonable time (adjust threshold as needed)
        expect(insertTime, lessThan(10000)); // 10 seconds max
        
        // Verify all data was inserted
        final allKeys = await storage.keys('batch:');
        expect(allKeys.length, equals(1000));
        
        // Test random access
        stopwatch.reset();
        stopwatch.start();
        
        for (int i = 0; i < 100; i++) {
          final randomIndex = i * 10; // Every 10th item
          final data = await storage.get('batch:$randomIndex');
          expect(data!['id'], equals(randomIndex));
        }
        
        stopwatch.stop();
        final readTime = stopwatch.elapsedMilliseconds;
        expect(readTime, lessThan(1000)); // 1 second max for 100 reads
      });

      test('should handle key pattern matching efficiently', () async {
        // Insert data with different prefixes
        final prefixes = ['user', 'post', 'comment', 'like', 'share'];
        for (final prefix in prefixes) {
          for (int i = 0; i < 100; i++) {
            await storage.put('$prefix:$i', {'type': prefix, 'id': i});
          }
        }
        
        final stopwatch = Stopwatch()..start();
        
        // Test pattern matching for each prefix
        for (final prefix in prefixes) {
          final keys = await storage.keys(prefix);
          expect(keys.length, equals(100));
          expect(keys.every((k) => k.startsWith('$prefix:')), isTrue);
        }
        
        stopwatch.stop();
        expect(stopwatch.elapsedMilliseconds, lessThan(1000));
      });

      test('should handle pagination efficiently with large datasets', () async {
        // Insert 500 items
        for (int i = 0; i < 500; i++) {
          await storage.put('page:${i.toString().padLeft(3, '0')}', {
            'index': i,
            'data': 'Page item $i'
          });
        }

        final stopwatch = Stopwatch()..start();
        
        // Test pagination
        const pageSize = 20;
        final pages = <List<Map<String, dynamic>>>[];
        
        for (int page = 0; page < 5; page++) {
          final entries = await storage.getAllEntries(
            limit: pageSize,
            offset: page * pageSize,
            orderBy: 'key ASC'
          );
          pages.add(entries);
          expect(entries.length, equals(pageSize));
        }
        
        stopwatch.stop();
        expect(stopwatch.elapsedMilliseconds, lessThan(1000));
        
        // Verify no duplicates across pages
        final allKeys = pages.expand((p) => p.map((e) => e['key'] as String)).toSet();
        expect(allKeys.length, equals(100)); // 5 pages * 20 items
      });

      test('should maintain consistent performance under load', () async {
        final times = <int>[];
        
        // Perform multiple rounds of operations
        for (int round = 0; round < 10; round++) {
          final stopwatch = Stopwatch()..start();
          
          // Write operations
          for (int i = 0; i < 50; i++) {
            await storage.put('load:${round}_$i', {
              'round': round,
              'item': i,
              'data': 'Load test data for round $round item $i'
            });
          }
          
          // Read operations
          for (int i = 0; i < 20; i++) {
            await storage.get('load:${round}_$i');
          }
          
          stopwatch.stop();
          times.add(stopwatch.elapsedMilliseconds);
        }
        
        // Performance should be relatively consistent
        final avgTime = times.reduce((a, b) => a + b) / times.length;
        
        // Use trimmed ratio to avoid outliers (drop fastest/slowest 10%)
        final sorted = List<int>.from(times)..sort();
        final start = (sorted.length * 0.1).floor();
        final end = (sorted.length * 0.9).ceil();
        final trimmed = sorted.sublist(start, end);
        final trimmedMax = trimmed.reduce((a, b) => a > b ? a : b);
        final trimmedMin = trimmed.reduce((a, b) => a < b ? a : b);
        
        // Trimmed max should not exceed 3.5x trimmed min to allow occasional jitter
        expect(trimmedMax / trimmedMin, lessThanOrEqualTo(3.5));
        expect(avgTime, lessThan(2000)); // 2 seconds average
      });
    });
  });
}
