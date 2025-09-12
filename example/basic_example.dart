// This example demonstrates the core Gun Dart functionality
import 'dart:async';

import 'package:dart_gun/dart_gun.dart';

/// Basic example showing how to use Gun Dart
void main() async {
  print('🔫 Gun Dart Basic Example');
  print('=================================\n');
  print('This example demonstrates core Gun Dart features:');
  print('• Basic put/get operations');
  print('• Real-time subscriptions');
  print('• Graph relationships');
  print('• CRDT conflict resolution');
  print('• Storage operations\n');
  // Create a Gun instance with default memory storage
  print('Creating Gun instance...');
  final gun = Gun();
  
  // 1. Basic put/get operations
  print('\n📝 1. Basic put/get operations');
  await gun.get('users').get('alice').put({
    'name': 'Alice Smith',
    'age': 30,
    'email': 'alice@example.com',
  });
  
  final userData = await gun.get('users').get('alice').once();
  print('   Retrieved user data: ${userData?['name']} (${userData?['age']} years old)');
  
  // 2. Real-time subscriptions
  print('\n⚡ 2. Real-time subscriptions');
  final completer = Completer<void>();
  
  final subscription = gun.get('users').get('alice').on((data, key) {
    print('   🔄 Real-time update received: ${data?['name']} is now ${data?['age']} years old');
    if (!completer.isCompleted) completer.complete();
  });
  
  // Update the data to trigger the subscription
  print('   Updating Alice\'s age...');
  await gun.get('users').get('alice').put({
    'name': 'Alice Smith',
    'age': 31, // Updated age
    'email': 'alice@example.com',
  });
  
  // Wait for the real-time update
  await completer.future;
  await subscription.cancel();
  
  // 3. Working with multiple nodes
  print('\n🕸️ 3. Working with multiple nodes');
  
  // Create another user
  await gun.get('users').get('bob').put({
    'name': 'Bob Johnson',
    'age': 28,
    'city': 'New York',
  });
  
  final bobData = await gun.get('users').get('bob').once();
  print('   Created Bob: ${bobData?['name']} from ${bobData?['city']}');
  
  // 4. Storage operations
  print('\n💾 4. Storage operations');
  
  final aliceExists = await gun.storage.exists('users/alice');
  print('   Alice exists in storage: $aliceExists');
  
  // 5. CRDT conflict resolution (basic demonstration)
  print('\n🔀 5. CRDT conflict resolution');
  
  // Simulate concurrent updates to the same field
  await gun.get('counter').put({'value': 5});
  await gun.get('counter').put({'value': 7});
  final finalCounter = await gun.get('counter').once();
  print('   Counter after concurrent updates: ${finalCounter?['value']}');
  
  // 6. Utility functions
  print('\n🛠️ 6. Utility functions');
  
  final randomId = Utils.randomString(8);
  print('   Generated random ID: $randomId');
  
  // Clean up
  print('\n🧹 Cleaning up...');
  try {
    await gun.close();
    print('   Gun instance closed successfully');
  } catch (e) {
    print('   Note: Clean up completed (no explicit close needed)');
  }
  
  print('\n✅ Gun Dart basic example completed successfully!');
  print('\nNext steps:');
  print('  • Check out advanced_example.dart for more features');
  print('  • Try flutter_example.dart for Flutter widgets');
  print('  • Explore networking_example.dart for peer connections');
  
  print('\n🚪 Example finished.');
}
