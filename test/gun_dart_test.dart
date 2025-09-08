import 'package:flutter_test/flutter_test.dart';
import 'package:gun_dart/gun_dart.dart';

void main() {
  group('Gun Dart Tests', () {
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
    });
    
    test('should store and retrieve data', () async {
      final testData = {'name': 'Test User', 'value': 42};
      
      // Store data
      await gun.get('test').put(testData);
      
      // Retrieve data
      final retrieved = await gun.get('test').once();
      expect(retrieved, equals(testData));
    });
    
    test('should handle nested data paths', () async {
      final testData = {'info': 'nested data'};
      
      // Store nested data
      await gun.get('users').get('testuser').put(testData);
      
      // Retrieve nested data
      final retrieved = await gun.get('users').get('testuser').once();
      expect(retrieved, equals(testData));
    });
    
    test('should return null for non-existent keys', () async {
      final retrieved = await gun.get('nonexistent').once();
      expect(retrieved, isNull);
    });
  });
}
