import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import '../utils/utils.dart';
import 'gun_wire_protocol.dart';
import 'peer_handshake.dart';
import 'message_tracker.dart';
import '../types/events.dart';

/// Gun.js relay server configuration
class RelayServerConfig {
  final String url;
  final Map<String, String> headers;
  final Duration connectionTimeout;
  final Duration pingInterval;
  final bool autoReconnect;
  final int maxReconnectAttempts;
  
  const RelayServerConfig({
    required this.url,
    this.headers = const {},
    this.connectionTimeout = const Duration(seconds: 10),
    this.pingInterval = const Duration(seconds: 30),
    this.autoReconnect = true,
    this.maxReconnectAttempts = 5,
  });
  
  RelayServerConfig.defaultConfig(String url) : this(url: url);
}

/// Connection state for relay server
enum RelayConnectionState {
  disconnected,
  connecting,
  authenticating,
  connected,
  reconnecting,
  failed,
}

/// Relay server connection statistics
class RelayStats {
  int messagesReceived = 0;
  int messagesSent = 0;
  int reconnectionAttempts = 0;
  int connectionFailures = 0;
  DateTime? lastConnected;
  DateTime? lastMessageReceived;
  Duration averageLatency = Duration.zero;
  
  RelayStats();
  
  Map<String, dynamic> toMap() => {
    'messagesReceived': messagesReceived,
    'messagesSent': messagesSent,
    'reconnectionAttempts': reconnectionAttempts,
    'connectionFailures': connectionFailures,
    'lastConnected': lastConnected?.toIso8601String(),
    'lastMessageReceived': lastMessageReceived?.toIso8601String(),
    'averageLatency': averageLatency.inMilliseconds,
  };
}

/// Gun.js relay server client
/// 
/// Provides connectivity to Gun.js relay servers with full protocol compatibility,
/// automatic reconnection, and proper message routing.
class GunRelayClient {
  final RelayServerConfig config;
  final String peerId;
  
  WebSocketChannel? _channel;
  RelayConnectionState _state = RelayConnectionState.disconnected;
  final MessageTracker _messageTracker = MessageTracker();
  final PeerHandshakeManager _handshakeManager = PeerHandshakeManager();
  final RelayStats _stats = RelayStats();
  
  final StreamController<Map<String, dynamic>> _messageController = StreamController.broadcast();
  final StreamController<RelayConnectionState> _stateController = StreamController.broadcast();
  final StreamController<RelayServerEvent> _eventController = StreamController.broadcast();
  
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  
  GunRelayClient({
    required this.config,
    String? peerId,
  }) : peerId = peerId ?? _generatePeerId();
  
  /// Generate a unique peer ID for this relay client
  static String _generatePeerId() => 'dart-relay-${Utils.randomString(8)}';
  
  /// Current connection state
  RelayConnectionState get state => _state;
  
  /// Whether the relay is currently connected
  bool get isConnected => _state == RelayConnectionState.connected;
  
  /// Stream of incoming messages from the relay server
  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  
  /// Stream of connection state changes
  Stream<RelayConnectionState> get stateChanges => _stateController.stream;
  
  /// Stream of relay server events
  Stream<RelayServerEvent> get events => _eventController.stream;
  
  /// Current relay server statistics
  RelayStats get stats => _stats;
  
