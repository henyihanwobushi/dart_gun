import 'dart:async';
import 'dart:math';
import 'gun_relay_client.dart';
import '../utils/utils.dart';

/// Load balancing strategy for relay servers
enum LoadBalancingStrategy {
  roundRobin,
  leastConnections,
  random,
  healthBased,
}

/// Relay server pool configuration
class RelayPoolConfig {
  final List<String> seedRelays;
  final int maxConnections;
  final int minConnections;
  final LoadBalancingStrategy loadBalancing;
  final Duration healthCheckInterval;
  final Duration connectionTimeout;
  final bool autoDiscovery;
  final int maxRetries;
  
  const RelayPoolConfig({
    required this.seedRelays,
    this.maxConnections = 10,
    this.minConnections = 2,
    this.loadBalancing = LoadBalancingStrategy.healthBased,
    this.healthCheckInterval = const Duration(minutes: 1),
    this.connectionTimeout = const Duration(seconds: 10),
    this.autoDiscovery = true,
    this.maxRetries = 3,
  });
}

/// Relay server health status
enum RelayHealthStatus {
  healthy,
  degraded,
  unhealthy,
  unknown,
}

/// Relay server information
class RelayServerInfo {
  final String url;
  final GunRelayClient client;
  final DateTime addedAt;
  
  RelayHealthStatus _healthStatus = RelayHealthStatus.unknown;
  DateTime _lastHealthCheck = DateTime.now();
  int _connectionCount = 0;
  int _failureCount = 0;
  double _responseTime = 0.0;
  
  RelayServerInfo({
    required this.url,
    required this.client,
  }) : addedAt = DateTime.now();
  
  RelayHealthStatus get healthStatus => _healthStatus;
  DateTime get lastHealthCheck => _lastHealthCheck;
  int get connectionCount => _connectionCount;
  int get failureCount => _failureCount;
  double get responseTime => _responseTime;
  
  void _updateHealth(RelayHealthStatus status, {double? responseTime}) {
    _healthStatus = status;
    _lastHealthCheck = DateTime.now();
    if (responseTime != null) {
      _responseTime = responseTime;
    }
  }
  
  void _incrementConnections() => _connectionCount++;
  void _decrementConnections() => _connectionCount = max(0, _connectionCount - 1);
  void _recordFailure() => _failureCount++;
  void _resetFailures() => _failureCount = 0;
  
  double get healthScore {
    switch (_healthStatus) {
      case RelayHealthStatus.healthy:
        return 1.0 - (_connectionCount / 100.0) - (_responseTime / 1000.0);
      case RelayHealthStatus.degraded:
        return 0.5 - (_connectionCount / 100.0) - (_responseTime / 1000.0);
      case RelayHealthStatus.unhealthy:
        return 0.1;
      case RelayHealthStatus.unknown:
        return 0.3;
    }
  }
}

/// Gun.js relay server pool manager
/// 
/// Manages connections to multiple Gun.js relay servers with load balancing,
/// health monitoring, automatic failover, and discovery.
class RelayPoolManager {
  final RelayPoolConfig config;
  
  final Map<String, RelayServerInfo> _relays = {};
  final List<String> _roundRobinOrder = [];
  int _roundRobinIndex = 0;
  
  Timer? _healthCheckTimer;
  Timer? _discoveryTimer;
  final Random _random = Random();
  
  final StreamController<RelayPoolEvent> _eventController = StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _messageController = StreamController.broadcast();
  
  RelayPoolManager(this.config);
  
  /// Stream of pool events
  Stream<RelayPoolEvent> get events => _eventController.stream;
  
  /// Stream of messages from all relays
  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  
  /// Number of currently active relay connections
  int get activeConnections => _relays.values.where((r) => r.client.isConnected).length;
  
  /// List of all relay URLs in the pool
  List<String> get relayUrls => _relays.keys.toList();
  
  /// Pool statistics
  Map<String, dynamic> get stats => {
    'totalRelays': _relays.length,
    'activeConnections': activeConnections,
    'healthyRelays': _relays.values.where((r) => r.healthStatus == RelayHealthStatus.healthy).length,
    'degradedRelays': _relays.values.where((r) => r.healthStatus == RelayHealthStatus.degraded).length,
    'unhealthyRelays': _relays.values.where((r) => r.healthStatus == RelayHealthStatus.unhealthy).length,
    'averageResponseTime': _relays.values.map((r) => r.responseTime).fold(0.0, (a, b) => a + b) / _relays.length,
    'totalConnectionCount': _relays.values.map((r) => r.connectionCount).fold(0, (a, b) => a + b),
  };
  
