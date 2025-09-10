import 'dart:async';

import 'gun_chain.dart';
import 'storage/storage_adapter.dart';
import 'storage/memory_storage.dart';
import 'network/peer.dart';
import 'network/gun_query.dart';
import 'network/relay_pool_manager.dart';
import 'network/gun_error_handler.dart';
import 'network/gun_wire_protocol.dart';
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
  final GunErrorHandler _errorHandler = GunErrorHandler();
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
    
    // Connect to peers and set up message handling
    for (final peer in _peers) {
      if (peer is WebSocketPeer) {
        // Listen for incoming Gun messages from this peer
        peer.gunMessages.listen((message) {
          _handlePeerMessage(message, peer);
        });
      }
      
      // Connect to peer (this is async but we don't await to allow parallel connections)
      peer.connect().catchError((error) {
        print('Gun: Failed to connect to peer ${peer.url}: $error');
      });
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
  
  /// Get a reference to a graph node by key
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
    
    // Set up message listener for WebSocket peers
    if (peer is WebSocketPeer) {
      peer.gunMessages.listen((message) {
        _handlePeerMessage(message, peer);
      });
    }
    
    // Connect to peer
    peer.connect().catchError((error) {
      print('Gun: Failed to connect to peer ${peer.url}: $error');
    });
  }
  
  /// Get the current storage adapter
  StorageAdapter get storage => _storage;
  
  /// Get the list of current peers
  List<Peer> get peers => List.unmodifiable(_peers);
  
  /// Get the internal graph
  Graph get graph => _graph;
  
  /// Get the user authentication system (Gun.js compatible method)
  User user() => _user;
  
  /// Get the event controller (for internal use by GunChain)
  StreamController<GunEvent> get eventController => _eventController;
  
  /// Get the query manager (for internal use by GunChain)
  GunQueryManager get queryManager => _queryManager;
  
  /// Get the error handler
  GunErrorHandler get errorHandler => _errorHandler;
  
  /// Get error stream
  Stream<GunError> get errors => _errorHandler.errors;
  
  /// Execute a graph query
  Future<GunQueryResult> executeQuery(GunQuery query) async {
    // Track the query for timeout and result handling
    _queryManager.trackQuery(query);
    
    // Create a completer to handle the async result
    final completer = Completer<GunQueryResult>();
    
    // Add a timeout to prevent tests from hanging
    Timer(const Duration(seconds: 5), () {
      if (!completer.isCompleted) {
        completer.complete(GunQueryResult(query: query, data: null));
      }
    });
    
    // Set up a callback to complete the future when we get a result
    final enhancedQuery = GunQuery(
      nodeId: query.nodeId,
      path: query.path,
      queryId: query.queryId,
      callback: (data, error) {
        if (!completer.isCompleted) {
          if (error != null) {
            completer.complete(GunQueryResult(query: query, error: error));
          } else {
            final result = GunQueryResult(query: query, data: data as Map<String, dynamic>?);
            // Note: enhancements (filter/map) are applied in GunChain after unflattening
            completer.complete(result);
          }
        }
      },
      filterFn: query.filterFn,
      mapFn: query.mapFn,
    );
    
    // Broadcast the query to relay servers first (if available)
    if (_relayPool != null) {
      try {
        await _relayPool!.sendGetQuery(query.nodeId, path: query.path);
      } catch (e) {
        // Ignore relay errors and continue with peers
        print('Gun: Relay query failed: $e');
      }
    }
    
    // Broadcast the query to all peers
    final wireQuery = enhancedQuery.toWireFormat();
    for (final peer in _peers) {
      if (peer.isConnected) {
        try {
          await peer.send(wireQuery);
        } catch (e) {
          // Ignore peer sending errors
          print('Gun: Peer query failed: $e');
        }
      }
    }
    
    // Also check local storage for immediate response
    final localData = await _getLocalData(enhancedQuery);
    if (localData != null) {
      // Note: enhancements (filter/map) are applied in GunChain after unflattening
      final localResult = GunQueryResult(query: enhancedQuery, data: localData);
      return localResult;
    }
    
    // If there is no network path available, return immediately with null data
    final hasConnectedPeers = _peers.any((p) => p.isConnected);
    final hasRelay = _relayPool != null;
    if (!hasConnectedPeers && !hasRelay) {
      return GunQueryResult(query: enhancedQuery, data: null);
    }
    
    // Return the future result (will be completed by network responses or timeout)
    return completer.future;
  }

  /// Get data from local storage for a query
  Future<Map<String, dynamic>?> _getLocalData(GunQuery query) async {
    final fullKey = query.fullPath.join('/');
    return await _storage.get(fullKey);
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
          orElse: () => _peers.isNotEmpty
              ? _peers.first
              : throw StateError('No peers available'),
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
  
  /// Handle incoming messages from peers
  Future<void> _handlePeerMessage(GunMessage message, Peer peer) async {
    try {
      switch (message.type) {
        case GunMessageType.put:
          await _handleIncomingPut(message, peer);
          break;
        case GunMessageType.get:
          await _handleIncomingGet(message, peer);
          break;
        case GunMessageType.hi:
        case GunMessageType.bye:
        case GunMessageType.dam:
        case GunMessageType.ok:
        case GunMessageType.unknown:
          // These are handled at the peer level or logged
          break;
      }
    } catch (e) {
      print('Gun: Error handling peer message: $e');
    }
  }
  
  /// Handle incoming PUT messages from peers (data synchronization)
  Future<void> _handleIncomingPut(GunMessage message, Peer peer) async {
    try {
      for (final entry in message.data.entries) {
        final nodeId = entry.key;
        final nodeData = entry.value;
        
        if (nodeData is Map<String, dynamic>) {
          print('Gun: Received PUT for node $nodeId from peer');
          
          // Get existing local data for HAM conflict resolution
          final existingData = await _storage.get(nodeId);
          
          // Merge with HAM logic
          final mergedData = _mergeWithHAM(existingData, nodeData, nodeId);
          
          if (mergedData != null) {
            // Store the merged data locally
            await _storage.put(nodeId, mergedData);
            
            // Update the graph
            _graph.putNode(nodeId, mergedData);
            
            // Emit event for subscribers (this enables real-time subscriptions!)
            _eventController.add(GunEvent(
              type: GunEventType.put,
              key: nodeId,
              data: mergedData,
            ));
          }
        }
      }
    } catch (e) {
      print('Gun: Error processing incoming PUT: $e');
    }
  }
  
  /// Handle incoming GET requests from peers
  Future<void> _handleIncomingGet(GunMessage message, Peer peer) async {
    try {
      final key = message.data['#'] as String?;
      if (key != null) {
        // Try to get the requested data from local storage
        final data = await _storage.get(key);
        if (data != null) {
          // Send the data back to the requesting peer
          await peer.send({
            'put': {key: data},
            '#': message.id, // Reply with the original message ID
          });
        }
      }
    } catch (e) {
      print('Gun: Error handling incoming GET: $e');
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
    // Use proper DAM message handling
    _errorHandler.handleDAM(message);
    
    // Also emit as Gun event for backward compatibility
    final error = message['dam'] as String?;
    if (error != null) {
      _eventController.add(GunEvent(
        type: GunEventType.error,
        key: '',
        data: message,
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
  
  /// Merge incoming data with existing data using HAM (Hypothetical Amnesia Machine) logic
  /// 
  /// This implements Gun.js compatible conflict resolution:
  /// - Field-level merging based on timestamps
  /// - Newer timestamps win
  /// - Missing timestamps are treated as very old
  Map<String, dynamic>? _mergeWithHAM(
    Map<String, dynamic>? existing, 
    Map<String, dynamic> incoming,
    String nodeId,
  ) {
    try {
      print('HAM: Merging data for node $nodeId');
      print('HAM: Existing data: $existing');
      print('HAM: Incoming data: $incoming');
      
      // If no existing data, accept incoming data
      if (existing == null) {
        print('HAM: No existing data, accepting incoming');
        return incoming;
      }
      
      // Extract HAM state (timestamps) from both datasets
      final existingMeta = existing['_'] as Map<String, dynamic>?;
      final incomingMeta = incoming['_'] as Map<String, dynamic>?;
      
      // Handle various timestamp formats from Gun.js
      final existingState = <String, num>{};
      final incomingState = <String, num>{};
      
      if (existingMeta?['>'] != null) {
        final stateData = existingMeta!['>'];
        if (stateData is Map) {
          for (final entry in stateData.entries) {
            if (entry.value is num) {
              existingState[entry.key] = entry.value;
            } else if (entry.value != null) {
              // Try to parse as number if it's a string
              final parsed = num.tryParse(entry.value.toString());
              if (parsed != null) {
                existingState[entry.key] = parsed;
              }
            }
          }
        }
      }
      
      if (incomingMeta?['>'] != null) {
        final stateData = incomingMeta!['>'];
        if (stateData is Map) {
          for (final entry in stateData.entries) {
            if (entry.value is num) {
              incomingState[entry.key] = entry.value;
            } else if (entry.value != null) {
              // Try to parse as number if it's a string
              final parsed = num.tryParse(entry.value.toString());
              if (parsed != null) {
                incomingState[entry.key] = parsed;
              }
            }
          }
        }
      }
      
      // Start with existing data
      final merged = Map<String, dynamic>.from(existing);
      final mergedState = Map<String, num>.from(existingState);
      
      // Process each field in the incoming data
      for (final entry in incoming.entries) {
        final field = entry.key;
        final incomingValue = entry.value;
        
        // Skip metadata field
        if (field == '_') continue;
        
        final incomingTimestamp = incomingState[field] ?? 0;
        final existingTimestamp = existingState[field] ?? 0;
        
        // HAM rule: newer timestamp wins, equal timestamps use lexical order
        // Also handle case where existing field doesn't exist (always accept incoming)
        bool shouldAccept;
        
        print('HAM: Field $field - existing ts: $existingTimestamp, incoming ts: $incomingTimestamp');
        print('HAM: Field $field - existing val: ${merged[field]}, incoming val: $incomingValue');
        
        if (incomingTimestamp > existingTimestamp) {
          shouldAccept = true; // Newer timestamp always wins
          print('HAM: Field $field - ACCEPT (newer timestamp)');
        } else if (incomingTimestamp < existingTimestamp) {
          shouldAccept = false; // Older timestamp always loses
          print('HAM: Field $field - REJECT (older timestamp)');
        } else if (!merged.containsKey(field)) {
          shouldAccept = true; // Field doesn't exist, accept incoming
          print('HAM: Field $field - ACCEPT (field does not exist)');
        } else {
          // Equal timestamps - use lexical ordering for deterministic conflict resolution
          final incomingStr = incomingValue?.toString() ?? '';
          final existingStr = merged[field]?.toString() ?? '';
          shouldAccept = incomingStr.compareTo(existingStr) > 0;
          print('HAM: Field $field - LEXICAL (equal timestamps): $shouldAccept');
        }
        
        if (shouldAccept) {
          print('HAM: Field $field - UPDATED to: $incomingValue');
          merged[field] = incomingValue;
          mergedState[field] = incomingTimestamp > 0 ? incomingTimestamp : DateTime.now().millisecondsSinceEpoch;
        } else {
          print('HAM: Field $field - KEPT existing: ${merged[field]}');
        }
      }
      
      // Also handle fields that exist in incoming metadata but not in data
      // This ensures all timestamp information is preserved
      for (final stateEntry in incomingState.entries) {
        final field = stateEntry.key;
        if (!mergedState.containsKey(field)) {
          mergedState[field] = stateEntry.value;
        }
      }
      
      // Update metadata with merged state
      merged['_'] = {
        '#': nodeId,
        '>': mergedState,
      };
      
      return merged;
      
    } catch (e) {
      print('Gun: Error in HAM merge: $e');
      // Fallback to incoming data if merge fails
      return incoming;
    }
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
    
    // Close error handler
    await _errorHandler.close();
    
    // Close event controller last
    await _eventController.close();
  }
}
