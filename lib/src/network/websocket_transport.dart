import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'transport.dart';

/// WebSocket transport implementation for Gun Dart with Gun.js wire protocol support
/// Provides real-time bidirectional communication over WebSocket
class WebSocketTransport extends BaseTransport {
  final String _url;
  WebSocketChannel? _channel;
  final StreamController<bool> _connectionStateController = StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _messagesController = StreamController.broadcast();
  bool _isConnected = false;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  final Duration _reconnectDelay;
  final Duration _pingInterval;
  final bool _autoReconnect;
  int _reconnectAttempts = 0;
  final int _maxReconnectAttempts;
  
  /// Create a WebSocket transport
  /// 
  /// [url] - WebSocket URL (ws:// or wss://)
  /// [reconnectDelay] - Delay between reconnection attempts
  /// [pingInterval] - Interval for sending ping messages
  /// [autoReconnect] - Whether to automatically reconnect on disconnect
  /// [maxReconnectAttempts] - Maximum number of reconnection attempts (0 = infinite)
  WebSocketTransport(
    this._url, {
    Duration reconnectDelay = const Duration(seconds: 5),
    Duration pingInterval = const Duration(seconds: 30),
    bool autoReconnect = true,
    int maxReconnectAttempts = 0,
  })
      : _reconnectDelay = reconnectDelay,
        _pingInterval = pingInterval,
        _autoReconnect = autoReconnect,
        _maxReconnectAttempts = maxReconnectAttempts,
        super();
  
  @override
  String get url => _url;
  
  @override
  bool get isConnected => _isConnected;
  
  @override
  Stream<bool> get connectionState => _connectionStateController.stream;
  
  @override
  Stream<Map<String, dynamic>> get messages => _messagesController.stream;
  
  @override
  Future<void> connect() async {
    if (_isConnected) return;
    
    try {
      _channel = IOWebSocketChannel.connect(Uri.parse(_url));
      
      // Listen for messages
      _channel!.stream.listen(
        (data) {
          _handleIncomingMessage(data);
        },
        onError: (error) {
          _handleConnectionError(error);
        },
        onDone: () {
          _handleConnectionClosed();
        },
      );
      
      _isConnected = true;
      _reconnectAttempts = 0;
      _connectionStateController.add(true);
      
      // Start ping timer to keep connection alive
      _startPingTimer();
      
    } catch (e) {
      _handleConnectionError(e);
      rethrow;
    }
  }
  
  @override
  Future<void> disconnect() async {
    _stopReconnectTimer();
    _stopPingTimer();
    
    if (_channel != null) {
      await _channel!.sink.close(WebSocketStatus.goingAway);
      _channel = null;
    }
    
    if (_isConnected) {
      _isConnected = false;
      _connectionStateController.add(false);
    }
  }
  
  @override
  Future<void> send(Map<String, dynamic> message) async {
    if (!_isConnected || _channel == null) {
      throw StateError('WebSocket not connected');
    }
    
    try {
      final jsonMessage = jsonEncode(message);
      _channel!.sink.add(jsonMessage);
    } catch (e) {
      _handleConnectionError(e);
      rethrow;
    }
  }
  
  @override
  Future<void> close() async {
    await disconnect();
    await _connectionStateController.close();
    await _messagesController.close();
  }
  
  /// Handle incoming WebSocket messages
  void _handleIncomingMessage(dynamic data) {
    try {
      if (data is String) {
        // Parse JSON safely
        dynamic parsed;
        try {
          parsed = jsonDecode(data);
        } catch (e) {
          print('WebSocketTransport: Invalid JSON: $e');
          return;
        }
        
        // Handle different message formats from Gun.js
        if (parsed is Map<String, dynamic>) {
          _handleMapMessage(parsed);
        } else if (parsed is List) {
          // Gun.js sometimes sends arrays of messages
          for (final item in parsed) {
            if (item is Map<String, dynamic>) {
              _handleMapMessage(item);
            }
          }
        } else {
          print('WebSocketTransport: Unexpected message format: ${parsed.runtimeType}');
        }
      }
    } catch (e) {
      print('WebSocketTransport: Failed to parse message: $e');
    }
  }
  
