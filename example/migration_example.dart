import 'dart:io';
import 'dart:convert';
import '../lib/gun_dart.dart';
import '../lib/src/utils/gunjs_migration.dart';

/// Gun.js migration utilities example
/// 
/// Demonstrates how to import/export data between Gun.js and gun_dart
Future<void> main() async {
  print('=== Gun.js Migration Utilities Example ===\n');
  
  // Create gun_dart instance
  final gun = Gun(GunOptions(storage: MemoryStorage()));
  
  print('1. Creating sample data in gun_dart...\n');
  await createSampleData(gun);
  
  print('2. Exporting gun_dart data to Gun.js format...\n');
  await demonstrateExport(gun);
  
  print('3. Creating backup...\n');
  await demonstrateBackup(gun);
  
  print('4. Simulating Gun.js import...\n');
  await demonstrateImport(gun);
  
  print('5. Data format conversion...\n');
  await demonstrateFormatConversion();
  
  // Clean up
  await gun.close();
  
  print('\n=== Example completed ===');
}

Future<void> createSampleData(Gun gun) async {
  // Create some user data
  final user = gun.user();
  await user.create('alice', 'password123');
  
  await user.getUserPath('profile').put({
    'name': 'Alice Smith',
    'email': 'alice@example.com',
    'age': 30,
    'bio': 'Software developer'
  });
  
  await user.getUserPath('todos').put({
    'task1': 'Learn Gun.js',
    'task2': 'Build Flutter app',
    'task3': 'Sync with gun_dart'
  });
  
  // Create some public data
  await gun.get('posts/post1').put({
    'title': 'Hello from gun_dart!',
    'content': 'This is a test post from gun_dart.',
    'author': 'alice',
    'timestamp': DateTime.now().millisecondsSinceEpoch,
    'tags': ['gunjs', 'dart', 'flutter']
  });
  
  await gun.get('comments/comment1').put({
    'postId': 'posts/post1',
    'text': 'Great post!',
    'author': 'bob',
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  });
  
  print('✓ Created sample user data, posts, and comments');
}

Future<void> demonstrateExport(Gun gun) async {
  try {
    // Export specific nodes
    final result = await GunJSMigration.exportToGunJS(
      gun,
      '/tmp/gun_dart_export.json',
      nodeIds: ['posts/post1', 'comments/comment1'],
      includeMetadata: true,
      prettify: true,
    );
    
    if (result.success) {
      print('✓ Export successful!');
      print('  - Exported ${result.exportedCount} nodes');
      print('  - Output file: ${result.outputFile}');
      print('  - Duration: ${result.duration.inMilliseconds}ms');
      
      // Show a sample of the exported data
      final file = File(result.outputFile!);
      final content = await file.readAsString();
      final preview = content.length > 500 
          ? '${content.substring(0, 500)}...'
          : content;
      print('\nExported data preview:');
      print(preview);
    } else {
      print('✗ Export failed: ${result.errors.join(', ')}');
    }
  } catch (e) {
    print('✗ Export error: $e');
  }
}

Future<void> demonstrateBackup(Gun gun) async {
  try {
    final result = await GunJSMigration.createBackup(
      gun,
      '/tmp/backups',
      description: 'Example backup with user and post data',
    );
    
    if (result.success) {
      print('✓ Backup successful!');
      print('  - Backup file: ${result.outputFile}');
      print('  - Description: ${result.description}');
      print('  - Duration: ${result.duration.inMilliseconds}ms');
    } else {
      print('✗ Backup failed: ${result.errors.join(', ')}');
    }
  } catch (e) {
    print('✗ Backup error: $e');
  }
}

