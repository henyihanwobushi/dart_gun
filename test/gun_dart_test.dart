import 'package:flutter_test/flutter_test.dart';
import 'package:gun_dart/gun_dart.dart';
import 'dart:async';

void main() {
  group('Gun Dart Core Tests', () {
    late Gun gun;
    
    setUp(() {
      gun = Gun();
    });
    
    tearDown(() async {
      await gun.close();
    });
    
    test('should create Gun instance', () {
      expect(gun, isNotNull);
      expect(gun.storage, isNotNull);
      expect(gun.graph, isNotNull);
    });
    
    test('should store and retrieve data', () async {
      final testData = {'name': 'Test User', 'value': 42};
      
      // Store data
      await gun.get('test').put(testData);
      
      // Retrieve data
      final retrieved = await gun.get('test').once();
      expect(retrieved, equals(testData));
    });
    
    test('should handle nested data paths', () async {
      final testData = {'info': 'nested data'};
      
      // Store nested data
      await gun.get('users').get('testuser').put(testData);
      
      // Retrieve nested data
      final retrieved = await gun.get('users').get('testuser').once();
      expect(retrieved, equals(testData));
    });
    
    test('should return null for non-existent keys', () async {
      final retrieved = await gun.get('nonexistent').once();
      expect(retrieved, isNull);
    });
    
    test('should handle real-time subscriptions', () async {
      final completer = Completer<Map<String, dynamic>>();
      
      // Subscribe to changes
      final subscription = gun.get('realtime-test').on((data, key) {
        completer.complete(data as Map<String, dynamic>);
      });
      
      // Put some data
      final testData = {'message': 'Hello real-time!'};
      await gun.get('realtime-test').put(testData);
      
      // Wait for the subscription to fire
      final receivedData = await completer.future;
      expect(receivedData, equals(testData));
      
      await subscription.cancel();
    });
    
    test('should update graph when putting data', () async {
      final testData = {'value': 'graph test'};
      await gun.get('graph-test').put(testData);
      
      // Check that the graph was updated
      final node = gun.graph.getNode('graph-test');
      expect(node, isNotNull);
      expect(node!.data['value'], equals('graph test'));
    });
  });
  
  group('CRDT Tests', () {
    test('should resolve conflicts using Last Write Wins', () {
      final now = DateTime.now();
      final earlier = now.subtract(Duration(seconds: 1));
      
      final result = CRDT.resolve('old', 'new', 
          currentTime: earlier, incomingTime: now);
      expect(result, equals('new'));
      
      final result2 = CRDT.resolve('old', 'new', 
          currentTime: now, incomingTime: earlier);
      expect(result2, equals('old'));
    });
    
    test('should merge nodes correctly', () {
      final current = {'name': 'Alice', 'age': 30};
      final incoming = {'age': 31, 'city': 'NYC'};
      
      final merged = CRDT.mergeNodes(current, incoming);
      expect(merged['name'], equals('Alice'));
      expect(merged['age'], equals(31));
      expect(merged['city'], equals('NYC'));
    });
    
    test('should generate timestamps', () {
      final ts1 = CRDT.generateTimestamp();
      final ts2 = CRDT.generateTimestamp();
      expect(ts2, greaterThanOrEqualTo(ts1));
    });
  });
  
  group('Graph Tests', () {
    late Graph graph;
    
    setUp(() {
      graph = Graph();
    });
    
    tearDown(() {
      graph.dispose();
    });
    
    test('should add and retrieve nodes', () {
      final data = {'name': 'Test Node'};
      graph.putNode('test-id', data);
      
      final node = graph.getNode('test-id');
      expect(node, isNotNull);
      expect(node!.data['name'], equals('Test Node'));
    });
    
    test('should create and traverse links', () {
      // Create nodes
      graph.putNode('user1', {'name': 'Alice'});
      graph.putNode('user2', {'name': 'Bob'});
      
      // Create link
      graph.createLink('user1', 'user2', 'friend');
      
      // Check link exists
      final edges = graph.getEdges('user1');
      expect(edges, contains('user2'));
      
      // Test traversal
      final traversed = graph.traverse('user1');
      expect(traversed, contains('user1'));
      expect(traversed, contains('user2'));
    });
    
    test('should emit events on changes', () async {
      final completer = Completer<GraphEvent>();
      
      graph.events.listen((event) {
        if (!completer.isCompleted) {
          completer.complete(event);
        }
      });
      
      graph.putNode('event-test', {'data': 'test'});
      
      final event = await completer.future;
      expect(event.type, equals(GraphEventType.nodeUpdated));
      expect(event.nodeId, equals('event-test'));
    });
  });
  
  group('Storage Tests', () {
    late MemoryStorage storage;
    
    setUp(() {
      storage = MemoryStorage();
    });
    
    tearDown(() async {
      await storage.close();
    });
    
    test('should initialize storage', () async {
      await storage.initialize();
      expect(storage, isNotNull);
    });
    
    test('should store and retrieve data', () async {
      await storage.initialize();
      
      final data = {'test': 'value'};
      await storage.put('key1', data);
      
      final retrieved = await storage.get('key1');
      expect(retrieved, equals(data));
    });
    
    test('should check existence and delete', () async {
      await storage.initialize();
      
      final data = {'test': 'value'};
      await storage.put('key1', data);
      
      expect(await storage.exists('key1'), isTrue);
      expect(await storage.exists('nonexistent'), isFalse);
      
      await storage.delete('key1');
      expect(await storage.exists('key1'), isFalse);
    });
    
    test('should list keys with pattern matching', () async {
      await storage.initialize();
      
      await storage.put('user:alice', {'name': 'Alice'});
      await storage.put('user:bob', {'name': 'Bob'});
      await storage.put('post:1', {'title': 'Hello'});
      
      final allKeys = await storage.keys();
      expect(allKeys.length, equals(3));
      
      final userKeys = await storage.keys('user');
      expect(userKeys.length, equals(2));
      expect(userKeys, contains('user:alice'));
      expect(userKeys, contains('user:bob'));
    });
  });
  
  group('Node Data Tests', () {
    test('should create and update GunDataNode', () {
      final node = GunDataNode(
        id: 'test',
        data: {'name': 'Test'},
        lastModified: DateTime.now(),
      );
      
      expect(node.id, equals('test'));
      expect(node.getValue('name'), equals('Test'));
      
      final updated = node.setValue('age', 25);
      expect(updated.getValue('age'), equals(25));
      expect(updated.getValue('name'), equals('Test'));
    });
    
    test('should handle links in nodes', () {
      final node = GunDataNode(
        id: 'test',
        data: {},
        lastModified: DateTime.now(),
      );
      
      final withLink = node.createLink('friend', 'user123');
      expect(withLink.hasLinks, isTrue);
      
      final links = withLink.getLinks();
      expect(links.length, equals(1));
      expect(links.first.reference, equals('user123'));
    });
    
    test('should convert to/from wire format', () {
      final node = GunDataNode(
        id: 'test',
        data: {'name': 'Alice', 'age': 30},
        lastModified: DateTime.now(),
        vectorClock: {'name': 1234567890, 'age': 1234567891},
      );
      
      final wireFormat = node.toWireFormat();
      expect(wireFormat['name'], equals('Alice'));
      expect(wireFormat['age'], equals(30));
      expect(wireFormat['_']['#'], equals('test'));
      
      final restored = GunDataNode.fromWireFormat(wireFormat);
      expect(restored.id, equals('test'));
      expect(restored.getValue('name'), equals('Alice'));
      expect(restored.getValue('age'), equals(30));
    });
  });
  
  group('Utils Tests', () {
    test('should generate random strings', () {
      final str1 = Utils.randomString(10);
      final str2 = Utils.randomString(10);
      
      expect(str1.length, equals(10));
      expect(str2.length, equals(10));
      expect(str1, isNot(equals(str2)));
    });
    
    test('should check if objects are plain', () {
      expect(Utils.isPlain(null), isTrue);
      expect(Utils.isPlain('string'), isTrue);
      expect(Utils.isPlain(42), isTrue);
      expect(Utils.isPlain(true), isTrue);
      expect(Utils.isPlain(['a', 'b']), isTrue);
      expect(Utils.isPlain({'key': 'value'}), isTrue);
    });
    
    test('should deep copy objects', () {
      final original = {
        'name': 'Alice',
        'details': {'age': 30, 'city': 'NYC'},
        'hobbies': ['reading', 'coding']
      };
      
      final copy = Utils.deepCopy(original);
      expect(copy, equals(original));
      expect(identical(copy, original), isFalse);
      expect(identical(copy['details'], original['details']), isFalse);
    });
    
    test('should check deep equality', () {
      final obj1 = {'name': 'Alice', 'age': 30};
      final obj2 = {'name': 'Alice', 'age': 30};
      final obj3 = {'name': 'Bob', 'age': 30};
      
      expect(Utils.deepEqual(obj1, obj2), isTrue);
      expect(Utils.deepEqual(obj1, obj3), isFalse);
    });
    
    test('should merge objects deeply', () {
      final target = {'a': 1, 'b': {'c': 2}};
      final source = {'b': {'d': 3}, 'e': 4};
      
      final merged = Utils.deepMerge(target, source);
      expect(merged['a'], equals(1));
      expect(merged['b']['c'], equals(2));
      expect(merged['b']['d'], equals(3));
      expect(merged['e'], equals(4));
    });
    
    test('should match patterns', () {
      expect(Utils.matchPattern('hello', 'hello'), isTrue);
      expect(Utils.matchPattern('hello world', '*world'), isTrue);
      expect(Utils.matchPattern('hello world', 'hello*'), isTrue);
      expect(Utils.matchPattern('hello world', '*lo wo*'), isTrue);
      expect(Utils.matchPattern('hello', 'world'), isFalse);
    });
  });
}
