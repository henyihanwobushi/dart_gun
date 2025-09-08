import 'dart:async';

/// Abstract storage adapter interface for Gun Dart
abstract class StorageAdapter {
  /// Initialize the storage adapter
  Future<void> initialize();
  
  /// Store data at the given key
  Future<void> put(String key, Map<String, dynamic> data);
  
  /// Retrieve data for the given key
  Future<Map<String, dynamic>?> get(String key);
  
  /// Delete data at the given key
  Future<void> delete(String key);
  
  /// Check if key exists
  Future<bool> exists(String key);
  
  /// Get all keys matching a pattern
  Future<List<String>> keys([String? pattern]);
  
  /// Clear all data
  Future<void> clear();
  
  /// Close the storage adapter
  Future<void> close();
}
