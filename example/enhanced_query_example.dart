import 'package:dart_gun/dart_gun.dart';

void main() async {
  // Create a Gun instance
  final gun = Gun();

  print('=== Gun Dart Enhanced Query Example ===\n');

  // Add some sample data
  await gun.get('users').put({
    'alice': {
      'name': 'Alice',
      'age': 25,
      'role': 'admin',
      'active': true,
    },
    'bob': {
      'name': 'Bob',
      'age': 30,
      'role': 'user',
      'active': true,
    },
    'charlie': {
      'name': 'Charlie',
      'age': 22,
      'role': 'user',
      'active': false,
    },
  });

  print('1. Basic query (all users):');
  final allUsers = await gun.get('users').once();
  print(allUsers);
  print('');

  print('2. Filter query (only active users):');
  final activeUsers = await gun.get('users').filter((user, key) {
    return user['active'] == true;
  }).once();
  print(activeUsers);
  print('');

  print('3. Map query (user names only):');
  final userNames = await gun.get('users').map((user, key) {
    return {'name': user['name']};
  }).once();
  print(userNames);
  print('');

  print('4. Filter and map query (names of admin users):');
  final adminNames = await gun
      .get('users')
      .filter((user, key) => user['role'] == 'admin')
      .map((user, key) => {'name': user['name'], 'role': user['role']})
      .once();
  print(adminNames);
  print('');

  print('5. Complex filter (users over 25):');
  final olderUsers = await gun.get('users').filter((user, key) {
    return user['age'] > 25;
  }).once();
  print(olderUsers);
  print('');

  print('Example completed.');
}
