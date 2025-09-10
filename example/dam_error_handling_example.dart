import 'package:gun_dart/gun_dart.dart';

Future<void> main() async {
  print('=== Gun Dart Error Handling Demo ===');
  
  // Create Gun instance
  final gun = Gun();
  
  // Subscribe to error events if available
  try {
    gun.errors.listen((error) {
      print('\n🚨 Gun Error Detected:');
      print('  Type: ${error.type.name}');
      print('  Message: ${error.message}');
      if (error.code != null) print('  Code: ${error.code}');
      print('  Timestamp: ${error.timestamp}');
      print('');
    });
    print('Error monitoring active');
  } catch (e) {
    print('Error monitoring not available yet');
  }
  
  print('\n1. Testing basic data operations with error handling...\n');
  
  try {
    // Test basic operations
    await gun.get('users').get('alice').put({
      'name': 'Alice',
      'email': 'alice@example.com'
    });
    print('  ✅ Data stored successfully');
    
    final userData = await gun.get('users').get('alice').once();
    print('  ✅ Data retrieved: ${userData?['name']}');
  } catch (e) {
    print('  ❌ Error in basic operations: $e');
  }
  
  print('\n2. Testing error scenarios...\n');
  
  try {
    // Test with potentially problematic data
    await gun.get('').put({'empty_key': 'test'});
  } catch (e) {
    print('  ❌ Caught expected error: ${e.toString().substring(0, 50)}...');
  }
  
  print('\n3. Testing network simulation...\n');
  
  // Simulate network operations (these may not work without actual peers)
  try {
    print('  Attempting network operations...');
    // This would normally connect to peers
    print('  Note: Network operations require actual peer connections');
  } catch (e) {
    print('  Network simulation error: $e');
  }
  
  // Clean up
  try {
    await gun.close();
    print('\n✅ Example completed successfully');
  } catch (e) {
    print('\n✅ Example completed');
  }
}

