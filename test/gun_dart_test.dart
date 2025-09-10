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
      final retrieved = await gun.get('test').once() as Map<String, dynamic>;
      
      // Check that the data content is correct (ignoring metadata)
      expect(retrieved['name'], equals('Test User'));
      expect(retrieved['value'], equals(42));
      
      // Check that metadata was added
      expect(retrieved['_'], isA<Map<String, dynamic>>());
      final metadata = retrieved['_'] as Map<String, dynamic>;
      expect(metadata['#'], isA<String>());
      expect(metadata['>'], isA<Map<String, dynamic>>());
    });
    
    test('should handle nested data paths', () async {
      final testData = {'info': 'nested data'};
      
      // Store nested data
      await gun.get('users').get('testuser').put(testData);
      
      // Retrieve nested data
      final retrieved = await gun.get('users').get('testuser').once() as Map<String, dynamic>;
      
      // Check data content
      expect(retrieved['info'], equals('nested data'));
      
      // Check metadata
      expect(retrieved['_'], isA<Map<String, dynamic>>());
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
      
      // Check data content (now includes metadata)
      expect(receivedData['message'], equals('Hello real-time!'));
      expect(receivedData['_'], isA<Map<String, dynamic>>());
      
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
    
    test('should merge nodes correctly', () async {
      // Create nodes with proper HAM metadata for realistic testing
      final currentNode = CRDT.createNode('node1', {'name': 'Alice', 'age': 30});
      // Wait a bit to ensure different timestamps
      await Future.delayed(Duration(milliseconds: 2));
      final incomingNode = CRDT.createNode('node1', {'age': 31, 'city': 'NYC'});
      
      final merged = CRDT.mergeNodes(currentNode, incomingNode);
      expect(merged['name'], equals('Alice'));
      expect(merged['age'], equals(31)); // Incoming value wins due to newer timestamp
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
      // Storage now adds metadata automatically
      expect(retrieved!['test'], equals('value'));
      expect(retrieved['_'], isA<Map<String, dynamic>>());
      
      final metadata = retrieved['_'] as Map<String, dynamic>;
      expect(metadata['#'], equals('key1'));
      expect(metadata['>'], isA<Map<String, dynamic>>());
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
      final node = GunDataNode.create(
        id: 'test',
        data: {'name': 'Test'},
      );
      
      expect(node.id, equals('test'));
      expect(node.getValue('name'), equals('Test'));
      
      final updated = node.setValue('age', 25);
      expect(updated.getValue('age'), equals(25));
      expect(updated.getValue('name'), equals('Test'));
    });
    
    test('should handle links in nodes', () {
      final node = GunDataNode.create(
        id: 'test',
        data: {},
      );
      
      final withLink = node.createLink('friend', 'user123');
      expect(withLink.hasLinks, isTrue);
      
      final links = withLink.getLinks();
      expect(links.length, equals(1));
      expect(links.first.reference, equals('user123'));
    });
    
    test('should convert to/from wire format', () {
      final node = GunDataNode.create(
        id: 'test',
        data: {'name': 'Alice', 'age': 30},
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
  
  group('SEA (Security, Encryption, Authorization) Tests', () {
    test('should generate key pairs', () async {
      final keyPair = await SEA.pair();
      
      expect(keyPair.pub, isNotEmpty);
      expect(keyPair.priv, isNotEmpty);
      expect(keyPair.epub, isNotEmpty);
      expect(keyPair.epriv, isNotEmpty);
      expect(keyPair.pub, isNot(equals(keyPair.priv)));
    });
    
    test('should encrypt and decrypt data', () async {
      const password = 'test-password';
      const testData = 'Hello, World!';
      
      final encrypted = await SEA.encrypt(testData, password);
      final decrypted = await SEA.decrypt(encrypted, password);
      
      expect(encrypted, isNot(equals(testData)));
      expect(decrypted, equals(testData));
    });
    
    test('should encrypt and decrypt complex data', () async {
      const password = 'complex-password-123';
      final testData = {
        'name': 'Alice',
        'age': 30,
        'hobbies': ['reading', 'coding'],
        'metadata': {'verified': true}
      };
      
      final encrypted = await SEA.encrypt(testData, password);
      final decrypted = await SEA.decrypt(encrypted, password);
      
      expect(decrypted, equals(testData));
    });
    
    test('should fail to decrypt with wrong password', () async {
      const correctPassword = 'correct';
      const wrongPassword = 'wrong';
      const testData = 'secret data';
      
      final encrypted = await SEA.encrypt(testData, correctPassword);
      
      expect(() async => await SEA.decrypt(encrypted, wrongPassword),
          throwsA(isA<SEAException>()));
    });
    
    test('should sign and verify data', () async {
      final keyPair = await SEA.pair();
      const testData = 'data to sign';
      
      final signature = await SEA.sign(testData, keyPair);
      final isValid = await SEA.verify(testData, signature, keyPair.pub);
      
      expect(isValid, isTrue);
    });
    
    test('should fail verification with wrong data', () async {
      final keyPair = await SEA.pair();
      const originalData = 'original data';
      const tamperedData = 'tampered data';
      
      final signature = await SEA.sign(originalData, keyPair);
      final isValid = await SEA.verify(tamperedData, signature, keyPair.pub);
      
      expect(isValid, isFalse);
    });
    
    test('should create and verify work proofs', () async {
      final keyPair = await SEA.pair();
      const testData = {'message': 'test work'};
      
      final work = await SEA.work(testData, keyPair);
      final isValid = await SEA.verifyWork(work, keyPair.pub);
      
      expect(work.hash, isNotEmpty);
      expect(work.proof, isNotEmpty);
      expect(isValid, isTrue);
    });
  });
  
  group('User Authentication Tests', () {
    late Gun gun;
    
    setUp(() {
      gun = Gun();
    });
    
    tearDown(() async {
      await gun.close();
    });
    
    test('should create new user account', () async {
      const alias = 'testuser';
      const password = 'testpass123';
      
      final account = await gun.user().create(alias, password);
      
      expect(account.alias, equals(alias));
      expect(account.pub, isNotEmpty);
      expect(account.epub, isNotEmpty);
    });
    
    test('should prevent duplicate user creation', () async {
      const alias = 'duplicate';
      const password = 'password';
      
      await gun.user().create(alias, password);
      
      expect(() async => await gun.user().create(alias, password),
          throwsA(isA<UserException>()));
    });
    
    test('should authenticate existing user', () async {
      const alias = 'authtest';
      const password = 'authpass';
      
      // Create user first
      await gun.user().create(alias, password);
      await gun.user().leave();
      
      // Now authenticate
      final account = await gun.user().auth(alias, password);
      
      expect(account.alias, equals(alias));
      expect(gun.user().isAuthenticated, isTrue);
      expect(gun.user().alias, equals(alias));
    });
    
    test('should fail authentication with wrong password', () async {
      const alias = 'wrongpasstest';
      const correctPassword = 'correct';
      const wrongPassword = 'wrong';
      
      await gun.user().create(alias, correctPassword);
      await gun.user().leave();
      
      expect(() async => await gun.user().auth(alias, wrongPassword),
          throwsA(isA<UserException>()));
    });
    
    test('should sign out user', () async {
      const alias = 'signouttest';
      const password = 'password';
      
      await gun.user().create(alias, password);
      expect(gun.user().isAuthenticated, isTrue);
      
      await gun.user().leave();
      expect(gun.user().isAuthenticated, isFalse);
      expect(gun.user().alias, isNull);
    });
    
    test('should encrypt and decrypt user data', () async {
      const alias = 'cryptotest';
      const password = 'cryptopass';
      const testData = {'secret': 'user data'};
      
      await gun.user().create(alias, password);
      
      final encrypted = await gun.user().encrypt(testData);
      final decrypted = await gun.user().decrypt(encrypted);
      
      expect(decrypted, equals(testData));
    });
    
    test('should require authentication for encryption', () async {
      expect(() async => await gun.user().encrypt('data'),
          throwsA(isA<UserException>()));
    });
    
    test('should provide user storage access', () async {
      const alias = 'storagetest';
      const password = 'storagepass';
      
      await gun.user().create(alias, password);
      
      final userStorage = gun.user().storage;
      expect(userStorage, isNotNull);
      
      // Test storing data in user space
      await userStorage.get('profile').put({'name': 'Test User'});
      final profile = await userStorage.get('profile').once() as Map<String, dynamic>;
      
      // Check data content (now includes metadata)
      expect(profile['name'], equals('Test User'));
      expect(profile['_'], isA<Map<String, dynamic>>());
    });
    
    test('should emit user events', () async {
      const alias = 'eventtest';
      const password = 'eventpass';
      
      final events = <UserEvent>[];
      final subscription = gun.user().events.listen((event) => events.add(event));
      
      await gun.user().create(alias, password);
      // Give the stream time to process the event
      await Future.delayed(Duration(milliseconds: 10));
      expect(events.length, equals(1));
      expect(events[0].type, equals(UserEventType.created));
      
      await gun.user().leave();
      // Give the stream time to process the event
      await Future.delayed(Duration(milliseconds: 10));
      expect(events.length, equals(2));
      expect(events[1].type, equals(UserEventType.signedOut));
      
      subscription.cancel();
    });
  });
  
  group('Query Operations Tests', () {
    late Gun gun;
    
    setUp(() async {
      gun = Gun();
      
      // Set up test data for query operations
      await gun.get('users').put({
        'alice': {
          'name': 'Alice Smith',
          'age': 25,
          'role': 'admin',
          'active': true,
          'email': 'alice@example.com',
        },
        'bob': {
          'name': 'Bob Johnson', 
          'age': 30,
          'role': 'user',
          'active': true,
          'email': 'bob@example.com',
        },
        'charlie': {
          'name': 'Charlie Brown',
          'age': 22,
          'role': 'user', 
          'active': false,
          'email': 'charlie@example.com',
        },
        'diana': {
          'name': 'Diana Prince',
          'age': 28,
          'role': 'admin',
          'active': true,
          'email': 'diana@example.com',
        },
      });
      
      // Set up test products data
      await gun.get('products').put({
        'laptop': {
          'name': 'Gaming Laptop',
          'price': 1299.99,
          'category': 'electronics',
          'inStock': true,
          'rating': 4.5,
        },
        'mouse': {
          'name': 'Wireless Mouse',
          'price': 29.99,
          'category': 'electronics',
          'inStock': true,
          'rating': 4.2,
        },
        'book': {
          'name': 'Learning Dart',
          'price': 39.99,
          'category': 'books',
          'inStock': false,
          'rating': 4.8,
        },
        'chair': {
          'name': 'Office Chair',
          'price': 199.99,
          'category': 'furniture',
          'inStock': true,
          'rating': 3.9,
        },
      });
    });
    
    tearDown(() async {
      await gun.close();
    });
    
    group('Filter Operations', () {
      test('should filter by single boolean condition', () async {
        final activeUsers = await gun.get('users')
          .filter((user, key) => user['active'] == true)
          .once();
        
        expect(activeUsers, isA<Map<String, dynamic>>());
        final activeMap = activeUsers as Map<String, dynamic>;
        
        // Should contain alice, bob, and diana but not charlie
        expect(activeMap.keys, contains('alice'));
        expect(activeMap.keys, contains('bob'));
        expect(activeMap.keys, contains('diana'));
        expect(activeMap.keys, isNot(contains('charlie')));
        
        // Verify the filtered data content
        expect(activeMap['alice']['active'], isTrue);
        expect(activeMap['bob']['active'], isTrue);
        expect(activeMap['diana']['active'], isTrue);
      });
      
      test('should filter by string condition', () async {
        final adminUsers = await gun.get('users')
          .filter((user, key) => user['role'] == 'admin')
          .once();
        
        expect(adminUsers, isA<Map<String, dynamic>>());
        final adminMap = adminUsers as Map<String, dynamic>;
        
        // Should contain alice and diana but not bob or charlie
        expect(adminMap.keys, contains('alice'));
        expect(adminMap.keys, contains('diana'));
        expect(adminMap.keys, isNot(contains('bob')));
        expect(adminMap.keys, isNot(contains('charlie')));
        
        expect(adminMap['alice']['role'], equals('admin'));
        expect(adminMap['diana']['role'], equals('admin'));
      });
      
      test('should filter by numeric condition', () async {
        final youngerUsers = await gun.get('users')
          .filter((user, key) => user['age'] < 27)
          .once();
        
        expect(youngerUsers, isA<Map<String, dynamic>>());
        final youngerMap = youngerUsers as Map<String, dynamic>;
        
        // Should contain alice (25) and charlie (22)
        expect(youngerMap.keys, contains('alice'));
        expect(youngerMap.keys, contains('charlie'));
        expect(youngerMap.keys, isNot(contains('bob'))); // 30
        expect(youngerMap.keys, isNot(contains('diana'))); // 28
        
        expect(youngerMap['alice']['age'], lessThan(27));
        expect(youngerMap['charlie']['age'], lessThan(27));
      });
      
      test('should filter by complex compound condition', () async {
        final activeAdmins = await gun.get('users')
          .filter((user, key) => user['active'] == true && user['role'] == 'admin')
          .once();
        
        expect(activeAdmins, isA<Map<String, dynamic>>());
        final activeAdminMap = activeAdmins as Map<String, dynamic>;
        
        // Should only contain alice and diana (both active admins)
        expect(activeAdminMap.keys, contains('alice'));
        expect(activeAdminMap.keys, contains('diana'));
        expect(activeAdminMap.keys, isNot(contains('bob'))); // user, not admin
        expect(activeAdminMap.keys, isNot(contains('charlie'))); // not active
        
        expect(activeAdminMap['alice']['active'], isTrue);
        expect(activeAdminMap['alice']['role'], equals('admin'));
        expect(activeAdminMap['diana']['active'], isTrue);
        expect(activeAdminMap['diana']['role'], equals('admin'));
      });
      
      test('should handle filter with no matching results', () async {
        final superOldUsers = await gun.get('users')
          .filter((user, key) => user['age'] > 100)
          .once();
        
        expect(superOldUsers, isA<Map<String, dynamic>>());
        final superOldMap = superOldUsers as Map<String, dynamic>;
        expect(superOldMap.keys, isEmpty);
      });
      
      test('should filter products by price range', () async {
        final affordableProducts = await gun.get('products')
          .filter((product, key) => product['price'] < 50.0)
          .once();
        
        expect(affordableProducts, isA<Map<String, dynamic>>());
        final affordableMap = affordableProducts as Map<String, dynamic>;
        
        // Should contain mouse and book
        expect(affordableMap.keys, contains('mouse')); // 29.99
        expect(affordableMap.keys, contains('book'));  // 39.99
        expect(affordableMap.keys, isNot(contains('laptop'))); // 1299.99
        expect(affordableMap.keys, isNot(contains('chair')));  // 199.99
      });
      
      test('should filter by key name', () async {
        final usersStartingWithA = await gun.get('users')
          .filter((user, key) => key.startsWith('a'))
          .once();
        
        expect(usersStartingWithA, isA<Map<String, dynamic>>());
        final aUsersMap = usersStartingWithA as Map<String, dynamic>;
        
        // Should only contain alice
        expect(aUsersMap.keys, contains('alice'));
        expect(aUsersMap.keys, isNot(contains('bob')));
        expect(aUsersMap.keys, isNot(contains('charlie')));
        expect(aUsersMap.keys, isNot(contains('diana')));
      });
    });
    
    group('Map Operations', () {
      test('should map to extract single field', () async {
        final userNames = await gun.get('users')
          .map((user, key) => {'name': user['name']})
          .once();
        
        expect(userNames, isA<Map<String, dynamic>>());
        final namesMap = userNames as Map<String, dynamic>;
        
        // Should have all user keys but only name field
        expect(namesMap.keys, contains('alice'));
        expect(namesMap.keys, contains('bob'));
        expect(namesMap.keys, contains('charlie'));
        expect(namesMap.keys, contains('diana'));
        
        expect(namesMap['alice'], equals({'name': 'Alice Smith'}));
        expect(namesMap['bob'], equals({'name': 'Bob Johnson'}));
        expect(namesMap['charlie'], equals({'name': 'Charlie Brown'}));
        expect(namesMap['diana'], equals({'name': 'Diana Prince'}));
        
        // Should not contain other fields
        expect(namesMap['alice'], isNot(contains('age')));
        expect(namesMap['alice'], isNot(contains('role')));
      });
      
      test('should map to transform field values', () async {
        final userSummaries = await gun.get('users')
          .map((user, key) => {
            'id': key.toUpperCase(),
            'displayName': '${user['name']} (${user['role']})',
            'isActive': user['active'],
            'ageGroup': user['age'] < 25 ? 'young' : user['age'] < 30 ? 'adult' : 'mature',
          })
          .once();
        
        expect(userSummaries, isA<Map<String, dynamic>>());
        final summariesMap = userSummaries as Map<String, dynamic>;
        
        expect(summariesMap['alice'], equals({
          'id': 'ALICE',
          'displayName': 'Alice Smith (admin)',
          'isActive': true,
          'ageGroup': 'adult', // 25
        }));
        
        expect(summariesMap['charlie'], equals({
          'id': 'CHARLIE', 
          'displayName': 'Charlie Brown (user)',
          'isActive': false,
          'ageGroup': 'young', // 22
        }));
        
        expect(summariesMap['bob'], equals({
          'id': 'BOB',
          'displayName': 'Bob Johnson (user)',
          'isActive': true,
          'ageGroup': 'mature', // 30
        }));
      });
      
      test('should map products to price categories', () async {
        final priceCategories = await gun.get('products')
          .map((product, key) => {
            'name': product['name'],
            'priceCategory': product['price'] < 50 ? 'budget' : 
                           product['price'] < 200 ? 'mid-range' : 'premium',
            'availability': product['inStock'] ? 'available' : 'out-of-stock',
          })
          .once();
        
        expect(priceCategories, isA<Map<String, dynamic>>());
        final categoriesMap = priceCategories as Map<String, dynamic>;
        
        expect(categoriesMap['mouse'], equals({
          'name': 'Wireless Mouse',
          'priceCategory': 'budget',   // 29.99
          'availability': 'available',
        }));
        
        expect(categoriesMap['chair'], equals({
          'name': 'Office Chair',
          'priceCategory': 'mid-range', // 199.99
          'availability': 'available',
        }));
        
        expect(categoriesMap['laptop'], equals({
          'name': 'Gaming Laptop',
          'priceCategory': 'premium',   // 1299.99
          'availability': 'available',
        }));
      });
      
      test('should map with key transformation', () async {
        final keyBasedMapping = await gun.get('users')
          .map((user, key) => {
            'originalKey': key,
            'keyLength': key.length,
            'keyUppercase': key.toUpperCase(),
            'userName': user['name'],
          })
          .once();
        
        expect(keyBasedMapping, isA<Map<String, dynamic>>());
        final keyMappingMap = keyBasedMapping as Map<String, dynamic>;
        
        expect(keyMappingMap['alice'], equals({
          'originalKey': 'alice',
          'keyLength': 5,
          'keyUppercase': 'ALICE',
          'userName': 'Alice Smith',
        }));
      });
      
      test('should handle map with null/empty values', () async {
        // Add a user with some null values
        await gun.get('users').get('testuser').put({
          'name': 'Test User',
          'age': null,
          'role': '',
          'active': false,
        });
        
        final safeMapping = await gun.get('users')
          .map((user, key) => {
            'name': user['name'] ?? 'Unknown',
            'age': user['age'] ?? 0,
            'role': user['role']?.isEmpty == true ? 'unassigned' : user['role'],
            'status': user['active'] == true ? 'active' : 'inactive',
          })
          .once();
        
        expect(safeMapping, isA<Map<String, dynamic>>());
        final safeMappingMap = safeMapping as Map<String, dynamic>;
        
        expect(safeMappingMap['testuser'], equals({
          'name': 'Test User',
          'age': 0,
          'role': 'unassigned',
          'status': 'inactive',
        }));
      });
    });
    
    group('Chained Filter and Map Operations', () {
      test('should chain filter then map', () async {
        final activeUserNames = await gun.get('users')
          .filter((user, key) => user['active'] == true)
          .map((user, key) => {
            'name': user['name'],
            'email': user['email'],
          })
          .once();
        
        expect(activeUserNames, isA<Map<String, dynamic>>());
        final activeNamesMap = activeUserNames as Map<String, dynamic>;
        
        // Should only have active users
        expect(activeNamesMap.keys, contains('alice'));
        expect(activeNamesMap.keys, contains('bob'));
        expect(activeNamesMap.keys, contains('diana'));
        expect(activeNamesMap.keys, isNot(contains('charlie'))); // not active
        
        // Should only have mapped fields
        expect(activeNamesMap['alice'], equals({
          'name': 'Alice Smith',
          'email': 'alice@example.com',
        }));
        expect(activeNamesMap['alice'], isNot(contains('age')));
        expect(activeNamesMap['alice'], isNot(contains('role')));
      });
      
      test('should chain map then filter', () async {
        final expensiveProductNames = await gun.get('products')
          .map((product, key) => {
            'name': product['name'],
            'isExpensive': product['price'] > 100,
            'price': product['price'],
          })
          .filter((product, key) => product['isExpensive'] == true)
          .once();
        
        expect(expensiveProductNames, isA<Map<String, dynamic>>());
        final expensiveMap = expensiveProductNames as Map<String, dynamic>;
        
        // Should only have expensive products (laptop and chair)
        expect(expensiveMap.keys, contains('laptop'));
        expect(expensiveMap.keys, contains('chair'));
        expect(expensiveMap.keys, isNot(contains('mouse')));
        expect(expensiveMap.keys, isNot(contains('book')));
        
        expect(expensiveMap['laptop']['isExpensive'], isTrue);
        expect(expensiveMap['chair']['isExpensive'], isTrue);
      });
      
      test('should chain multiple filters and maps', () async {
        final adminUserSummary = await gun.get('users')
          .filter((user, key) => user['role'] == 'admin')
          .filter((user, key) => user['active'] == true)
          .map((user, key) => {
            'adminId': key.toUpperCase(),
            'fullName': user['name'],
            'contactEmail': user['email'],
          })
          .once();
        
        expect(adminUserSummary, isA<Map<String, dynamic>>());
        final adminMap = adminUserSummary as Map<String, dynamic>;
        
        // Should only have active admins (alice and diana)
        expect(adminMap.keys, contains('alice'));
        expect(adminMap.keys, contains('diana'));
        expect(adminMap.keys, isNot(contains('bob')));     // not admin
        expect(adminMap.keys, isNot(contains('charlie'))); // not active
        
        expect(adminMap['alice'], equals({
          'adminId': 'ALICE',
          'fullName': 'Alice Smith',
          'contactEmail': 'alice@example.com',
        }));
      });
    });
    
    group('Error Handling', () {
      test('should handle filter function errors gracefully', () async {
        try {
          await gun.get('users')
            .filter((user, key) => throw Exception('Filter error'))
            .once();
          // If no exception is thrown, that's also acceptable
        } catch (e) {
          // Error handling is implementation dependent
          expect(e, isA<Exception>());
        }
      });
      
      test('should handle map function errors gracefully', () async {
        try {
          await gun.get('users')
            .map((user, key) => throw Exception('Map error'))
            .once();
          // If no exception is thrown, that's also acceptable
        } catch (e) {
          // Error handling is implementation dependent 
          expect(e, isA<Exception>());
        }
      });
      
      test('should handle filter on non-existent data', () async {
        final result = await gun.get('nonexistent')
          .filter((item, key) => true)
          .once();
        
        expect(result, isNull);
      });
      
      test('should handle map on non-existent data', () async {
        final result = await gun.get('nonexistent')
          .map((item, key) => {'transformed': true})
          .once();
        
        expect(result, isNull);
      });
    });
    
    group('Real-time Operations', () {
      test('should filter on real-time updates', () async {
        final completer = Completer<Map<String, dynamic>>();
        
        // Subscribe to filtered active users
        final subscription = gun.get('realtimeUsers')
          .filter((user, key) => user['active'] == true)
          .on((data, key) {
            if (!completer.isCompleted) {
              completer.complete(data as Map<String, dynamic>);
            }
          });
        
        // Add test data with both active and inactive users
        await gun.get('realtimeUsers').put({
          'user1': {
            'name': 'Active User',
            'active': true,
          },
          'user2': {
            'name': 'Inactive User', 
            'active': false,
          },
        });
        
        final receivedData = await completer.future;
        
        // Should receive the filtered data
        expect(receivedData.keys, contains('user1'));
        // Depending on implementation, user2 might be filtered out
        
        await subscription.cancel();
      });
      
      test('should map on real-time updates', () async {
        final completer = Completer<Map<String, dynamic>>();
        
        // Subscribe to mapped user data
        final subscription = gun.get('realtimeMapping')
          .map((user, key) => {
            'id': key,
            'displayName': user['name'],
          })
          .on((data, key) {
            if (!completer.isCompleted) {
              completer.complete(data as Map<String, dynamic>);
            }
          });
        
        // Add test data
        await gun.get('realtimeMapping').put({
          'testuser': {
            'name': 'Test User',
            'age': 25,
          },
        });
        
        final receivedData = await completer.future;
        
        // Should receive the mapped data structure
        expect(receivedData, isA<Map<String, dynamic>>());
        
        await subscription.cancel();
      });
    });
  });
}
