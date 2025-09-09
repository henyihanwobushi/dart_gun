import 'dart:async';
import 'dart:math' as math;
import '../utils/utils.dart';
import 'peer.dart';
import 'peer_handshake.dart';
import 'websocket_transport.dart';

/// Gun.js compatible mesh networking discovery system
/// 
/// This class manages automatic peer discovery and connection
/// management to build resilient Gun.js compatible mesh networks.
class MeshNetworkDiscovery {
  final List<String> _knownPeerUrls = [];
  final Map<String, WebSocketPeer> _connectedPeers = {};
  final Map<String, DateTime> _lastConnectionAttempt = {};
  final List<String> _seedPeers;
  final int _maxPeers;
  final Duration _reconnectInterval;
  final Duration _discoveryInterval;
  final math.Random _random = math.Random();
  
  Timer? _discoveryTimer;
  Timer? _maintenanceTimer;
  StreamSubscription? _peerConnectionSub;
  bool _isActive = false;
  
  /// Statistics for monitoring mesh health
  MeshStats _stats = MeshStats();
  
  /// Stream controller for mesh network events
  final StreamController<MeshEvent> _eventController = StreamController.broadcast();
  
  MeshNetworkDiscovery({
    List<String> seedPeers = const [],
    int maxPeers = 8,
    Duration reconnectInterval = const Duration(seconds: 30),
    Duration discoveryInterval = const Duration(seconds: 60),
  }) : _seedPeers = List.from(seedPeers),
       _maxPeers = maxPeers,
       _reconnectInterval = reconnectInterval,
       _discoveryInterval = discoveryInterval {
    _knownPeerUrls.addAll(_seedPeers);
  }
  
  /// Stream of mesh network events
  Stream<MeshEvent> get events => _eventController.stream;
  
  /// Get current mesh statistics
  MeshStats get stats => _stats;
  
  /// Get list of connected peers
  List<WebSocketPeer> get connectedPeers => List.from(_connectedPeers.values);
  
  /// Get list of known peer URLs
  List<String> get knownPeerUrls => List.from(_knownPeerUrls);
  
  /// Start mesh network discovery
  Future<void> start() async {
    if (_isActive) return;
    
    _isActive = true;
    
    // Start discovery timer
    _discoveryTimer = Timer.periodic(_discoveryInterval, (_) => _runDiscovery());
    
    // Start maintenance timer
    _maintenanceTimer = Timer.periodic(_reconnectInterval, (_) => _runMaintenance());
    
    // Initial connection attempt
    await _runDiscovery();
    
    _eventController.add(MeshEvent(
      type: MeshEventType.discoveryStarted,
      message: 'Mesh network discovery started',
    ));
  }
  
  /// Stop mesh network discovery
  Future<void> stop() async {
    if (!_isActive) return;
    
    _isActive = false;
    
    // Cancel timers
    _discoveryTimer?.cancel();
    _maintenanceTimer?.cancel();
    
    // Disconnect all peers
    await disconnectAll();
    
    _eventController.add(MeshEvent(
      type: MeshEventType.discoveryStopped,
      message: 'Mesh network discovery stopped',
    ));
  }
  
  /// Add a peer URL to the known peers list
  void addPeerUrl(String url) {
    if (!_knownPeerUrls.contains(url)) {
      _knownPeerUrls.add(url);
      _eventController.add(MeshEvent(
        type: MeshEventType.peerDiscovered,
        peerUrl: url,
        message: 'New peer URL discovered: $url',
      ));
    }
  }
  
  /// Remove a peer URL from known peers
  void removePeerUrl(String url) {
    _knownPeerUrls.remove(url);
    _lastConnectionAttempt.remove(url);
  }
  
  /// Connect to a specific peer
  Future<bool> connectToPeer(String url) async {
    if (_connectedPeers.containsKey(url)) {
      return true; // Already connected
    }
    
    if (_connectedPeers.length >= _maxPeers) {
      return false; // Too many connections
    }
    
    try {
      _lastConnectionAttempt[url] = DateTime.now();
      
      final peer = WebSocketPeer(url);
      await peer.connect();
      
      _connectedPeers[url] = peer;
      _stats = _stats.copyWith(
        connectedPeers: _connectedPeers.length,
        totalConnectionAttempts: _stats.totalConnectionAttempts + 1,
        successfulConnections: _stats.successfulConnections + 1,
      );
      
      // Subscribe to peer connection events
      peer.connectionState.listen((isConnected) {
        if (!isConnected && _connectedPeers.containsKey(url)) {
          _handlePeerDisconnect(url);
        }
      });
      
      _eventController.add(MeshEvent(
        type: MeshEventType.peerConnected,
        peerUrl: url,
        peerInfo: peer.remotePeerInfo,
        message: 'Connected to peer: $url',
      ));
      
      // Ask connected peer for their known peers
      await _requestPeerList(peer);
      
      return true;
      
    } catch (e) {
      _stats = _stats.copyWith(
        totalConnectionAttempts: _stats.totalConnectionAttempts + 1,
        failedConnections: _stats.failedConnections + 1,
      );
      
      _eventController.add(MeshEvent(
        type: MeshEventType.connectionFailed,
        peerUrl: url,
        message: 'Failed to connect to peer: $url, Error: $e',
      ));
      
      return false;
    }
  }
  
  /// Disconnect from a specific peer
  Future<void> disconnectFromPeer(String url) async {
    final peer = _connectedPeers.remove(url);
    if (peer != null) {
      await peer.disconnect();
      await peer.close();
      
      _stats = _stats.copyWith(
        connectedPeers: _connectedPeers.length,
      );
      
      _eventController.add(MeshEvent(
        type: MeshEventType.peerDisconnected,
        peerUrl: url,
        message: 'Disconnected from peer: $url',
      ));
    }
  }
  
