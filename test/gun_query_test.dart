import 'package:flutter_test/flutter_test.dart';
import '../lib/src/network/gun_query.dart';

void main() {
  group('GunQuery Tests', () {
    test('should create simple node query', () {
      final query = GunQuery.node('users/alice');
      
      expect(query.nodeId, equals('users/alice'));
      expect(query.path, isEmpty);
      expect(query.isSimple, isTrue);
      expect(query.isTraversal, isFalse);
      expect(query.targetNodeId, equals('users/alice'));
      expect(query.fullPath, equals(['users/alice']));
    });
    
    test('should create graph traversal query', () {
      final query = GunQuery.traverse('users', ['alice', 'profile']);
      
      expect(query.nodeId, equals('users'));
      expect(query.path, equals(['alice', 'profile']));
      expect(query.isSimple, isFalse);
      expect(query.isTraversal, isTrue);
      expect(query.targetNodeId, equals('profile'));
      expect(query.fullPath, equals(['users', 'alice', 'profile']));
    });
    
    test('should convert simple query to wire format', () {
      final query = GunQuery.node('users/alice', queryId: 'test-123');
      final wireFormat = query.toWireFormat();
      
      expect(wireFormat, equals({
        'get': {
          '#': 'users/alice'
        },
        '@': 'test-123'
      }));
    });
    
    test('should convert traversal query to wire format', () {
      final query = GunQuery.traverse('users', ['alice'], queryId: 'test-456');
      final wireFormat = query.toWireFormat();
      
      expect(wireFormat, equals({
        'get': {
          '#': 'users',
          '.': {
            '#': 'alice'
          }
        },
        '@': 'test-456'
      }));
    });
    
    test('should convert multi-level traversal query to wire format', () {
      final query = GunQuery.traverse('users', ['alice', 'profile'], queryId: 'test-789');
      final wireFormat = query.toWireFormat();
      
      expect(wireFormat, equals({
        'get': {
          '#': 'users',
          '.': {
            '#': 'alice',
            '.': {
              '#': 'profile'
            }
          }
        },
        '@': 'test-789'
      }));
    });
    
    test('should parse simple query from wire format', () {
      final wireData = {
        'get': {
          '#': 'users/alice'
        },
        '@': 'test-123'
      };
      
      final query = GunQuery.fromWireFormat(wireData);
      
      expect(query.nodeId, equals('users/alice'));
      expect(query.path, isEmpty);
      expect(query.queryId, equals('test-123'));
    });
    
    test('should parse traversal query from wire format', () {
      final wireData = {
        'get': {
          '#': 'users',
          '.': {
            '#': 'alice'
          }
        },
        '@': 'test-456'
      };
      
      final query = GunQuery.fromWireFormat(wireData);
      
      expect(query.nodeId, equals('users'));
      expect(query.path, equals(['alice']));
      expect(query.queryId, equals('test-456'));
    });
    
    test('should parse multi-level traversal from wire format', () {
      final wireData = {
        'get': {
          '#': 'users',
          '.': {
            '#': 'alice',
            '.': {
              '#': 'profile'
            }
          }
        },
        '@': 'test-789'
      };
      
      final query = GunQuery.fromWireFormat(wireData);
      
      expect(query.nodeId, equals('users'));
      expect(query.path, equals(['alice', 'profile']));
      expect(query.queryId, equals('test-789'));
    });
    
    test('should extend query with additional path segment', () {
      final query = GunQuery.node('users');
      final extended = query.extend('alice');
      
      expect(extended.nodeId, equals('users'));
      expect(extended.path, equals(['alice']));
      expect(extended.queryId, isNot(equals(query.queryId))); // Should have new ID
    });
    
    test('should handle equality comparison', () {
      final query1 = GunQuery.node('users', queryId: 'test-123');
      final query2 = GunQuery.node('users', queryId: 'test-123');
      final query3 = GunQuery.node('posts', queryId: 'test-123');
      
      expect(query1, equals(query2));
      expect(query1, isNot(equals(query3)));
    });
    
    test('should throw error for invalid wire format', () {
      expect(() => GunQuery.fromWireFormat({}), 
             throwsA(isA<ArgumentError>()));
      
      expect(() => GunQuery.fromWireFormat({'get': {}}), 
             throwsA(isA<ArgumentError>()));
    });
  });
  
  group('GunQueryResult Tests', () {
    test('should create successful query result', () {
      final query = GunQuery.node('users/alice');
      final data = {'name': 'Alice', 'age': 30};
      final result = GunQueryResult(query: query, data: data);
      
      expect(result.isSuccess, isTrue);
      expect(result.isError, isFalse);
      expect(result.data, equals(data));
      expect(result.error, isNull);
    });
    
    test('should create error query result', () {
      final query = GunQuery.node('users/alice');
      final result = GunQueryResult(query: query, error: 'Node not found');
      
      expect(result.isSuccess, isFalse);
      expect(result.isError, isTrue);
      expect(result.data, isNull);
      expect(result.error, equals('Node not found'));
    });
  });
  
  group('GunQueryManager Tests', () {
    late GunQueryManager manager;
    
    setUp(() {
      manager = GunQueryManager();
    });
    
    tearDown(() {
      manager.clear();
    });
    
    test('should track and retrieve queries', () {
      final query = GunQuery.node('users/alice');
      manager.trackQuery(query);
      
      expect(manager.getQuery(query.queryId), equals(query));
      expect(manager.activeQueries, contains(query));
    });
    
    test('should handle query results', () {
      final query = GunQuery.node('users/alice');
      var callbackData;
      var callbackError;
      
      final queryWithCallback = GunQuery(
        nodeId: query.nodeId,
        queryId: query.queryId,
        callback: (data, error) {
          callbackData = data;
          callbackError = error;
        },
      );
      
      manager.trackQuery(queryWithCallback);
      
      final result = GunQueryResult(
        query: queryWithCallback, 
        data: {'name': 'Alice'}
      );
      manager.handleResult(queryWithCallback.queryId, result);
      
      expect(callbackData, equals({'name': 'Alice'}));
      expect(callbackError, isNull);
      expect(manager.getQuery(queryWithCallback.queryId), isNull);
    });
    
    test('should handle query errors', () {
      final query = GunQuery.node('users/alice');
      var callbackData;
      var callbackError;
      
      final queryWithCallback = GunQuery(
        nodeId: query.nodeId,
        queryId: query.queryId,
        callback: (data, error) {
          callbackData = data;
          callbackError = error;
        },
      );
      
      manager.trackQuery(queryWithCallback);
      
      final result = GunQueryResult(
        query: queryWithCallback,
        error: 'Node not found'
      );
      manager.handleResult(queryWithCallback.queryId, result);
      
      expect(callbackData, isNull);
      expect(callbackError, equals('Node not found'));
    });
    
    test('should provide statistics', () {
      final query1 = GunQuery.node('users/alice');
      final query2 = GunQuery.node('users/bob');
      
      manager.trackQuery(query1);
      manager.trackQuery(query2);
      
      final stats = manager.getStats();
      expect(stats['activeQueries'], equals(2));
      expect(stats['activeTimeouts'], equals(2));
    });
    
    test('should clear all queries', () {
      final query1 = GunQuery.node('users/alice');
      final query2 = GunQuery.node('users/bob');
      
      manager.trackQuery(query1);
      manager.trackQuery(query2);
      
      expect(manager.activeQueries.length, equals(2));
      
      manager.clear();
      
      expect(manager.activeQueries, isEmpty);
      expect(manager.getStats()['activeQueries'], equals(0));
    });
  });
}
