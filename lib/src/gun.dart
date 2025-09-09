import 'dart:async';

import 'gun_chain.dart';
import 'storage/storage_adapter.dart';
import 'storage/memory_storage.dart';
import 'network/peer.dart';
import 'network/gun_query.dart';
import 'network/relay_pool_manager.dart';
import 'types/types.dart';
import 'types/events.dart';
import 'data/graph.dart';
import 'data/metadata_manager.dart';
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
  RelayPoolManager? _relayPool;
  late final User _user;
  
  /// Creates a new Gun instance
  /// 
  /// [opts] - Configuration options including storage, peers, and relays
  Gun([GunOptions? opts]) 
      : _storage = opts?.storage ?? MemoryStorage() {
    if (opts?.peers != null) {
      _peers.addAll(opts!.peers!);
    }
    
    // Initialize relay pool if relay servers are provided
    if (opts?.relayServers != null && opts!.relayServers!.isNotEmpty) {
      _relayPool = RelayPoolManager(RelayPoolConfig(
        seedRelays: opts.relayServers!,
        maxConnections: opts.maxRelayConnections ?? 5,
        minConnections: opts.minRelayConnections ?? 1,
        loadBalancing: opts.relayLoadBalancing ?? LoadBalancingStrategy.healthBased,
        autoDiscovery: opts.enableRelayDiscovery ?? true,
      ));
    }
    
    _user = User(this);
    _initializeGun();
  }
  
  /// Initialize the Gun instance
  void _initializeGun() async {
    // Initialize storage
    await _storage.initialize();
    
    // Connect to peers if any
    for (final peer in _peers) {
      peer.connect();
    }
    
    // Start relay pool if configured
    if (_relayPool != null) {
      await _relayPool!.start();
      
      // Set up relay message handling
      _relayPool!.messages.listen((message) {
        _handleRelayMessage(message);
      });
      
      // Set up relay event handling
      _relayPool!.events.listen((event) {
        _handleRelayEvent(event);
      });
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
      // Storage adapter will handle metadata automatically
      await _storage.put('', data);
      
      // Add metadata for the graph as well (if not already present)
      final nodeData = MetadataManager.isValidNode(data) 
          ? data 
          : MetadataManager.addMetadata(
              nodeId: MetadataManager.generateNodeId(''),
              data: data,
            );
            
      _graph.putNode('', nodeData);
      _eventController.add(GunEvent(
        type: GunEventType.put,
        key: '',
        data: nodeData,
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
      
      // If we have local data or network is disabled, return immediately
      if (localData != null || !useNetwork) {
        final result = GunQueryResult(
          query: query,
          data: localData,
        );
        
        _queryManager.handleResult(query.queryId, result);
        return result;
      }
      
      // Send query to relay servers first (if available)
      if (_relayPool != null) {
        try {
          await _relayPool!.sendGetQuery(query.nodeId, path: query.path);
        } catch (e) {
          // Relay query failed, continue with peers
        }
      }
      
      // Send query to peers if no local data and network is enabled
      final wireMessage = query.toWireFormat();
      
      for (final peer in _peers) {
        if (peer.isConnected) {
          await peer.send(wireMessage);
        }
      }
      
      // Return result with local data (null is valid in Gun.js)
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
  
  /// Get relay pool manager (if configured)
  RelayPoolManager? get relayPool => _relayPool;
  
  /// Get relay statistics
  Map<String, dynamic>? get relayStats => _relayPool?.stats;
  
  /// Add a relay server to the pool
  Future<bool> addRelay(String url) async {
    if (_relayPool == null) {
      // Initialize relay pool if not already done
      _relayPool = RelayPoolManager(RelayPoolConfig(
        seedRelays: [],
        maxConnections: 5,
        minConnections: 1,
      ));
      await _relayPool!.start();
      
      // Set up message and event handling
      _relayPool!.messages.listen(_handleRelayMessage);
      _relayPool!.events.listen(_handleRelayEvent);
    }
    
    return await _relayPool!.addRelay(url);
  }
  
  /// Remove a relay server from the pool
  Future<void> removeRelay(String url) async {
    if (_relayPool != null) {
      await _relayPool!.removeRelay(url);
    }
  }
  
  /// Handle incoming messages from relay servers
  void _handleRelayMessage(Map<String, dynamic> message) {
    try {
      // Handle different message types
      if (message.containsKey('put')) {
        _handleRelayPutMessage(message);
      } else if (message.containsKey('get')) {
        _handleRelayGetMessage(message);
      } else if (message.containsKey('dam')) {
        _handleRelayErrorMessage(message);
      }
    } catch (e) {
      // Ignore malformed messages
    }
  }
  
  /// Handle put messages from relay servers
  void _handleRelayPutMessage(Map<String, dynamic> message) async {
    final putData = message['put'] as Map<String, dynamic>?;
    if (putData == null) return;
    
    for (final entry in putData.entries) {
      final nodeId = entry.key;
      final nodeData = entry.value as Map<String, dynamic>;
      
      // Store the data locally
      await _storage.put(nodeId, nodeData);
      
      // Update the graph
      _graph.putNode(nodeId, nodeData);
      
      // Emit event
      _eventController.add(GunEvent(
        type: GunEventType.put,
        key: nodeId,
        data: nodeData,
      ));
    }
  }
  
  /// Handle get messages from relay servers
  void _handleRelayGetMessage(Map<String, dynamic> message) async {
    // Relay servers typically don't send get messages to clients
    // This would be used if we were acting as a relay server ourselves
  }
  
  /// Handle error messages from relay servers
  void _handleRelayErrorMessage(Map<String, dynamic> message) {
    final error = message['dam'] as String?;
    if (error != null) {
      // Emit error event
      _eventController.add(GunEvent(
        type: GunEventType.error,
        key: '',
        data: {'error': error},
      ));
    }
  }
  
  /// Handle relay server events
  void _handleRelayEvent(RelayPoolEvent event) {
    // Forward relay events as Gun events
    _eventController.add(GunEvent(
      type: GunEventType.network,
      key: event.relayUrl ?? '',
      data: event.toMap(),
    ));
  }
  
  /// Close the Gun instance and clean up resources
  Future<void> close() async {
    // Close relay pool first
    if (_relayPool != null) {
      await _relayPool!.close();
      _relayPool = null;
    }
    
    // Close all peers
    for (final peer in _peers) {
      await peer.disconnect();
      await peer.close();
    }
    _peers.clear();
    
    // Close storage and other components
    await _storage.close();
    _graph.dispose();
    await _user.dispose();
    _queryManager.clear();
    
    // Close event controller last
    await _eventController.close();
  }
}