  /// Start the relay pool manager
  Future<void> start() async {
    // Add seed relays
    for (final url in config.seedRelays) {
      await addRelay(url);
    }
    
    // Start health monitoring
    _startHealthChecking();
    
    // Start auto-discovery if enabled
    if (config.autoDiscovery) {
      _startAutoDiscovery();
    }
    
    // Ensure minimum connections
    await _ensureMinimumConnections();
    
    _emitEvent(RelayPoolEvent(
      type: RelayPoolEventType.started,
      message: 'Relay pool started with ${_relays.length} relays',
    ));
  }
  
  /// Stop the relay pool manager
  Future<void> stop() async {
    _healthCheckTimer?.cancel();
    _discoveryTimer?.cancel();
    
    // Disconnect all relays
    final futures = _relays.values.map((info) => info.client.close());
    await Future.wait(futures);
    
    _relays.clear();
    _roundRobinOrder.clear();
    
    _emitEvent(RelayPoolEvent(
      type: RelayPoolEventType.stopped,
      message: 'Relay pool stopped',
    ));
  }
  
  /// Add a relay server to the pool
  Future<bool> addRelay(String url) async {
    if (_relays.containsKey(url)) {
      return true; // Already exists
    }
    
    if (_relays.length >= config.maxConnections) {
      _emitEvent(RelayPoolEvent(
        type: RelayPoolEventType.error,
        relayUrl: url,
        message: 'Cannot add relay: maximum connections reached',
      ));
      return false;
    }
    
    try {
      final client = GunRelayClient(
        config: RelayServerConfig(
          url: url,
          connectionTimeout: config.connectionTimeout,
        ),
      );
      
      final info = RelayServerInfo(url: url, client: client);
      _relays[url] = info;
      _roundRobinOrder.add(url);
      
      // Set up message forwarding
      client.messages.listen((message) {
        _messageController.add(message);
      });
      
      // Set up event forwarding
      client.events.listen((event) {
        _handleRelayEvent(url, event);
      });
      
      // Attempt to connect
      final connected = await client.connect();
      if (connected) {
        info._updateHealth(RelayHealthStatus.healthy);
        info._resetFailures();
        
        _emitEvent(RelayPoolEvent(
          type: RelayPoolEventType.relayAdded,
          relayUrl: url,
          message: 'Relay added and connected successfully',
        ));
      } else {
        info._updateHealth(RelayHealthStatus.unhealthy);
        info._recordFailure();
        
        _emitEvent(RelayPoolEvent(
          type: RelayPoolEventType.error,
          relayUrl: url,
          message: 'Failed to connect to relay',
        ));
      }
      
      return connected;
      
    } catch (e) {
      _emitEvent(RelayPoolEvent(
        type: RelayPoolEventType.error,
        relayUrl: url,
        message: 'Error adding relay: $e',
      ));
      return false;
    }
  }
  
  /// Remove a relay server from the pool
  Future<void> removeRelay(String url) async {
    final info = _relays[url];
    if (info == null) return;
    
    await info.client.close();
    _relays.remove(url);
    _roundRobinOrder.remove(url);
    
    if (_roundRobinIndex >= _roundRobinOrder.length) {
      _roundRobinIndex = 0;
    }
    
    _emitEvent(RelayPoolEvent(
      type: RelayPoolEventType.relayRemoved,
      relayUrl: url,
      message: 'Relay removed from pool',
    ));
  }
  
  /// Get the best relay server based on load balancing strategy
  RelayServerInfo? getBestRelay() {
    final healthyRelays = _relays.values
        .where((info) => info.client.isConnected && 
                        info.healthStatus != RelayHealthStatus.unhealthy)
        .toList();
    
    if (healthyRelays.isEmpty) {
      return null;
    }
    
    switch (config.loadBalancing) {
      case LoadBalancingStrategy.roundRobin:
        return _getRoundRobinRelay(healthyRelays);
      case LoadBalancingStrategy.leastConnections:
        return _getLeastConnectionsRelay(healthyRelays);
      case LoadBalancingStrategy.random:
        return _getRandomRelay(healthyRelays);
      case LoadBalancingStrategy.healthBased:
        return _getHealthBasedRelay(healthyRelays);
    }
  }
  
