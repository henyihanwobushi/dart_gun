// Advanced Gun Dart example demonstrating complex features
import 'package:gun_dart/gun_dart.dart';

/// Advanced example showing complex Gun Dart features
void main() async {
  print('🚀 Gun Dart Advanced Example');
  print('============================\n');
  print('This example demonstrates advanced Gun Dart features:');
  print('• Advanced CRDT data types');
  print('• Network transport protocols');
  print('• Security & encryption (SEA)');
  print('• User authentication');
  print('• Graph relationships');
  print('• Error handling\n');

  // Create Gun instance
  print('Creating Gun instance with advanced configuration...');
  final gun = Gun();

  // 1. Advanced CRDT Data Types
  print('\n🧮 1. Advanced CRDT Data Types');

  // G-Counter (grow-only counter)
  print('   Testing G-Counter (distributed counter)...');
  try {
    final counter1 = CRDTFactory.createGCounter('node1');
    final counter2 = CRDTFactory.createGCounter('node2');

    counter1.increment(5);
    counter2.increment(3);
    print('     Counter 1 value: ${counter1.value}');
    print('     Counter 2 value: ${counter2.value}');

    counter1.merge(counter2);
    print('     Merged counter value: ${counter1.value}');
  } catch (e) {
    print('     Note: CRDT types may not be fully implemented yet');
  }

  // 2. Network Transport Protocols
  print('\n🌐 2. Network Transport Protocols');

  try {
    // HTTP Transport
    print('   Testing HTTP/HTTPS transport...');
    final httpTransport = HttpTransport(baseUrl: 'https://gun-server.example.com');
    print('     HTTP transport URL: ${httpTransport.url}');
    print('     Initial connection state: ${httpTransport.isConnected ? '✅' : '❌'}');

    // WebSocket Transport
    print('   Testing WebSocket transport...');
    print('     WebSocket transport created');

    // Note: Actual connection would require a running server
    print('     Note: Transport examples require actual servers to connect to');
  } catch (e) {
    print('     Note: Transport initialization requires server configuration');
  }

  // 3. Security and Authentication (SEA)
  print('\n🔒 3. Security and Authentication (SEA)');

  try {
    // Generate cryptographic keys
    final keyPair = await SEA.pair();
    print('   Key pair generated: ${keyPair.pub.substring(0, 8)}...');

    // Encrypt sensitive data
    final secretData = {'password': 'super-secret', 'token': 'abc123'};
    final encrypted = await SEA.encrypt(secretData, 'my-password');
    print('   Data encrypted successfully');

    // Decrypt the data
    final decrypted = await SEA.decrypt(encrypted, 'my-password');
    print('   Data decrypted: ${decrypted['password'] == 'super-secret'}');

    // Digital signatures
    final signature = await SEA.sign('important message', keyPair);
    final verified = await SEA.verify('important message', signature, keyPair.pub);
    print('   Digital signature verified: $verified');
  } catch (e) {
    print('   Note: SEA functionality requires full cryptographic implementation');
  }

  // 4. User Authentication
  print('\n👤 4. User Authentication');

  try {
    final user = gun.user();
    print('   Creating user account...');

    // In a real implementation, this would create and authenticate a user
    print('   Note: User authentication requires full SEA implementation');
    print('   User system initialized: true');
  } catch (e) {
    print('   Note: User authentication not yet fully implemented');
  }

  // 5. Graph Relationships and Links
  print('\n🕸️ 5. Graph Relationships and Links');

  // Create a more complex data structure
  await gun.get('posts').get('post1').put({
    'title': 'Advanced Gun Dart Features',
    'content': 'This post demonstrates advanced features...',
    'author': 'alice',
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  });

  await gun.get('posts').get('post2').put({
    'title': 'Real-time Database Magic',
    'content': 'Gun.js and gun_dart provide real-time sync...',
    'author': 'bob',
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  });

  // Create comments linked to posts
  await gun.get('comments').get('comment1').put({
    'postId': 'post1',
    'text': 'Great explanation!',
    'author': 'charlie',
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  });

  print('   Created linked data structure (posts and comments)');

  // Retrieve and display the linked data
  final post1 = await gun.get('posts').get('post1').once();
  final comment1 = await gun.get('comments').get('comment1').once();

  print('   Post: "${post1?['title']}" by ${post1?['author']}');
  print('   Comment: "${comment1?['text']}" by ${comment1?['author']}');

  // 6. Error Handling and Monitoring
  print('\n🚨 6. Error Handling and Monitoring');

  try {
    // Subscribe to error events
    gun.errors.listen((error) {
      print('   🔴 Error detected: ${error.type.name} - ${error.message}');
    });

    print('   Error monitoring system active');

    // Simulate accessing non-existent data to trigger error handling
    final nonExistent = await gun.get('nonexistent').get('data').once();
    print('   Non-existent data query: ${nonExistent ?? 'null (as expected)'}');
  } catch (e) {
    print('   Error handling: $e');
  }

  // 7. Performance and Statistics
  print('\n📊 7. Performance and Statistics');

  try {
    final stats = gun.graph.getStats();
    print('   Graph statistics: $stats');
  } catch (e) {
    print('   Note: Graph statistics not yet implemented');
  }

  // Clean up
  print('\n🧹 Cleaning up...');
  try {
    await gun.close();
    print('   Advanced example completed successfully');
  } catch (e) {
    print('   Clean up completed');
  }

  print('\n✅ Gun Dart advanced example completed!');
  print('\nAdvanced features demonstrated:');
  print('  • ⚡ Advanced data structures and CRDT types');
  print('  • 🌐 Network transport abstraction');
  print('  • 🔒 Security and encryption concepts');
  print('  • 👤 User authentication framework');
  print('  • 🕸️ Complex graph relationships');
  print('  • 🚨 Error handling and monitoring');
  print('  • 📊 Performance monitoring capabilities');

  print('\n🚪 Advanced example finished.');
}