  /// Handle map-based messages from Gun.js
  void _handleMapMessage(Map<String, dynamic> message) {
    try {
      // Debug: log all incoming messages except pings
      if (message['type'] != 'ping' && message['type'] != 'pong') {
        print('WebSocketTransport: Received message: $message');
      }
      
      // Handle ping/pong messages internally
      if (message['type'] == 'ping') {
        _sendPong();
        return;
      }
      
      if (message['type'] == 'pong') {
        // Pong received, connection is alive
        return;
      }
      
      // Create a clean message map, filtering out Gun.js internal fields
      final cleanMessage = <String, dynamic>{};
      
      // Copy standard Gun.js fields
      for (final entry in message.entries) {
        final key = entry.key;
        final value = entry.value;
        
        // Skip Gun.js internal fields that might cause parsing issues
        if (key == '##' || key == 'FOO' || key == 'pid') {
          continue; // These are Gun.js internal fields
        }
        
        // Handle null values gracefully
        if (value != null) {
          cleanMessage[key] = value;
        }
      }
      
      // Only forward non-empty messages
      if (cleanMessage.isNotEmpty) {
        _messagesController.add(cleanMessage);
      }
    } catch (e) {
      print('WebSocketTransport: Error handling map message: $e');
    }
  }
  
  /// Handle connection errors
  void _handleConnectionError(dynamic error) {
    print('WebSocketTransport: Connection error: $error');
    
    if (_isConnected) {
      _isConnected = false;
      _connectionStateController.add(false);
    }
    
    if (_autoReconnect) {
      _scheduleReconnect();
    }
  }
  
  /// Handle connection closed
  void _handleConnectionClosed() {
    if (_isConnected) {
      _isConnected = false;
      _connectionStateController.add(false);
    }
    
    _stopPingTimer();
    
    if (_autoReconnect) {
      _scheduleReconnect();
    }
  }
  
  /// Schedule a reconnection attempt
  void _scheduleReconnect() {
    if (_maxReconnectAttempts > 0 && _reconnectAttempts >= _maxReconnectAttempts) {
      print('WebSocketTransport: Max reconnection attempts reached');
      return;
    }
    
    _stopReconnectTimer();
    _reconnectAttempts++;
    
    print('WebSocketTransport: Scheduling reconnect attempt $_reconnectAttempts in ${_reconnectDelay.inSeconds}s');
    
    _reconnectTimer = Timer(_reconnectDelay, () {
      connect().catchError((e) {
        print('WebSocketTransport: Reconnection failed: $e');
      });
    });
  }
  
  /// Start the ping timer
  void _startPingTimer() {
    _stopPingTimer();
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      _sendPing();
    });
  }
  
  /// Stop the ping timer
  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }
  
  /// Stop the reconnect timer
  void _stopReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }
  
  /// Send a ping message
  void _sendPing() {
    if (_isConnected && _channel != null) {
      try {
        final pingMessage = jsonEncode({'type': 'ping', 'timestamp': DateTime.now().millisecondsSinceEpoch});
        _channel!.sink.add(pingMessage);
      } catch (e) {
        _handleConnectionError(e);
      }
    }
  }
  
  /// Send a pong message in response to ping
  void _sendPong() {
    if (_isConnected && _channel != null) {
      try {
        final pongMessage = jsonEncode({'type': 'pong', 'timestamp': DateTime.now().millisecondsSinceEpoch});
        _channel!.sink.add(pongMessage);
      } catch (e) {
        _handleConnectionError(e);
      }
    }
  }
  
  /// Get connection statistics
  Map<String, dynamic> getStats() {
    return {
      'url': _url,
      'isConnected': _isConnected,
      'reconnectAttempts': _reconnectAttempts,
      'maxReconnectAttempts': _maxReconnectAttempts,
      'autoReconnect': _autoReconnect,
    };
  }
}
