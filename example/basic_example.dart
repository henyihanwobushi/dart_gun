import 'package:gun_dart/gun_dart.dart';

/// Basic example showing how to use Gun Dart
void main() async {
  print('Gun Dart Basic Example');
  
  // Create a new Gun instance
  final gun = Gun();
  
  // Store some data
  print('Storing user data...');
  await gun.get('users').get('alice').put({
    'name': 'Alice Smith',
    'age': 30,
    'email': 'alice@example.com',
  });
  
  // Retrieve the data
  print('Retrieving user data...');
  final userData = await gun.get('users').get('alice').once();
  print('Retrieved data: $userData');
  
  // Subscribe to changes (placeholder - not fully implemented yet)
  print('Setting up real-time listener...');
  gun.get('users').get('alice').on((data, key) {
    print('Data changed for $key: $data');
  });
  
  // Update the data
  print('Updating user age...');
  await gun.get('users').get('alice').put({
    'name': 'Alice Smith',
    'age': 31,
    'email': 'alice@example.com',
  });
  
  // Clean up
  await gun.close();
  print('Example completed.');
}
