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
      if (data is Map<String, dynamic>) {
        await _gun._storage.put(fullKey, data);
      } else {
        await _gun._storage.put(fullKey, {'_': data});
      }
      callback?.call(null);
      return this;
    } catch (error) {
      callback?.call(error);
      rethrow;
    }
  }
  
  /// Subscribe to changes on this node
  StreamSubscription on(GunListener listener) {
    // TODO: Implement real-time subscription
    return Stream.empty().listen((_) {});
  }
  
  /// Get data once from this node
  Future<dynamic> once([Function? callback]) async {
    try {
      final fullKey = [..._path, _key].join('/');
      final data = await _gun._storage.get(fullKey);
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
