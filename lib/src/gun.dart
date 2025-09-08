import 'dart:async';

import 'gun_chain.dart';
import 'storage/storage_adapter.dart';
import 'storage/memory_storage.dart';
import 'network/peer.dart';
import 'types/types.dart';
import 'types/events.dart';
import 'data/graph.dart';
import 'auth/user.dart';

/// Main Gun class - entry point for Gun Dart
/// 
/// This class provides the primary interface for interacting with the Gun
/// database, similar to the Gun constructor in Gun.js
class Gun {
  final StorageAdapter _storage;
  final List<Peer> _peers = [];
  final StreamController<GunEvent> _eventController = StreamController.broadcast();
  final Graph _graph = Graph();
  late final User _user;
  
  /// Creates a new Gun instance
  /// 
  /// [opts] - Configuration options including storage and peers
  Gun([GunOptions? opts]) 
      : _storage = opts?.storage ?? MemoryStorage() {
    if (opts?.peers != null) {
      _peers.addAll(opts!.peers!);
    }
    
    _user = User(this);
    _initializeGun();
  }
  
  /// Initialize the Gun instance
  void _initializeGun() {
    // Initialize storage
    _storage.initialize();
    
    // Connect to peers if any
    for (final peer in _peers) {
      peer.connect();
    }
  }
  
  /// Get a reference to a node by key
  /// 
  /// This is the primary method for accessing data in Gun
  /// Similar to gun.get(key) in Gun.js
  GunChain get(String key) {
    return GunChain(this, key);
  }
  
  /// Put data at the root level
  /// 
  /// [data] - The data to store
  /// [callback] - Optional callback for completion
  Future<void> put(Map<String, dynamic> data, [Function? callback]) async {
    try {
      await _storage.put('', data);
      _graph.putNode('', data);
      _eventController.add(GunEvent(
        type: GunEventType.put,
        key: '',
        data: data,
      ));
      callback?.call(null);
    } catch (error) {
      callback?.call(error);
      rethrow;
    }
  }
  
  /// Subscribe to all events on this Gun instance
  /// 
  /// [callback] - Function to call when events occur
  StreamSubscription<GunEvent> on(void Function(GunEvent) callback) {
    return _eventController.stream.listen(callback);
  }
  
  /// Add a peer to the network
  /// 
  /// [peer] - The peer to add
  void addPeer(Peer peer) {
    _peers.add(peer);
    peer.connect();
  }
  
  /// Get the current storage adapter
  StorageAdapter get storage => _storage;
  
  /// Get the list of current peers
  List<Peer> get peers => List.unmodifiable(_peers);
  
  /// Get the internal graph
  Graph get graph => _graph;
  
  /// Get the user authentication system
  User get user => _user;
  
  /// Get the event controller (for internal use by GunChain)
  StreamController<GunEvent> get eventController => _eventController;
  
  /// Close the Gun instance and clean up resources
  Future<void> close() async {
    await _eventController.close();
    await _storage.close();
    _graph.dispose();
    _user.dispose();
    
    for (final peer in _peers) {
      await peer.disconnect();
    }
  }
}
