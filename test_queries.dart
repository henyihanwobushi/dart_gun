#!/usr/bin/env dart

import 'lib/gun_dart.dart';

Future<void> main() async {
  print('Gun Dart Query Feature Test\n' + '=' * 30);
  
  try {
    // Create Gun instance with in-memory storage
    final gun = Gun(GunOptions(storage: MemoryStorage()));
    
    print('🔧 Creating sample data...');
    
    // Add sample users data
    await gun.get('users').get('user1').put({
      'name': 'Alice',
      'age': 25,
      'role': 'admin',
      'active': true,
    });
    
    await gun.get('users').get('user2').put({
      'name': 'Bob',
      'age': 30,
      'role': 'user',
      'active': true,
    });
    
    await gun.get('users').get('user3').put({
      'name': 'Charlie',
      'age': 20,
      'role': 'user',
      'active': false,
    });
    
    await gun.get('users').get('user4').put({
      'name': 'Diana',
      'age': 35,
      'role': 'admin',
      'active': true,
    });
    
    // Give it a moment for data to be stored
    await Future.delayed(Duration(milliseconds: 100));
    
    print('✅ Sample data created\n');
    
    // Test 1: Basic query to get all users
    print('🔍 Test 1: Basic query - all users');
    final allUsers = await gun.get('users').once();
    print('All users: ${allUsers?.toString() ?? 'null'}\n');
    
    // Test 2: Filter query - only active users
    print('🔍 Test 2: Filter query - active users only');
    final activeUsers = await gun.get('users').filter((key, value) {
      if (value is Map<String, dynamic>) {
        return value['active'] == true;
      }
      return false;
    }).once();
    print('Active users: ${activeUsers?.toString() ?? 'null'}\n');
    
    // Test 3: Map query - extract user names
    print('🔍 Test 3: Map query - extract names only');
    final userNames = await gun.get('users').map((key, value) {
      if (value is Map<String, dynamic>) {
        return {'name': value['name']};
      }
      return null;
    }).once();
    print('User names: ${userNames?.toString() ?? 'null'}\n');
    
    // Test 4: Chained query - filter admin users, then extract names
    print('🔍 Test 4: Chained query - admin users names');
    final adminNames = await gun.get('users')
      .filter((key, value) {
        if (value is Map<String, dynamic>) {
          return value['role'] == 'admin';
        }
        return false;
      })
      .map((key, value) {
        if (value is Map<String, dynamic>) {
          return {'name': value['name']};
        }
        return null;
      })
      .once();
    print('Admin names: ${adminNames?.toString() ?? 'null'}\n');
    
    // Test 5: Complex filter - users over 25
    print('🔍 Test 5: Complex filter - users over 25');
    final olderUsers = await gun.get('users').filter((key, value) {
      if (value is Map<String, dynamic> && value['age'] is int) {
        return value['age'] > 25;
      }
      return false;
    }).once();
    print('Users over 25: ${olderUsers?.toString() ?? 'null'}\n');
    
    print('✅ All query tests completed successfully!');
    
  } catch (e, stackTrace) {
    print('❌ Error during testing: $e');
    print('Stack trace: $stackTrace');
  }
}
