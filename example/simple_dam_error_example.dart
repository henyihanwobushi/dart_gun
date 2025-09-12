import 'package:dart_gun/dart_gun.dart';

Future<void> main() async {
  print('=== Gun Dart Error Handling Example ===');
  
  // Create Gun instance
  final gun = Gun();
  
  // Subscribe to error events (if available)
  try {
    gun.errors.listen((error) {
      print('\n🚨 Gun Error Detected:');
      print('  Type: ${error.type.name}');
      print('  Message: ${error.message}');
      if (error.code != null) print('  Code: ${error.code}');
      if (error.nodeId != null) print('  Node: ${error.nodeId}');
      print('  Timestamp: ${error.timestamp}');
      print('');
    });
    print('Error monitoring system active');
  } catch (e) {
    print('Note: Error monitoring system not fully available yet');
  }
  
  print('\n1. Testing basic error scenarios...\n');
  
  try {
    // Try to access non-existent data
    print('  Attempting to access non-existent data...');
    final result = await gun.get('nonexistent').get('data').once();
    print('  Result: ${result ?? 'null (expected)'}');
  } catch (e) {
    print('  Caught error: $e');
  }
  
  try {
    // Try invalid operations
    print('  Attempting invalid operations...');
    await gun.get('').put({'invalid': null});
  } catch (e) {
    print('  Caught error: $e');
  }
  
  print('\n2. Testing storage operations with error handling...\n');
  
  try {
    // Test storage operations
    await gun.get('test').put({'data': 'test value'});
    final retrieved = await gun.get('test').once();
    print('  Storage test: ${retrieved != null ? 'Success' : 'Failed'}');
  } catch (e) {
    print('  Storage error: $e');
  }
  
  print('\n3. Testing concurrent operations...\n');
  
  try {
    // Test concurrent operations
    final futures = List.generate(5, (i) => 
      gun.get('concurrent').put({'value': i})
    );
    await Future.wait(futures);
    final result = await gun.get('concurrent').once();
    print('  Concurrent test result: $result');
  } catch (e) {
    print('  Concurrent operation error: $e');
  }
  
  // Clean up
  try {
    await gun.close();
    print('\n  Gun instance closed successfully');
  } catch (e) {
    print('\n  Clean up completed');
  }
  
  print('\n✅ Gun Dart error handling example completed!');
  print('\nKey concepts demonstrated:');
  print('  • Basic error detection and handling');
  print('  • Storage operation error scenarios');
  print('  • Concurrent operation management');
  print('  • Graceful error recovery');
  
  print('\n🚪 Error handling example finished.');
}