  /// Connect to the Gun.js relay server
  Future<bool> connect() async {
    if (_state == RelayConnectionState.connecting || _state == RelayConnectionState.connected) {
      return _state == RelayConnectionState.connected;
    }
    
    _setState(RelayConnectionState.connecting);
    
    try {
      // Parse WebSocket URL from Gun.js relay URL
      final wsUrl = _convertToWebSocketUrl(config.url);
      
      // Create WebSocket connection with headers
      final uri = Uri.parse(wsUrl);
      _channel = IOWebSocketChannel.connect(
        uri,
        headers: config.headers.isNotEmpty ? config.headers : null,
        connectTimeout: config.connectionTimeout,
      );
      
      // Wait for connection to be established
      await _channel!.ready.timeout(config.connectionTimeout);
      
      // Set up message handling
      _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDisconnect,
        cancelOnError: false,
      );
      
      // Start authentication handshake
      _setState(RelayConnectionState.authenticating);
      final success = await _performHandshake();
      
      if (success) {
        _setState(RelayConnectionState.connected);
        _stats.lastConnected = DateTime.now();
        _reconnectAttempts = 0;
        
        // Start ping timer for keep-alive
        _startPingTimer();
        
        _emitEvent(RelayServerEvent(
          type: RelayEventType.connected,
          relayUrl: config.url,
          peerId: peerId,
        ));
        
        return true;
      } else {
        await _handleConnectionFailure('Handshake failed');
        return false;
      }
      
    } catch (e) {
      await _handleConnectionFailure('Connection failed: $e');
      return false;
    }
  }
  
  /// Disconnect from the relay server
  Future<void> disconnect() async {
    _cancelTimers();
    
    if (_channel != null && _state == RelayConnectionState.connected) {
      // Send bye message for graceful disconnection
      try {
        await _sendByeMessage();
      } catch (e) {
        // Ignore errors during bye message sending
      }
    }
    
    await _channel?.sink.close(WebSocketStatus.normalClosure, 'Client disconnecting');
    _channel = null;
    
    _setState(RelayConnectionState.disconnected);
    
    _emitEvent(RelayServerEvent(
      type: RelayEventType.disconnected,
      relayUrl: config.url,
      peerId: peerId,
    ));
  }
  
  /// Send a message to the relay server
  Future<String> sendMessage(Map<String, dynamic> message) async {
    if (!isConnected) {
      throw StateError('Relay client is not connected');
    }
    
    // Add message ID
    final messageId = Utils.randomString(8);
    message['@'] = messageId;
    
    // Send the message through WebSocket
    final wireMessage = json.encode(message);
    _channel!.sink.add(wireMessage);
    
    _stats.messagesSent++;
    
    _emitEvent(RelayServerEvent(
      type: RelayEventType.messageSent,
      relayUrl: config.url,
      peerId: peerId,
      data: message,
    ));
    
    return messageId;
  }
  
  /// Send a Gun.js get query to the relay server
  Future<String> sendGetQuery(String nodeId, {List<String>? path}) async {
    final getQuery = path == null || path.isEmpty
        ? {'get': {'#': nodeId}}
        : {'get': _buildPathQuery(nodeId, path)};
    
    return await sendMessage(getQuery);
  }
  
  /// Send a Gun.js put operation to the relay server
  Future<String> sendPutData(String nodeId, Map<String, dynamic> data) async {
    final putMessage = {
      'put': {nodeId: data}
    };
    
    return await sendMessage(putMessage);
  }
  
  /// Handle incoming message from relay server
  void _handleMessage(dynamic rawMessage) {
    _stats.messagesReceived++;
    _stats.lastMessageReceived = DateTime.now();
    
    try {
      final message = json.decode(rawMessage as String) as Map<String, dynamic>;
      
      // Handle acknowledgments
      if (message.containsKey('#')) {
        final ackId = message['#'] as String;
        _messageTracker.handleAck(ackId, Utils.randomString(8));
      }
      
      // Emit the message for external handling
      _messageController.add(message);
      
      _emitEvent(RelayServerEvent(
        type: RelayEventType.messageReceived,
        relayUrl: config.url,
        peerId: peerId,
        data: message,
      ));
      
    } catch (e) {
      _emitEvent(RelayServerEvent(
        type: RelayEventType.error,
        relayUrl: config.url,
        peerId: peerId,
        error: 'Failed to parse message: $e',
      ));
    }
  }
  
  /// Handle WebSocket errors
  void _handleError(dynamic error) {
    _stats.connectionFailures++;
    
    _emitEvent(RelayServerEvent(
      type: RelayEventType.error,
      relayUrl: config.url,
      peerId: peerId,
      error: error.toString(),
    ));
    
    if (_state == RelayConnectionState.connected || _state == RelayConnectionState.connecting) {
      _handleConnectionFailure('WebSocket error: $error');
    }
  }
  
  /// Handle WebSocket disconnection
  void _handleDisconnect() {
    _cancelTimers();
    
    if (_state == RelayConnectionState.connected) {
      _emitEvent(RelayServerEvent(
        type: RelayEventType.disconnected,
        relayUrl: config.url,
        peerId: peerId,
      ));
      
      if (config.autoReconnect && _reconnectAttempts < config.maxReconnectAttempts) {
        _startReconnectTimer();
      } else {
        _setState(RelayConnectionState.failed);
      }
    } else {
      _setState(RelayConnectionState.disconnected);
    }
  }
  
  /// Handle connection failures
  Future<void> _handleConnectionFailure(String reason) async {
    _stats.connectionFailures++;
    
    _emitEvent(RelayServerEvent(
      type: RelayEventType.error,
      relayUrl: config.url,
      peerId: peerId,
      error: reason,
    ));
    
    if (config.autoReconnect && _reconnectAttempts < config.maxReconnectAttempts) {
      _setState(RelayConnectionState.reconnecting);
      _startReconnectTimer();
    } else {
      _setState(RelayConnectionState.failed);
    }
  }
  
  /// Perform handshake with relay server
  Future<bool> _performHandshake() async {
    try {
      // Send hi message to relay server
      final hiMessage = GunWireProtocol.createHiMessage(
        version: 'dart-relay-0.4.0',
        peerId: peerId,
      );
      
      await sendMessage(hiMessage);
      
      // Wait for handshake response (simplified for relay servers)
      // Gun.js relay servers typically don't require complex handshakes
      // They accept connections and start relaying messages immediately
      
      return true;
      
    } catch (e) {
      return false;
    }
  }
  
  /// Send bye message for graceful disconnection
  Future<void> _sendByeMessage() async {
    try {
      final byeMessage = GunWireProtocol.createByeMessage(peerId: peerId);
      await sendMessage(byeMessage);
    } catch (e) {
      // Ignore errors during bye message
    }
  }
  
  /// Convert Gun.js relay URL to WebSocket URL
  String _convertToWebSocketUrl(String relayUrl) {
    if (relayUrl.startsWith('ws://') || relayUrl.startsWith('wss://')) {
      return relayUrl;
    }
    
    // Convert HTTP(S) URLs to WebSocket URLs
    if (relayUrl.startsWith('https://')) {
      return relayUrl.replaceFirst('https://', 'wss://');
    } else if (relayUrl.startsWith('http://')) {
      return relayUrl.replaceFirst('http://', 'ws://');
    }
    
    // Default to WebSocket if no protocol specified
    return 'ws://$relayUrl';
  }
  
  /// Build path query for Gun.js traversal
  Map<String, dynamic> _buildPathQuery(String nodeId, List<String> path) {
    if (path.isEmpty) {
      return {'#': nodeId};
    }
    
    Map<String, dynamic> query = {'#': nodeId};
    for (final segment in path) {
      query = {'.': {segment: query}};
    }
    
    return query;
  }
  
  /// Set connection state and notify listeners
  void _setState(RelayConnectionState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(_state);
    }
  }
  
  /// Start ping timer for keep-alive
  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(config.pingInterval, (_) {
      if (isConnected) {
        _sendPing();
      }
    });
  }
  
  /// Start reconnection timer
  void _startReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    _stats.reconnectionAttempts++;
    
    // Exponential backoff with jitter
    final delay = Duration(
      milliseconds: (1000 * (1 << (_reconnectAttempts - 1).clamp(0, 5))) + 
                    (Utils.randomString(3).hashCode.abs() % 1000)
    );
    
    _reconnectTimer = Timer(delay, () {
      if (_state == RelayConnectionState.reconnecting) {
        connect();
      }
    });
  }
  
  /// Send ping message
  void _sendPing() {
    try {
      final pingMessage = {
        'ping': DateTime.now().millisecondsSinceEpoch,
        '@': Utils.randomString(8),
      };
      
      final wireMessage = json.encode(pingMessage);
      _channel?.sink.add(wireMessage);
      
    } catch (e) {
      // Ignore ping errors
    }
  }
  
  /// Cancel all timers
  void _cancelTimers() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }
  
  /// Emit relay server event
  void _emitEvent(RelayServerEvent event) {
    _eventController.add(event);
  }
  
  /// Close the relay client and clean up resources
  Future<void> close() async {
    await disconnect();
    _cancelTimers();
    
    await _messageController.close();
    await _stateController.close();
    await _eventController.close();
  }
}

/// Relay server event types
enum RelayEventType {
  connected,
  disconnected,
  messageSent,
  messageReceived,
  error,
  reconnecting,
}

/// Relay server event
class RelayServerEvent {
  final RelayEventType type;
  final String relayUrl;
  final String peerId;
  final Map<String, dynamic>? data;
  final String? error;
  final DateTime timestamp;
  
  RelayServerEvent({
    required this.type,
    required this.relayUrl,
    required this.peerId,
    this.data,
    this.error,
  }) : timestamp = DateTime.now();
  
  Map<String, dynamic> toMap() => {
    'type': type.toString().split('.').last,
    'relayUrl': relayUrl,
    'peerId': peerId,
    'data': data,
    'error': error,
    'timestamp': timestamp.toIso8601String(),
  };
  
  @override
  String toString() => 'RelayServerEvent(${type.toString().split('.').last}: $relayUrl)';
}
