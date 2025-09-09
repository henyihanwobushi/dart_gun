import 'package:flutter_test/flutter_test.dart';
import 'package:gun_dart/src/data/metadata_manager.dart';

void main() {
  group('MetadataManager', () {
    test('should generate machine ID consistently', () {
      final id1 = MetadataManager.machineId;
      final id2 = MetadataManager.machineId;
      
      expect(id1, equals(id2));
      expect(id1.length, equals(8));
    });

    test('should increment machine state', () {
      final state1 = MetadataManager.nextMachineState;
      final state2 = MetadataManager.nextMachineState;
      
      expect(state2, equals(state1 + 1));
    });

    test('should create valid metadata for node', () {
      final data = {'name': 'John', 'age': 30};
      final nodeId = 'user123';
      
      final metadata = MetadataManager.createMetadata(
        nodeId: nodeId,
        data: data,
      );

      expect(metadata['#'], equals(nodeId));
      expect(metadata['>'], isA<Map<String, num>>());
      expect(metadata['machine'], isA<num>());
      expect(metadata['machineId'], isA<String>());
      
      final timestamps = metadata['>'] as Map<String, num>;
      expect(timestamps['name'], isA<num>());
      expect(timestamps['age'], isA<num>());
      expect(timestamps.containsKey('_'), isFalse); // Should not timestamp metadata field
    });

    test('should add metadata to data node', () {
      final data = {'name': 'John', 'age': 30};
      final nodeId = 'user123';
      
      final nodeWithMetadata = MetadataManager.addMetadata(
        nodeId: nodeId,
        data: data,
      );

      expect(nodeWithMetadata['name'], equals('John'));
      expect(nodeWithMetadata['age'], equals(30));
      expect(nodeWithMetadata['_'], isA<Map<String, dynamic>>());
      
      final metadata = nodeWithMetadata['_'] as Map<String, dynamic>;
      expect(metadata['#'], equals(nodeId));
      expect(metadata['>'], isA<Map<String, num>>());
    });

    test('should preserve existing timestamps when adding metadata', () {
      final data = {'name': 'John', 'age': 30};
      final nodeId = 'user123';
      final existingTimestamps = {'name': 1000, 'email': 2000};
      
      final nodeWithMetadata = MetadataManager.addMetadata(
        nodeId: nodeId,
        data: data,
        existingMetadata: {
          '#': nodeId,
          '>': existingTimestamps,
        },
      );

      final metadata = nodeWithMetadata['_'] as Map<String, dynamic>;
      final timestamps = metadata['>'] as Map<String, num>;
      
      expect(timestamps['name'], equals(1000)); // Preserved existing
      expect(timestamps['age'], isA<num>()); // New timestamp
      expect(timestamps['email'], equals(2000)); // Preserved even though not in new data
    });

    test('should extract metadata from node', () {
      final nodeWithMetadata = {
        'name': 'John',
        '_': {
          '#': 'user123',
          '>': {'name': 1000},
          'machine': 1,
          'machineId': 'abc123',
        }
      };
      
      final metadata = MetadataManager.extractMetadata(nodeWithMetadata);
      
      expect(metadata, isNotNull);
      expect(metadata!['#'], equals('user123'));
      expect(metadata['>'], equals({'name': 1000}));
    });

    test('should return null for node without metadata', () {
      final node = {'name': 'John', 'age': 30};
      
      final metadata = MetadataManager.extractMetadata(node);
      
      expect(metadata, isNull);
    });

    test('should get node ID from metadata', () {
      final node = {
        'name': 'John',
        '_': {
          '#': 'user123',
          '>': {'name': 1000},
        }
      };
      
      final nodeId = MetadataManager.getNodeId(node);
      
      expect(nodeId, equals('user123'));
    });

    test('should get timestamps from metadata', () {
      final node = {
        'name': 'John',
        '_': {
          '#': 'user123',
          '>': {'name': 1000, 'age': 2000},
        }
      };
      
      final timestamps = MetadataManager.getTimestamps(node);
      
      expect(timestamps, isNotNull);
      expect(timestamps!['name'], equals(1000));
      expect(timestamps['age'], equals(2000));
    });

    test('should validate valid node', () {
      final validNode = {
        'name': 'John',
        '_': {
          '#': 'user123',
          '>': {'name': 1000},
          'machine': 1,
          'machineId': 'abc123',
        }
      };
      
      expect(MetadataManager.isValidNode(validNode), isTrue);
    });

    test('should reject node without metadata', () {
      final invalidNode = {'name': 'John', 'age': 30};
      
      expect(MetadataManager.isValidNode(invalidNode), isFalse);
    });

    test('should reject node with invalid metadata structure', () {
      final invalidNode = {
        'name': 'John',
        '_': {
          // Missing required fields
          'machine': 1,
        }
      };
      
      expect(MetadataManager.isValidNode(invalidNode), isFalse);
    });

    test('should merge nodes using HAM timestamps', () {
      final currentNode = {
        'name': 'John',
        'age': 30,
        'email': 'old@example.com',
        '_': {
          '#': 'user123',
          '>': {'name': 1000, 'age': 2000, 'email': 500},
        }
      };
      
      final incomingNode = {
        'name': 'Johnny', // Newer
        'age': 25,      // Older
        'city': 'NYC',  // New field
        '_': {
          '#': 'user123',
          '>': {'name': 1500, 'age': 1000, 'city': 3000},
        }
      };
      
      final merged = MetadataManager.mergeNodes(currentNode, incomingNode);
      
      expect(merged['name'], equals('Johnny')); // Newer timestamp wins
      expect(merged['age'], equals(30));        // Current timestamp wins
      expect(merged['email'], equals('old@example.com')); // Preserved from current
      expect(merged['city'], equals('NYC'));    // New field from incoming
      
      final metadata = merged['_'] as Map<String, dynamic>;
      final timestamps = metadata['>'] as Map<String, num>;
      expect(timestamps['name'], equals(1500));
      expect(timestamps['age'], equals(2000));
      expect(timestamps['email'], equals(500));
      expect(timestamps['city'], equals(3000));
    });

    test('should resolve timestamp ties deterministically', () {
      final currentNode = {
        'name': 'Alpha',
        '_': {
          '#': 'user123',
          '>': {'name': 1000},
        }
      };
      
      final incomingNode = {
        'name': 'Beta',
        '_': {
          '#': 'user123',
          '>': {'name': 1000}, // Same timestamp
        }
      };
      
      final merged = MetadataManager.mergeNodes(currentNode, incomingNode);
      
      // 'Beta' > 'Alpha' lexicographically
      expect(merged['name'], equals('Beta'));
    });

    test('should generate unique node IDs', () {
      final id1 = MetadataManager.generateNodeId();
      final id2 = MetadataManager.generateNodeId();
      
      expect(id1, isNot(equals(id2)));
      expect(id1.contains('-'), isTrue);
      expect(id2.contains('-'), isTrue);
    });

    test('should use path as node ID when provided', () {
      final nodeId = MetadataManager.generateNodeId('users/john');
      
      expect(nodeId, equals('users/john'));
    });

    test('should update timestamps for modified fields only', () {
      final existingNode = {
        'name': 'John',
        'age': 30,
        'email': 'john@example.com',
        '_': {
          '#': 'user123',
          '>': {'name': 1000, 'age': 2000, 'email': 1500},
        }
      };
      
      final changes = {'name': 'Johnny', 'city': 'NYC'};
      
      final updated = MetadataManager.updateTimestamps(
        node: existingNode,
        changes: changes,
      );
      
      expect(updated['name'], equals('Johnny'));
      expect(updated['city'], equals('NYC'));
      expect(updated['age'], equals(30)); // Unchanged
      expect(updated['email'], equals('john@example.com')); // Unchanged
      
      final metadata = updated['_'] as Map<String, dynamic>;
      final timestamps = metadata['>'] as Map<String, num>;
      
      // Updated fields should have new timestamps
      expect(timestamps['name'], greaterThan(1000));
      expect(timestamps['city'], isA<num>());
      
      // Unchanged fields should keep old timestamps
      expect(timestamps['age'], equals(2000));
      expect(timestamps['email'], equals(1500));
    });

    test('should convert to wire format', () {
      final validNode = {
        'name': 'John',
        '_': {
          '#': 'user123',
          '>': {'name': 1000},
        }
      };
      
      final wireFormat = MetadataManager.toWireFormat(validNode);
      
      expect(wireFormat, equals(validNode));
    });

    test('should reject invalid node for wire format', () {
      final invalidNode = {'name': 'John'}; // No metadata
      
      expect(() => MetadataManager.toWireFormat(invalidNode), throwsStateError);
    });

    test('should create node from wire format', () {
      final wireData = {
        'name': 'John',
        '_': {
          '#': 'user123',
          '>': {'name': 1000},
        }
      };
      
      final node = MetadataManager.fromWireFormat(wireData);
      
      expect(node, equals(wireData));
    });

    test('should reject invalid wire format', () {
      final invalidWireData = {'name': 'John'}; // No metadata
      
      expect(() => MetadataManager.fromWireFormat(invalidWireData), 
             throwsA(isA<FormatException>()));
    });
  });

  group('MetadataValidator', () {
    test('should validate complete valid node', () {
      final validNode = {
        'name': 'John',
        '_': {
          '#': 'user123',
          '>': {'name': 1000, 'age': 2000},
          'machine': 1,
          'machineId': 'abc123',
        }
      };
      
      final result = MetadataValidator.validate(validNode);
      
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('should reject node without metadata', () {
      final invalidNode = {'name': 'John'};
      
      final result = MetadataValidator.validate(invalidNode);
      
      expect(result.isValid, isFalse);
      expect(result.errors, contains('Missing metadata field (_)'));
    });

    test('should reject node without node ID', () {
      final invalidNode = {
        'name': 'John',
        '_': {
          '>': {'name': 1000},
        }
      };
      
      final result = MetadataValidator.validate(invalidNode);
      
      expect(result.isValid, isFalse);
      expect(result.errors, contains('Missing node ID (#)'));
    });

    test('should reject node with invalid node ID', () {
      final invalidNode = {
        'name': 'John',
        '_': {
          '#': 123, // Should be string
          '>': {'name': 1000},
        }
      };
      
      final result = MetadataValidator.validate(invalidNode);
      
      expect(result.isValid, isFalse);
      expect(result.errors, contains('Invalid node ID: must be non-empty string'));
    });

    test('should reject node without timestamps', () {
      final invalidNode = {
        'name': 'John',
        '_': {
          '#': 'user123',
        }
      };
      
      final result = MetadataValidator.validate(invalidNode);
      
      expect(result.isValid, isFalse);
      expect(result.errors, contains('Missing HAM timestamps (>)'));
    });

    test('should reject node with invalid timestamp values', () {
      final invalidNode = {
        'name': 'John',
        '_': {
          '#': 'user123',
          '>': {'name': 'invalid'}, // Should be numeric
        }
      };
      
      final result = MetadataValidator.validate(invalidNode);
      
      expect(result.isValid, isFalse);
      expect(result.errors, contains('Invalid timestamp for field name: must be numeric'));
    });

    test('should validate optional fields correctly', () {
      final nodeWithValidOptionals = {
        'name': 'John',
        '_': {
          '#': 'user123',
          '>': {'name': 1000},
          'machine': 1,
          'machineId': 'abc123',
        }
      };
      
      final result = MetadataValidator.validate(nodeWithValidOptionals);
      
      expect(result.isValid, isTrue);
    });

    test('should reject invalid optional machine state', () {
      final invalidNode = {
        'name': 'John',
        '_': {
          '#': 'user123',
          '>': {'name': 1000},
          'machine': 'invalid', // Should be numeric
        }
      };
      
      final result = MetadataValidator.validate(invalidNode);
      
      expect(result.isValid, isFalse);
      expect(result.errors, contains('Invalid machine state: must be numeric if present'));
    });

    test('should reject invalid optional machine ID', () {
      final invalidNode = {
        'name': 'John',
        '_': {
          '#': 'user123',
          '>': {'name': 1000},
          'machineId': 123, // Should be string
        }
      };
      
      final result = MetadataValidator.validate(invalidNode);
      
      expect(result.isValid, isFalse);
      expect(result.errors, contains('Invalid machine ID: must be non-empty string if present'));
    });
  });
}
