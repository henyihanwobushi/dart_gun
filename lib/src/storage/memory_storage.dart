import 'dart:async';
import 'storage_adapter.dart';
import '../data/metadata_manager.dart';

/// In-memory storage adapter for Gun Dart
/// Useful for testing and temporary data
class MemoryStorage implements StorageAdapter {
  final Map<String, Map<String, dynamic>> _data = {};
  bool _initialized = false;
  
  @override
  Future<void> initialize() async {
    _initialized = true;
  }
  
  @override
  Future<void> put(String key, Map<String, dynamic> data) async {
    _ensureInitialized();
    
    // Get existing data for metadata merging
    final existing = _data[key];
    
    Map<String, dynamic> nodeData;
    if (MetadataManager.isValidNode(data)) {
      // Data already has valid metadata
      if (existing != null && MetadataManager.isValidNode(existing)) {
        // Merge with existing data using HAM conflict resolution
        nodeData = MetadataManager.mergeNodes(existing, data);
      } else {
        nodeData = data;
      }
    } else {
      // Add metadata to raw data
      final nodeId = MetadataManager.generateNodeId(key);
      nodeData = MetadataManager.addMetadata(
        nodeId: nodeId,
        data: data,
        existingMetadata: existing != null ? MetadataManager.extractMetadata(existing) : null,
      );
    }
    
    _data[key] = Map.from(nodeData);
  }
  
  @override
  Future<Map<String, dynamic>?> get(String key) async {
    _ensureInitialized();
    return _data[key] != null ? Map.from(_data[key]!) : null;
  }
  
  @override
  Future<void> delete(String key) async {
    _ensureInitialized();
    _data.remove(key);
  }
  
  @override
  Future<bool> exists(String key) async {
    _ensureInitialized();
    return _data.containsKey(key);
  }
  
  @override
  Future<List<String>> keys([String? pattern]) async {
    _ensureInitialized();
    if (pattern == null) {
      return _data.keys.toList();
    }
    // Simple pattern matching (could be enhanced with regex)
    return _data.keys.where((key) => key.contains(pattern)).toList();
  }
  
  @override
  Future<void> clear() async {
    _ensureInitialized();
    _data.clear();
  }
  
  @override
  Future<void> close() async {
    _data.clear();
    _initialized = false;
  }
  
  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('MemoryStorage not initialized. Call initialize() first.');
    }
  }
}
