import 'dart:async';

import 'gun_chain.dart';
import 'storage/storage_adapter.dart';
import 'storage/memory_storage.dart';
import 'network/peer.dart';
import 'network/gun_query.dart';
import 'types/types.dart';
import 'types/events.dart';
import 'data/graph.dart';
import 'auth/user.dart';
import 'utils/utils.dart';

/// Main Gun class - entry point for Gun Dart
/// 
/// This class provides the primary interface for interacting with the Gun
/// database, similar to the Gun constructor in Gun.js
class Gun {
  final StorageAdapter _storage;
  final List<Peer> _peers = [];
  final StreamController<GunEvent> _eventController = StreamController.broadcast();
  final Graph _graph = Graph();
  final GunQueryManager _queryManager = GunQueryManager();
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
  
  /// Get the query manager (for internal use by GunChain)
  GunQueryManager get queryManager => _queryManager;
  
  /// Execute a graph query
  Future<GunQueryResult> executeQuery(GunQuery query, {bool useNetwork = true}) async {
    try {
      // Track the query
      _queryManager.trackQuery(query);
      
      // First, try local storage
      final localData = await _tryLocalQuery(query);
      
      // Always return result with local data (even if null)
      // In Gun.js, null/undefined is a valid response meaning "no data"
      if (!useNetwork || _peers.isEmpty) {
        final result = GunQueryResult(
          query: query,
          data: localData,
        );
        
        _queryManager.handleResult(query.queryId, result);
        return result;
      }
      
      // Send query to peers if no local data and network is enabled
      final wireMessage = query.toWireFormat();
      
      for (final peer in _peers) {
        if (peer.isConnected) {
          await peer.send(wireMessage);
        }
      }
      
      // For now, return local result (peer responses will be handled via message system)
      final result = GunQueryResult(
        query: query,
        data: localData,
      );
      
      _queryManager.handleResult(query.queryId, result);
      return result;
      
    } catch (error) {
      final result = GunQueryResult(
        query: query,
        error: error.toString(),
      );
      
      _queryManager.handleResult(query.queryId, result);
      return result;
    }
  }
  
  /// Try to resolve query from local storage
  Future<Map<String, dynamic>?> _tryLocalQuery(GunQuery query) async {
    try {
      final targetKey = query.fullPath.join('/');
      return await _storage.get(targetKey);
    } catch (e) {
      return null;
    }
  }
  
  /// Handle incoming query from peer
  Future<void> handleIncomingQuery(GunQuery query, String peerId) async {
    try {
      // Try to resolve the query locally
      final data = await _tryLocalQuery(query);
      
      if (data != null) {
        // Send response back to the peer
        final response = {
          'put': {query.targetNodeId: data},
          '#': query.queryId, // Acknowledge the query
          '@': Utils.randomString(8),
        };
        
        // Find the peer and send response
        final peer = _peers.firstWhere(
          (p) => p.url.contains(peerId),
          orElse: () => _peers.isNotEmpty ? _peers.first : throw StateError('No peers available'),
        );
        
        if (peer.isConnected) {
          await peer.send(response);
        }
      }
    } catch (e) {
      // Could not resolve query - send DAM (error) message
      final errorResponse = {
        'dam': 'Could not resolve query: ${e.toString()}',
        '#': query.queryId,
        '@': Utils.randomString(8),
      };
      
      try {
        final peer = _peers.first;
        if (peer.isConnected) {
          await peer.send(errorResponse);
        }
      } catch (_) {
        // Ignore peer sending errors
      }
    }
  }
  
  /// Close the Gun instance and clean up resources
  Future<void> close() async {
    await _eventController.close();
    await _storage.close();
    _graph.dispose();
    _user.dispose();
    _queryManager.clear();
    
    for (final peer in _peers) {
      await peer.disconnect();
    }
  }
}