  /// Disconnect from all peers
  Future<void> disconnectAll() async {
    final urls = List.from(_connectedPeers.keys);
    for (final url in urls) {
      await disconnectFromPeer(url);
    }
  }
  
  /// Run peer discovery process
  Future<void> _runDiscovery() async {
    if (!_isActive) return;
    
    final availableSlots = _maxPeers - _connectedPeers.length;
    if (availableSlots <= 0) return;
    
    // Get list of unconnected peers
    final unconnectedPeers = _knownPeerUrls
        .where((url) => !_connectedPeers.containsKey(url))
        .where((url) => _shouldAttemptConnection(url))
        .toList();
    
    if (unconnectedPeers.isEmpty) return;
    
    // Shuffle to avoid all clients connecting to the same peers
    unconnectedPeers.shuffle(_random);
    
    // Connect to up to availableSlots peers
    final connectionsToMake = math.min(availableSlots, unconnectedPeers.length);
    
    for (int i = 0; i < connectionsToMake; i++) {
      final peerUrl = unconnectedPeers[i];
      await connectToPeer(peerUrl);
      
      // Add small delay between connections
      await Future.delayed(Duration(milliseconds: 100 + _random.nextInt(200)));
    }
  }
  
  /// Run maintenance tasks (reconnection, health checks)
  Future<void> _runMaintenance() async {
    if (!_isActive) return;
    
    // Remove disconnected peers
    final disconnectedUrls = <String>[];
    for (final entry in _connectedPeers.entries) {
      if (!entry.value.isConnected) {
        disconnectedUrls.add(entry.key);
      }
    }
    
    for (final url in disconnectedUrls) {
      await _handlePeerDisconnect(url);
    }
    
    // If we have fewer connections than desired, try discovery
    if (_connectedPeers.length < _maxPeers ~/ 2) {
      await _runDiscovery();
    }
  }
  
  /// Check if we should attempt connection to a peer
  bool _shouldAttemptConnection(String url) {
    final lastAttempt = _lastConnectionAttempt[url];
    if (lastAttempt == null) return true;
    
    // Don't retry failed connections for a while
    return DateTime.now().difference(lastAttempt) > _reconnectInterval;
  }
  
  /// Handle peer disconnection
  Future<void> _handlePeerDisconnect(String url) async {
    final peer = _connectedPeers.remove(url);
    if (peer != null) {
      try {
        await peer.close();
      } catch (e) {
        // Ignore cleanup errors
      }
      
      _stats = _stats.copyWith(
        connectedPeers: _connectedPeers.length,
      );
      
      _eventController.add(MeshEvent(
        type: MeshEventType.peerDisconnected,
        peerUrl: url,
        message: 'Peer disconnected: $url',
      ));
    }
  }
  
  /// Request peer list from connected peer (Gun.js style)
  Future<void> _requestPeerList(WebSocketPeer peer) async {
    // In Gun.js, peers share their peer lists
    // For now, this is a placeholder - in full implementation,
    // this would send a special message to request known peers
    try {
      // Send a discovery message (simplified)
      await peer.send({
        'discover': {'peers': true},
        '@': Utils.randomString(8),
      });
    } catch (e) {
      // Ignore discovery request errors
    }
  }
  
  /// Clean up resources
  Future<void> dispose() async {
    await stop();
    await _eventController.close();
  }
}

/// Mesh network event
class MeshEvent {
  final MeshEventType type;
  final String? peerUrl;
  final PeerInfo? peerInfo;
  final String message;
  final DateTime timestamp;
  
  MeshEvent({
    required this.type,
    this.peerUrl,
    this.peerInfo,
    required this.message,
  }) : timestamp = DateTime.now();
  
  @override
  String toString() => 'MeshEvent(type: $type, peer: $peerUrl, message: $message)';
}

/// Mesh network event types
enum MeshEventType {
  discoveryStarted,
  discoveryStopped,
  peerDiscovered,
  peerConnected,
  peerDisconnected,
  connectionFailed,
}

/// Mesh network statistics
class MeshStats {
  final int connectedPeers;
  final int totalConnectionAttempts;
  final int successfulConnections;
  final int failedConnections;
  final DateTime lastDiscoveryRun;
  
  MeshStats({
    this.connectedPeers = 0,
    this.totalConnectionAttempts = 0,
    this.successfulConnections = 0,
    this.failedConnections = 0,
    DateTime? lastDiscoveryRun,
  }) : lastDiscoveryRun = lastDiscoveryRun ?? DateTime.utc(2024, 1, 1);
  
  MeshStats copyWith({
    int? connectedPeers,
    int? totalConnectionAttempts,
    int? successfulConnections,
    int? failedConnections,
    DateTime? lastDiscoveryRun,
  }) {
    return MeshStats(
      connectedPeers: connectedPeers ?? this.connectedPeers,
      totalConnectionAttempts: totalConnectionAttempts ?? this.totalConnectionAttempts,
      successfulConnections: successfulConnections ?? this.successfulConnections,
      failedConnections: failedConnections ?? this.failedConnections,
      lastDiscoveryRun: lastDiscoveryRun ?? this.lastDiscoveryRun,
    );
  }
  
  double get connectionSuccessRate {
    if (totalConnectionAttempts == 0) return 0.0;
    return successfulConnections / totalConnectionAttempts;
  }
  
  @override
  String toString() {
    return 'MeshStats(connected: $connectedPeers, attempts: $totalConnectionAttempts, '
        'success: $successfulConnections, failed: $failedConnections, '
        'success rate: ${(connectionSuccessRate * 100).toStringAsFixed(1)}%)';
  }
}
