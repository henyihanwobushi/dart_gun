import 'dart:async';
import 'gun.dart';
import 'types/types.dart';
import 'types/events.dart';

/// Represents a chainable reference to Gun data
/// Similar to Gun.js chain API
class GunChain {
  final Gun _gun;
  final String _key;
  final List<String> _path;
  
  GunChain(this._gun, this._key, [this._path = const []]);
  
  /// Get a child node by key
  GunChain get(String key) {
    return GunChain(_gun, key, [..._path, _key]);
  }
  
  /// Put data at this node
  Future<GunChain> put(dynamic data, [Function? callback]) async {
    try {
      final fullKey = [..._path, _key].join('/');
      Map<String, dynamic> dataMap;
      
      if (data is Map<String, dynamic>) {
        dataMap = data;
        await _gun.storage.put(fullKey, dataMap);
      } else {
        dataMap = {'_': data};
        await _gun.storage.put(fullKey, dataMap);
      }
      
      // Update the graph
      _gun.graph.putNode(fullKey, dataMap);
      
      // Emit event for subscribers
      _gun.eventController.add(GunEvent(
        type: GunEventType.put,
        key: fullKey,
        data: data,
      ));
      
      callback?.call(null);
      return this;
    } catch (error) {
      callback?.call(error);
      rethrow;
    }
  }
  
  /// Subscribe to changes on this node
  StreamSubscription on(GunListener listener) {
    final fullKey = [..._path, _key].join('/');
    
    // Listen to gun events and filter for our key
    return _gun.eventController.stream
        .where((event) => event.key == fullKey)
        .listen((event) {
      listener(event.data, event.key);
    });
  }
  
  /// Get data once from this node
  Future<dynamic> once([Function? callback]) async {
    try {
      final fullKey = [..._path, _key].join('/');
      final data = await _gun.storage.get(fullKey);
      callback?.call(data, null);
      return data;
    } catch (error) {
      callback?.call(null, error.toString());
      rethrow;
    }
  }
  
  /// Map over a set of data
  /// 
  /// Iterates over child nodes and calls the provided callback for each.
  /// This is useful for working with collections of data.
  Future<List<MapEntry<String, dynamic>>> map([Function? callback]) async {
    final fullKey = [..._path, _key].join('/');
    final results = <MapEntry<String, dynamic>>[];
    
    try {
      // Get all keys that start with our path
      final allKeys = await _gun.storage.keys();
      final childKeys = allKeys
          .where((key) => key.startsWith('$fullKey/'))
          .map((key) => key.substring('$fullKey/'.length))
          .where((subKey) => !subKey.contains('/')) // Only direct children
          .toList();
      
      // Process each child
      for (final childKey in childKeys) {
        final childData = await _gun.storage.get('$fullKey/$childKey');
        if (childData != null) {
          final entry = MapEntry(childKey, childData);
          results.add(entry);
          callback?.call(childData, childKey);
        }
      }
    } catch (error) {
      callback?.call(null, error);
    }
    
    return results;
  }
  
  /// Set data (for sets/arrays)
  /// 
  /// Adds data to a set-like structure using a unique key.
  /// Unlike put(), set() generates unique keys for each item.
  Future<GunChain> set(dynamic data, [Function? callback]) async {
    try {
      final fullKey = [..._path, _key].join('/');
      
      // Generate a unique key for this set item
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final random = (timestamp * 1000 + (data.hashCode & 0xFFFF)) & 0xFFFFFFFF;
      final uniqueKey = '$fullKey/${random.toRadixString(36)}';
      
      Map<String, dynamic> dataMap;
      if (data is Map<String, dynamic>) {
        dataMap = data;
      } else {
        dataMap = {'_': data};
      }
      
      // Store the data with the unique key
      await _gun.storage.put(uniqueKey, dataMap);
      
      // Update the graph
      _gun.graph.putNode(uniqueKey, dataMap);
      
      // Create a reference in the parent to maintain set structure
      final setRef = {'#': uniqueKey};
      final parentKey = [..._path, _key].join('/');
      final existing = await _gun.storage.get(parentKey) ?? <String, dynamic>{};
      
      // Add to the set structure
      existing[random.toRadixString(36)] = setRef;
      await _gun.storage.put(parentKey, existing);
      
      // Emit event for subscribers
      _gun.eventController.add(GunEvent(
        type: GunEventType.put,
        key: uniqueKey,
        data: data,
      ));
      
      callback?.call(null);
      return this;
    } catch (error) {
      callback?.call(error);
      rethrow;
    }
  }
}