  /// Send a message through the best available relay
  Future<String?> sendMessage(Map<String, dynamic> message) async {
    final relay = getBestRelay();
    if (relay == null) {
      _emitEvent(RelayPoolEvent(
        type: RelayPoolEventType.error,
        message: 'No healthy relays available for message sending',
      ));
      return null;
    }
    
    try {
      relay._incrementConnections();
      final messageId = await relay.client.sendMessage(message);
      relay._decrementConnections();
      return messageId;
    } catch (e) {
      relay._decrementConnections();
      relay._recordFailure();
      
      _emitEvent(RelayPoolEvent(
        type: RelayPoolEventType.error,
        relayUrl: relay.url,
        message: 'Failed to send message through relay: $e',
      ));
      
      // Try with another relay
      final backupRelay = getBestRelay();
      if (backupRelay != null && backupRelay.url != relay.url) {
        try {
          backupRelay._incrementConnections();
          final messageId = await backupRelay.client.sendMessage(message);
          backupRelay._decrementConnections();
          return messageId;
        } catch (e2) {
          backupRelay._decrementConnections();
          backupRelay._recordFailure();
        }
      }
      
      return null;
    }
  }
  
  /// Send a get query to the best available relay
  Future<String?> sendGetQuery(String nodeId, {List<String>? path}) async {
    final relay = getBestRelay();
    if (relay == null) return null;
    
    try {
      relay._incrementConnections();
      final messageId = await relay.client.sendGetQuery(nodeId, path: path);
      relay._decrementConnections();
      return messageId;
    } catch (e) {
      relay._decrementConnections();
      relay._recordFailure();
      return null;
    }
  }
  
  /// Send put data to the best available relay
  Future<String?> sendPutData(String nodeId, Map<String, dynamic> data) async {
    final relay = getBestRelay();
    if (relay == null) return null;
    
    try {
      relay._incrementConnections();
      final messageId = await relay.client.sendPutData(nodeId, data);
      relay._decrementConnections();
      return messageId;
    } catch (e) {
      relay._decrementConnections();
      relay._recordFailure();
      return null;
    }
  }
  
  /// Handle relay server events
  void _handleRelayEvent(String url, RelayServerEvent event) {
    final info = _relays[url];
    if (info == null) return;
    
    switch (event.type) {
      case RelayEventType.connected:
        info._updateHealth(RelayHealthStatus.healthy);
        info._resetFailures();
        break;
      case RelayEventType.disconnected:
        info._updateHealth(RelayHealthStatus.unhealthy);
        break;
      case RelayEventType.error:
        info._recordFailure();
        if (info.failureCount > 3) {
          info._updateHealth(RelayHealthStatus.unhealthy);
        } else {
          info._updateHealth(RelayHealthStatus.degraded);
        }
        break;
      default:
        break;
    }
    
    // Forward event
    _emitEvent(RelayPoolEvent(
      type: RelayPoolEventType.relayEvent,
      relayUrl: url,
      message: event.toString(),
      data: event.toMap(),
    ));
  }
  