Future<void> demonstrateImport(Gun gun) async {
  try {
    // Create a mock Gun.js export file
    final mockGunJSData = {
      'items/item1': {
        'name': 'Item from Gun.js',
        'description': 'This item was exported from Gun.js',
        'price': 29.99,
        'category': 'electronics',
        '_': {
          '#': 'items/item1',
          '>': {
            'name': DateTime.now().millisecondsSinceEpoch - 1000,
            'description': DateTime.now().millisecondsSinceEpoch - 1000,
            'price': DateTime.now().millisecondsSinceEpoch - 500,
            'category': DateTime.now().millisecondsSinceEpoch - 800,
          },
          'machine': 1,
          'machineId': 'GUNJS123'
        }
      },
      'users/bob': {
        'alias': 'bob',
        'pub': 'mock_public_key_bob',
        'epub': 'mock_encrypted_pub_bob',
        'auth': 'mock_encrypted_auth_data',
        '_': {
          '#': 'users/bob',
          '>': {
            'alias': DateTime.now().millisecondsSinceEpoch,
            'pub': DateTime.now().millisecondsSinceEpoch,
            'epub': DateTime.now().millisecondsSinceEpoch,
            'auth': DateTime.now().millisecondsSinceEpoch,
          },
          'machine': 2,
          'machineId': 'GUNJS456'
        }
      }
    };
    
    // Write mock data to file
    final mockFile = File('/tmp/mock_gunjs_export.json');
    await mockFile.writeAsString(
const JsonEncoder.withIndent('  ').convert(mockGunJSData)
    );
    
    // Import the mock Gun.js data
    final result = await GunJSMigration.importFromGunJS(
      gun,
      '/tmp/mock_gunjs_export.json',
      validateData: true,
      preserveTimestamps: true,
      overwriteExisting: false,
    );
    
    if (result.success) {
      print('✓ Import successful!');
      print('  - Imported ${result.importedCount} nodes');
      print('  - Merged ${result.mergedCount} nodes');
      print('  - Skipped ${result.skippedCount} nodes');
      print('  - Duration: ${result.duration.inMilliseconds}ms');
      
      // Verify imported data
      final item = await gun.get('items/item1').once();
      if (item != null) {
        print('\\nVerified imported item:');
        print('  - Name: ${item['name']}');
        print('  - Price: ${item['price']}');
        print('  - Has metadata: ${item.containsKey('_')}');
      }
    } else {
      print('✗ Import failed: ${result.errors.join(', ')}');
    }
  } catch (e) {
    print('✗ Import error: $e');
  }
}

Future<void> demonstrateFormatConversion() async {
  // Demonstrate data format conversion
  final dartData = {
    'message': 'Hello World',
    'timestamp': DateTime.now().millisecondsSinceEpoch,
    'nested': {
      'value': 42,
      'active': true
    }
  };
  
  print('Original gun_dart data:');
  print(const JsonEncoder.withIndent('  ').convert(dartData));
  
  // Convert to Gun.js format
  final gunJSFormat = GunJSMigration.convertDataFormat(dartData, toGunJS: true);
  print('\\nConverted to Gun.js format:');
  print(const JsonEncoder.withIndent('  ').convert(gunJSFormat));
  
  // Convert back to gun_dart format
  final backToDart = GunJSMigration.convertDataFormat(gunJSFormat, toGunJS: false);
  print('\\nConverted back to gun_dart format:');
  print(const JsonEncoder.withIndent('  ').convert(backToDart));
  
  // Compare formats
  final mockGunJSData = {
    'message': 'Hello World',
    'timestamp': DateTime.now().millisecondsSinceEpoch,
    'nested': {
      'value': 42,
      'active': true
    },
    '_': {
      '#': 'test/node',
      '>': {'message': 1234567890},
      'machine': 1,
      'machineId': 'TEST123'
    }
  };
  
  final comparison = GunJSMigration.compareFormats(dartData, mockGunJSData);
  
  print('\\nFormat comparison:');
  print('  - Has differences: ${comparison.hasDifferences}');
  if (comparison.hasDifferences) {
    print('  - Only in gun_dart: ${comparison.onlyInDart}');
    print('  - Only in Gun.js: ${comparison.onlyInGunJS}');
    print('  - In both: ${comparison.inBoth}');
  }
}

/// Additional utility functions for migration
Future<void> demonstrateValidation() async {
  print('\\n6. Validating Gun.js formats...');
  
  // Test valid Gun.js format
  final validGunJSFile = '/tmp/valid_gunjs.json';
  final validData = {
    'test/node': {
      'value': 'test',
      '_': {
        '#': 'test/node',
        '>': {'value': 1234567890}
      }
    }
  };
  
  await File(validGunJSFile).writeAsString(jsonEncode(validData));
  
  final isValid = GunJSMigration.validateGunJSFormat(validGunJSFile);
  print('✓ Gun.js format validation: ${isValid ? 'VALID' : 'INVALID'}');
  
  // Test invalid format
  final invalidGunJSFile = '/tmp/invalid_gunjs.json';
  final invalidData = {
    'test/node': 'just a string, not an object'
  };
  
  await File(invalidGunJSFile).writeAsString(jsonEncode(invalidData));
  
  final isInvalid = GunJSMigration.validateGunJSFormat(invalidGunJSFile);
  print('✓ Invalid format detected: ${!isInvalid ? 'CORRECTLY REJECTED' : 'INCORRECTLY ACCEPTED'}');
}
