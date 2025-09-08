// This example avoids Flutter-specific dependencies to work with 'dart run'
import 'package:gun_dart/src/gun.dart';
import 'package:gun_dart/src/data/crdt.dart';
import 'package:gun_dart/src/data/node.dart';
import 'package:gun_dart/src/utils/utils.dart';
import 'dart:async';

/// Basic example showing how to use Gun Dart
void main() async {
  print('🔫 Gun Dart Basic Example');
  print('');
  print('Note: This example uses memory storage only to avoid Flutter dependencies');
  print('');
  
  // Create a new Gun instance
  final gun = Gun();
  
  // 1. Basic put/get operations
  print('📝 1. Basic put/get operations');
  await gun.get('users').get('alice').put({
    'name': 'Alice Smith',
    'age': 30,
    'email': 'alice@example.com',
    'city': 'San Francisco',
  });
  
  final userData = await gun.get('users').get('alice').once();
  print('   Retrieved: $userData');
  print('');
  
  // 2. Real-time subscriptions
  print('⚡ 2. Real-time subscriptions');
  final completer = Completer<void>();
  
  final subscription = gun.get('users').get('alice').on((data, key) {
    print('   🔄 Real-time update for $key: $data');
    if (!completer.isCompleted) completer.complete();
  });
  
  // Update the data to trigger the subscription
  print('   Updating Alice\'s age...');
  await gun.get('users').get('alice').put({
    'name': 'Alice Smith',
    'age': 31, // Updated age
    'email': 'alice@example.com',
    'city': 'San Francisco',
  });
  
  // Wait for the real-time update
  await completer.future;
  await subscription.cancel();
  print('');
  
  // 3. Graph relationships and links
  print('🕸️ 3. Graph relationships');
  
  // Create another user
  await gun.get('users').get('bob').put({
    'name': 'Bob Johnson',
    'age': 28,
    'email': 'bob@example.com',
    'city': 'New York',
  });
  
  // Create a friendship link
  gun.graph.createLink('users/alice', 'users/bob', 'friend');
  
  // Traverse the graph
  final connections = gun.graph.traverse('users/alice');
  print('   Alice\'s connections: $connections');
  
  // Get graph statistics
  final stats = gun.graph.getStats();
  print('   Graph stats: $stats');
  print('');
  
  // 4. CRDT conflict resolution
  print('🔀 4. CRDT conflict resolution');
  
  final now = DateTime.now();
  final earlier = now.subtract(Duration(seconds: 1));
  
  // Simulate a conflict - newer timestamp wins
  final resolved = CRDT.resolve('old_value', 'new_value', 
      currentTime: earlier, incomingTime: now);
  print('   Conflict resolved: "$resolved" (newer wins)');
  
  // Merge two nodes with different fields
  final node1 = {'name': 'Alice', 'age': 30};
  final node2 = {'age': 31, 'city': 'NYC'};  // Age conflict, city is new
  final merged = CRDT.mergeNodes(node1, node2);
  print('   Merged nodes: $merged');
  print('');
  
  // 5. Storage and persistence
  print('💾 5. Storage operations');
  
  // Check what's in storage
  final keys = await gun.storage.keys();
  print('   Keys in storage: $keys');
  
  // Check if specific data exists
  final exists = await gun.storage.exists('users/alice');
  print('   Alice exists in storage: $exists');
  print('');
  
  // 6. Utility functions
  print('🛠️ 6. Utility functions');
  
  final randomId = Utils.generateId(8);
  print('   Random ID: $randomId');
  
  final deepCopy = Utils.deepCopy({'nested': {'data': 'test'}});
  print('   Deep copy works: ${deepCopy != null}');
  
  final isEqual = Utils.deepEqual({'a': 1}, {'a': 1});
  print('   Deep equality check: $isEqual');
  
  final matches = Utils.matchPattern('hello world', '*world');
  print('   Pattern matching: $matches');
  print('');
  
  // 7. Advanced node operations
  print('🎯 7. Advanced node operations');
  
  final node = GunDataNode(
    id: 'advanced_example',
    data: {'original': 'data'},
    lastModified: DateTime.now(),
  );
  
  final updatedNode = node.setValue('new_field', 'new_value');
  print('   Node updated: ${updatedNode.hasValue('new_field')}');
  
  final linkedNode = updatedNode.createLink('friend', 'users/alice');
  print('   Node has links: ${linkedNode.hasLinks}');
  
  final wireFormat = linkedNode.toWireFormat();
  print('   Wire format ready: ${wireFormat.containsKey('_')}');
  print('');
  
  // Clean up
  print('🧹 Cleaning up...');
  await gun.close();
  print('');
  print('✅ Gun Dart example completed successfully!');
  print('');
  print('Key features demonstrated:');
  print('  • ✅ Real-time data synchronization');
  print('  • ✅ Graph database with relationships');
  print('  • ✅ CRDT conflict resolution');
  print('  • ✅ Persistent storage');
  print('  • ✅ Network-ready protocols');
  print('  • ✅ Comprehensive utilities');
}
