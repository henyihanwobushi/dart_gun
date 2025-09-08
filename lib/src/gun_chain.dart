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
  GunChain map() {
    // TODO: Implement map functionality
    return this;
  }
  
  /// Set data (for sets/arrays)
  Future<GunChain> set(dynamic data, [Function? callback]) async {
    // TODO: Implement set functionality
    return put(data, callback);
  }
}
