import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import '../lib/dart_gun.dart';

/// Tests for Gun.js compatible user space implementation
/// 
/// Validates that user data isolation and path formats match Gun.js exactly
void main() {
  group('Gun.js User Space Compatibility', () {
    late Gun gun;
    
    setUp(() {
      gun = Gun(GunOptions(storage: MemoryStorage()));
    });
    
    tearDown(() async {
      await gun.close();
    });
    
    group('User Path Formats', () {
      test('should use ~@alias format for user data', () async {
        final user = gun.user();
        await user.create('testuser', 'password123');
        
        // Should be able to access user data via ~@alias path
        final userData = await gun.get('~@testuser').once();
        expect(userData, isNotNull);
        expect(userData!['alias'], equals('testuser'));
        
        // User data space should point to same location
        final userDataViaChain = await user.data.once();
        expect(userDataViaChain!['alias'], equals('testuser'));
      });
      
      test('should use ~publickey format for public key space', () async {
        final user = gun.user();
        final account = await user.create('alice', 'secret456');
        
        // Should be able to access user data via ~publickey path
        final publicData = await gun.get('~${account.pub}').once();
        expect(publicData, isNotNull);
        expect(publicData!['alias'], equals('alice'));
        
        // Public space should point to same location
        final publicDataViaChain = await user.publicSpace.once();
        expect(publicDataViaChain!['alias'], equals('alice'));
      });
      
      test('should support user path resolution', () async {
        final user = gun.user();
        await user.create('bob', 'mypassword');
        
        // Test alias to public key resolution
        final pubKey = await user.aliasToPublicKey('bob');
        expect(pubKey, isNotNull);
        expect(pubKey, equals(user.keyPair!.pub));
        
        // Test public key to alias resolution
        final alias = await user.publicKeyToAlias(pubKey!);
        expect(alias, equals('bob'));
      });
    });
    
    group('User Data Isolation', () {
      test('should isolate user data by alias', () async {
        // Create two separate Gun instances to ensure complete isolation
        final gun1 = Gun(GunOptions(storage: MemoryStorage()));
        final gun2 = Gun(GunOptions(storage: MemoryStorage()));
        
        try {
          final user1 = gun1.user();
          final user2 = gun2.user();
          
          // Create two different users
          await user1.create('user1', 'pass1');
          await user2.create('user2', 'pass2');
          
          // Each user should have isolated data spaces
          await user1.getUserPath('profile').put({
            'name': 'User One',
            'email': 'user1@example.com',
          });
          
          await user2.getUserPath('profile').put({
            'name': 'User Two',
            'email': 'user2@example.com',
          });
          
          // Verify isolation - user1's data should not be accessible to user2
          final user1Profile = await user1.getUserPath('profile').once();
          expect(user1Profile!['name'], equals('User One'));
          
          final user2Profile = await user2.getUserPath('profile').once();
          expect(user2Profile!['name'], equals('User Two'));
          
          // Verify cross-instance isolation
          final user1ViaGun2 = await gun2.get('~@user1').get('profile').once();
          expect(user1ViaGun2, isNull); // Should not exist in gun2's storage
          
          final user2ViaGun1 = await gun1.get('~@user2').get('profile').once();
          expect(user2ViaGun1, isNull); // Should not exist in gun1's storage
        } finally {
          await gun1.close();
          await gun2.close();
        }
      });
      
      test('should handle user data encryption', () async {
        final user = gun.user();
        await user.create('secureuser', 'securepass');
        
        // Encrypt some sensitive data
        final sensitiveData = {'ssn': '123-45-6789', 'secret': 'top secret'};
        final encrypted = await user.encrypt(sensitiveData);
        
        // Store encrypted data in user space
        await user.getUserPath('private').put({'data': encrypted});
        
        // Verify we can decrypt it back
        final storedData = await user.getUserPath('private').once();
        final decrypted = await user.decrypt(storedData!['data'] as String);
        
        expect(decrypted['ssn'], equals('123-45-6789'));
        expect(decrypted['secret'], equals('top secret'));
      });
      
      test('should support user data signing and verification', () async {
        final user = gun.user();
        await user.create('signer', 'signpass');
        
        final message = {'text': 'This is a signed message', 'timestamp': DateTime.now().millisecondsSinceEpoch};
        
        // Sign the message
        final signature = await user.sign(message);
        
        // Verify with public key
        final isValid = await user.verify(message, signature, user.keyPair!.pub);
        expect(isValid, isTrue);
        
        // Verify with wrong public key should fail
        final anotherUser = gun.user();
        await anotherUser.create('other', 'otherpass');
        final invalidVerify = await user.verify(message, signature, anotherUser.keyPair!.pub);
        expect(invalidVerify, isFalse);
      });
    });
    
    group('Gun.js User Space Format Compatibility', () {
      test('should match Gun.js user data structure', () async {
        final user = gun.user();
        final account = await user.create('gunjs_compatible', 'password');
        
        // Check that user data follows Gun.js format
        final userData = await gun.get('~@gunjs_compatible').once();
        expect(userData, isNotNull);
        expect(userData!.containsKey('alias'), isTrue);
        expect(userData.containsKey('pub'), isTrue);
        expect(userData.containsKey('epub'), isTrue);
        expect(userData.containsKey('auth'), isTrue);
        
        expect(userData['alias'], equals('gunjs_compatible'));
        expect(userData['pub'], equals(account.pub));
        expect(userData['epub'], equals(account.epub));
        expect(userData['auth'], isA<String>()); // Encrypted auth data
        
        // Check public key space has same data
        final publicData = await gun.get('~${account.pub}').once();
        expect(publicData!['alias'], equals(userData['alias']));
        expect(publicData['pub'], equals(userData['pub']));
      });
      
      test('should handle user space paths like Gun.js', () async {
        final user = gun.user();
        await user.create('pathtest', 'pathpass');
        
        // Test various user space paths that Gun.js uses
        await user.getUserPath('profile').put({'name': 'Test User'});
        await user.getUserPath('todos').put({'item1': 'Task 1', 'item2': 'Task 2'});
        await user.getUserPath('settings/theme').put({'color': 'dark'});
        
        // Verify paths are accessible
        final profile = await user.getUserPath('profile').once();
        expect(profile!['name'], equals('Test User'));
        
        final todos = await user.getUserPath('todos').once();
        expect(todos!['item1'], equals('Task 1'));
        
        final theme = await user.getUserPath('settings/theme').once();
        expect(theme!['color'], equals('dark'));
        
        // Should also be accessible via direct Gun paths
        final directProfile = await gun.get('~@pathtest').get('profile').once();
        expect(directProfile!['name'], equals('Test User'));
      });
    });
    
    group('User Authentication Events', () {
      test('should emit proper user events', () async {
        final user = gun.user();
        final events = <UserEvent>[];
        final eventsCompleter = Completer<void>();
        
        // Listen to user events
        late StreamSubscription subscription;
        subscription = user.events.listen((event) {
          events.add(event);
          // Complete when we have all expected events
          if (events.length >= 3) {
            eventsCompleter.complete();
            subscription.cancel();
          }
        });
        
        // Create user - should emit created event
        await user.create('eventuser', 'eventpass');
        
        // Sign out - should emit signed out event
        await user.leave();
        
        // Auth back in - should emit authenticated event
        await user.auth('eventuser', 'eventpass');
        
        // Wait for all events to be processed
        await eventsCompleter.future.timeout(const Duration(seconds: 2));
        
        expect(events.length, equals(3));
        expect(events[0].type, equals(UserEventType.created));
        expect(events[0].alias, equals('eventuser'));
        expect(events[1].type, equals(UserEventType.signedOut));
        expect(events[2].type, equals(UserEventType.authenticated));
        expect(events[2].alias, equals('eventuser'));
      });
    });
    
    group('Error Handling', () {
      test('should handle user authentication errors properly', () async {
        final user = gun.user();
        
        // Try to authenticate non-existent user
        try {
          await user.auth('nonexistent', 'password');
          fail('Should have thrown UserException');
        } catch (e) {
          expect(e, isA<UserException>());
          expect(e.toString(), contains('User not found'));
        }
        
        // Create user and try wrong password
        await user.create('testuser', 'correctpass');
        await user.leave();
        
        try {
          await user.auth('testuser', 'wrongpass');
          fail('Should have thrown UserException');
        } catch (e) {
          expect(e, isA<UserException>());
          expect(e.toString(), contains('Invalid password'));
        }
      });
      
      test('should handle unauthenticated access attempts', () async {
        final user = gun.user();
        
        // Try to access user data without authentication
        try {
          user.data;
          fail('Should have thrown UserException');
        } catch (e) {
          expect(e, isA<UserException>());
          expect(e.toString(), contains('User not authenticated'));
        }
        
        try {
          await user.encrypt({'data': 'secret'});
          fail('Should have thrown UserException');
        } catch (e) {
          expect(e, isA<UserException>());
          expect(e.toString(), contains('User not authenticated'));
        }
      });
    });
  });
}