  /// Start health checking for all relays
  void _startHealthChecking() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(config.healthCheckInterval, (_) {
      _performHealthChecks();
    });
  }
  
  /// Perform health checks on all relays
  Future<void> _performHealthChecks() async {
    final futures = _relays.values.map(_performHealthCheck);
    await Future.wait(futures);
    
    // Remove consistently unhealthy relays
    final toRemove = <String>[];
    for (final entry in _relays.entries) {
      final info = entry.value;
      if (info.healthStatus == RelayHealthStatus.unhealthy && 
          info.failureCount > 5 &&
          DateTime.now().difference(info.lastHealthCheck) > Duration(minutes: 5)) {
        toRemove.add(entry.key);
      }
    }
    
    for (final url in toRemove) {
      await removeRelay(url);
    }
    
    // Ensure minimum connections
    await _ensureMinimumConnections();
  }
  
  /// Perform health check on a single relay
  Future<void> _performHealthCheck(RelayServerInfo info) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      if (!info.client.isConnected) {
        // Try to reconnect
        final connected = await info.client.connect();
        if (connected) {
          info._updateHealth(RelayHealthStatus.healthy, responseTime: stopwatch.elapsedMilliseconds.toDouble());
          info._resetFailures();
        } else {
          info._updateHealth(RelayHealthStatus.unhealthy);
          info._recordFailure();
        }
      } else {
        // Send ping to check responsiveness
        await info.client.sendMessage({
          'ping': DateTime.now().millisecondsSinceEpoch,
          '@': Utils.randomString(8),
        });
        
        info._updateHealth(RelayHealthStatus.healthy, responseTime: stopwatch.elapsedMilliseconds.toDouble());
        info._resetFailures();
      }
    } catch (e) {
      info._updateHealth(RelayHealthStatus.unhealthy);
      info._recordFailure();
    }
  }
  
  /// Start auto-discovery of relay servers
  void _startAutoDiscovery() {
    _discoveryTimer?.cancel();
    _discoveryTimer = Timer.periodic(Duration(minutes: 5), (_) {
      _performAutoDiscovery();
    });
  }
  
  /// Perform auto-discovery of new relay servers
  Future<void> _performAutoDiscovery() async {
    // In a real implementation, this would:
    // 1. Query DHT for relay servers
    // 2. Ask peers for their relay servers
    // 3. Use well-known relay server lists
    // 4. DNS-based discovery
    
    // For now, this is a placeholder that could be extended
    _emitEvent(RelayPoolEvent(
      type: RelayPoolEventType.discovery,
      message: 'Auto-discovery completed (no new relays found)',
    ));
  }
  
  /// Ensure minimum number of healthy connections
  Future<void> _ensureMinimumConnections() async {
    final healthyCount = _relays.values
        .where((info) => info.client.isConnected && 
                        info.healthStatus != RelayHealthStatus.unhealthy)
        .length;
    
    if (healthyCount < config.minConnections) {
      _emitEvent(RelayPoolEvent(
        type: RelayPoolEventType.warning,
        message: 'Below minimum healthy connections: $healthyCount/${config.minConnections}',
      ));
    }
  }
  
  /// Get relay using round-robin strategy
  RelayServerInfo? _getRoundRobinRelay(List<RelayServerInfo> relays) {
    if (relays.isEmpty) return null;
    
    // Find the next relay in round-robin order
    for (int i = 0; i < _roundRobinOrder.length; i++) {
      final index = (_roundRobinIndex + i) % _roundRobinOrder.length;
      final url = _roundRobinOrder[index];
      final relay = relays.firstWhere((r) => r.url == url, orElse: () => relays.first);
      
      if (relays.contains(relay)) {
        _roundRobinIndex = (index + 1) % _roundRobinOrder.length;
        return relay;
      }
    }
    
    return relays.first;
  }
  
  /// Get relay with least connections
  RelayServerInfo _getLeastConnectionsRelay(List<RelayServerInfo> relays) {
    return relays.reduce((a, b) => a.connectionCount < b.connectionCount ? a : b);
  }
  
  /// Get random relay
  RelayServerInfo _getRandomRelay(List<RelayServerInfo> relays) {
    return relays[_random.nextInt(relays.length)];
  }
  
  /// Get relay based on health score
  RelayServerInfo _getHealthBasedRelay(List<RelayServerInfo> relays) {
    return relays.reduce((a, b) => a.healthScore > b.healthScore ? a : b);
  }
  
  /// Emit pool event
  void _emitEvent(RelayPoolEvent event) {
    _eventController.add(event);
  }
  
  /// Close the relay pool manager
  Future<void> close() async {
    await stop();
    await _eventController.close();
    await _messageController.close();
  }
}

/// Relay pool event types
enum RelayPoolEventType {
  started,
  stopped,
  relayAdded,
  relayRemoved,
  relayEvent,
  discovery,
  warning,
  error,
}

/// Relay pool event
class RelayPoolEvent {
  final RelayPoolEventType type;
  final String? relayUrl;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;
  
  RelayPoolEvent({
    required this.type,
    this.relayUrl,
    required this.message,
    this.data,
  }) : timestamp = DateTime.now();
  
  Map<String, dynamic> toMap() => {
    'type': type.toString().split('.').last,
    'relayUrl': relayUrl,
    'message': message,
    'data': data,
    'timestamp': timestamp.toIso8601String(),
  };
  
  @override
  String toString() => 'RelayPoolEvent(${type.toString().split('.').last}: $message)';
}
