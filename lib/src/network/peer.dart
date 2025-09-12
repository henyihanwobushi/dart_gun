import 'dart:async';
import '../types/types.dart';
import 'gun_wire_protocol.dart';
import 'transport.dart';
import 'websocket_transport.dart';
import 'peer_handshake.dart';

/// Abstract peer interface for Gun network layer
abstract class Peer {
  /// Peer URL or identifier
  String get url;
  
  /// Current connection status
  bool get isConnected;
  
  /// Connect to this peer
  Future<void> connect();
  
  /// Disconnect from this peer
  Future<void> disconnect();
  
  /// Send data to this peer
  Future<void> send(Map<String, dynamic> data);
  
  /// Stream of incoming messages from this peer
  Stream<Map<String, dynamic>> get messages;
  
  /// Close the peer and clean up resources
  Future<void> close();
}

/// WebSocket implementation of a Gun peer
class WebSocketPeer implements Peer {
  final Transport _transport;
  final StreamController<GunMessage> _incomingMessages = StreamController.broadcast();
  final Set<String> _knownNodes = {};
  final PeerHandshakeManager _handshakeManager = PeerHandshakeManager();
  late StreamSubscription _transportSubscription;
  late String _localPeerId;
  PeerInfo? _remotePeerInfo;
  
  /// Create a WebSocket peer
  /// 
  /// [url] - WebSocket URL to connect to
  /// [transport] - Optional transport implementation (defaults to WebSocketTransport)
  WebSocketPeer(String url, [Transport? transport])
      : _transport = transport ?? WebSocketTransport(url) {
    _localPeerId = _handshakeManager.generatePeerId();
    _setupMessageHandler();
  }
  
  @override
  String get url => _transport.url;
  
  @override
  bool get isConnected => _transport.isConnected;
  
  /// Stream of connection state changes
  Stream<bool> get connectionState => _transport.connectionState;
  
  @override
  Stream<Map<String, dynamic>> get messages => _transport.messages;
  
  /// Stream of Gun messages specifically
  Stream<GunMessage> get gunMessages => _incomingMessages.stream;
  
  @override
  Future<void> connect() async {
    await _transport.connect();
    
    // Note: Gun.js interoperability confirmed working
    // Handshake can be skipped as Gun.js accepts PUT messages without handshake
    print('WebSocketPeer: Connected to ${_transport.url}');
    
    // Optionally attempt handshake, but don't fail if it doesn't work
    // Some Gun.js servers may not support the same handshake protocol
    try {
      _remotePeerInfo = await _handshakeManager.initiateHandshake(
        _localPeerId,
        (message) => _transport.send(message),
      );
      print('WebSocketPeer: Handshake completed with ${_remotePeerInfo?.id}');
    } catch (e) {
      print('WebSocketPeer: Handshake not completed (${e}), continuing anyway');
      // This is fine - Gun.js interop works without handshake
    }
  }
  
  @override
  Future<void> disconnect() async {
    // Send bye messages to all connected peers
    try {
      final byeMessages = await _handshakeManager.disconnectAll(_localPeerId);
      for (final message in byeMessages) {
        await _transport.send(message);
      }
    } catch (e) {
      print('WebSocketPeer: Error sending bye messages: $e');
    }
    
    await _transport.disconnect();
  }
  
  @override
  Future<void> send(Map<String, dynamic> data) async {
    await _transport.send(data);
  }
  
  @override
  Future<void> close() async {
    await _transportSubscription.cancel();
    await _incomingMessages.close();
    await _handshakeManager.dispose();
    await _transport.close();
  }
  
  /// Send a Gun message to this peer
  Future<void> sendGunMessage(GunMessage message) async {
    await send(message.toJson());
  }
  
  /// Send a GET request for specific data
  Future<void> get(String key) async {
    final message = GunMessage(
      type: GunMessageType.get,
      data: {'#': key},
      timestamp: DateTime.now(),
    );
    await sendGunMessage(message);
  }
  
  /// Send a PUT request with data
  Future<void> put(String key, Map<String, dynamic> data) async {
    final message = GunMessage(
      type: GunMessageType.put,
      data: {key: data},
      timestamp: DateTime.now(),
    );
    await sendGunMessage(message);
  }
  
  /// Get local peer ID
  String get localPeerId => _localPeerId;
  
  /// Get remote peer info
  PeerInfo? get remotePeerInfo => _remotePeerInfo;
  
  /// Get handshake statistics
  HandshakeStats get handshakeStats => _handshakeManager.getStats();
  
  /// Get connected peers from handshake manager
  List<PeerInfo> get connectedPeers => _handshakeManager.getConnectedPeers();
  
  /// Setup message handler to convert transport messages to Gun messages
  void _setupMessageHandler() {
    _transportSubscription = _transport.messages.listen((rawMessage) {
      try {
        // Skip empty messages
        if (rawMessage.isEmpty) return;
        
        // DEBUG: Log all incoming WebSocket messages
        print('WebSocketPeer: Raw message received: ${rawMessage.toString()}');
        print('WebSocketPeer: Message keys: ${rawMessage.keys.toList()}');
        
        // Check for PUT messages specifically
        if (rawMessage.containsKey('put')) {
          print('WebSocketPeer: PUT message detected!');
          print('WebSocketPeer: PUT content: ${rawMessage['put']}');
        }
        
        // First, try to handle as wire protocol message
        _handleWireMessage(rawMessage);
      } catch (e) {
        print('WebSocketPeer: Wire protocol parsing failed: $e');
        // If wire protocol fails, try as handshake message
        try {
          _handleHandshakeMessage(rawMessage);
        } catch (e2) {
          print('WebSocketPeer: Handshake parsing failed: $e2');
          // If handshake fails, try as regular Gun message
          try {
            final gunMessage = GunMessage.fromJson(rawMessage);
            _handleGunMessage(gunMessage);
          } catch (e3) {
            print('WebSocketPeer: All parsing failed for message: ${rawMessage.keys}');
            print('WebSocketPeer: Final error: $e3');
          }
        }
      }
    });
  }
  
  /// Handle incoming Gun messages
  void _handleGunMessage(GunMessage message) {
    switch (message.type) {
      case GunMessageType.hi:
        _handleHandshake(message);
        break;
      case GunMessageType.get:
        _handleGet(message);
        break;
      case GunMessageType.put:
        _handlePut(message);
        break;
      case GunMessageType.bye:
        _handleBye(message);
        break;
      case GunMessageType.dam:
        _handleDam(message);
        break;
      case GunMessageType.ok:
        _handleOk(message);
        break;
      case GunMessageType.unknown:
        _handleUnknown(message);
        break;
    }
    
    // Forward to subscribers
    _incomingMessages.add(message);
  }
  
  /// Handle incoming handshake messages
  Future<void> _handleHandshakeMessage(Map<String, dynamic> rawMessage) async {
    try {
      final responseMessage = await _handshakeManager.handleHandshakeMessage(
        rawMessage,
        _localPeerId,
        (message) => _transport.send(message),
      );
      
      if (responseMessage != null) {
        await _transport.send(responseMessage);
      }
    } catch (e) {
      print('WebSocketPeer: Error handling handshake: $e');
    }
  }
  
  /// Handle wire protocol messages directly
  Future<void> _handleWireMessage(Map<String, dynamic> rawMessage) async {
    try {
      print('WebSocketPeer: Parsing wire message with keys: ${rawMessage.keys.toList()}');
      final wireMessage = GunWireProtocol.parseMessage(rawMessage);
      
      print('WebSocketPeer: Parsed wire message type: ${wireMessage.type}');
      
      // Handle different message types
      switch (wireMessage.type) {
        case GunMessageType.hi:
          print('WebSocketPeer: Processing HI message');
          try {
            await _handleHandshakeMessage(rawMessage);
          } catch (e) {
            print('WebSocketPeer: Handshake handling failed: $e');
          }
          break;
        case GunMessageType.bye:
          print('WebSocketPeer: Processing BYE message');
          try {
            await _handleHandshakeMessage(rawMessage);
          } catch (e) {
            print('WebSocketPeer: Bye handling failed: $e');
          }
          break;
        case GunMessageType.dam:
          // Handle DAM messages specially - these are often acknowledgments or errors
          print('WebSocketPeer: Received DAM message: ${wireMessage.dam}');
          final gunMessage = _wireMessageToGunMessage(wireMessage);
          _handleGunMessage(gunMessage);
          break;
        case GunMessageType.ok:
          // Handle OK acknowledgments
          print('WebSocketPeer: Received OK acknowledgment');
          final gunMessage = _wireMessageToGunMessage(wireMessage);
          _handleGunMessage(gunMessage);
          break;
        case GunMessageType.get:
          print('WebSocketPeer: Processing GET message');
          final gunMessage = _wireMessageToGunMessage(wireMessage);
          _handleGunMessage(gunMessage);
          break;
        case GunMessageType.put:
          print('WebSocketPeer: Processing PUT message!');
          print('WebSocketPeer: PUT data: ${wireMessage.put}');
          final gunMessage = _wireMessageToGunMessage(wireMessage);
          print('WebSocketPeer: Converted to GunMessage with data: ${gunMessage.data}');
          _handleGunMessage(gunMessage);
          break;
        case GunMessageType.unknown:
          print('WebSocketPeer: Processing UNKNOWN message type');
          // Convert to GunMessage and handle normally
          final gunMessage = _wireMessageToGunMessage(wireMessage);
          _handleGunMessage(gunMessage);
          break;
      }
    } catch (e) {
      print('WebSocketPeer: Wire message parsing failed: $e');
      rethrow;
    }
  }
  
  /// Convert wire message to Gun message format
  GunMessage _wireMessageToGunMessage(GunWireMessage wireMessage) {
    Map<String, dynamic> data = {};
    
    try {
      // Safely add data from different message types
      if (wireMessage.get != null) {
        data.addAll(wireMessage.get!);
      }
      
      // For PUT messages, the structure is { "put": { "nodeId": nodeData } }
      // We need to extract the individual nodes and put them directly in data
      if (wireMessage.put != null) {
        // Don't add the 'put' wrapper, extract the individual nodes
        data.addAll(wireMessage.put!);
      }
      
      if (wireMessage.hi != null) {
        data.addAll(wireMessage.hi!);
      }
      
      if (wireMessage.bye != null) {
        if (wireMessage.bye is Map<String, dynamic>) {
          data.addAll(wireMessage.bye as Map<String, dynamic>);
        } else {
          data['bye'] = wireMessage.bye;
        }
      }
      
      if (wireMessage.dam != null) {
        data['dam'] = wireMessage.dam;
      }
      
      if (wireMessage.ok != null) {
        data['ok'] = wireMessage.ok;
      }
      
      // If no specific data was found, include the raw message
      if (data.isEmpty && wireMessage.raw.isNotEmpty) {
        // Filter out protocol fields and include the rest as data
        for (final entry in wireMessage.raw.entries) {
          final key = entry.key;
          if (key != '@' && key != '#' && key != '##' && key != 'FOO' && key != 'pid') {
            data[key] = entry.value;
          }
        }
      }
      
    } catch (e) {
      print('WebSocketPeer: Error converting wire message: $e');
      // Fallback to raw data
      data = Map<String, dynamic>.from(wireMessage.raw);
    }
    
    return GunMessage(
      type: wireMessage.type,
      data: data,
      id: wireMessage.messageId,
      timestamp: DateTime.now(),
    );
  }
  
  /// Handle handshake messages (legacy method)
  void _handleHandshake(GunMessage message) {
    print('WebSocketPeer: Received legacy handshake from ${message.data}');
  }
  
  /// Handle GET requests
  void _handleGet(GunMessage message) {
    final key = message.data['#'] as String?;
    if (key != null) {
      _knownNodes.add(key);
    }
  }
  
  /// Handle PUT requests
  void _handlePut(GunMessage message) {
    // Process incoming PUT messages from Gun.js - these contain data updates
    try {
      for (final entry in message.data.entries) {
        final nodeId = entry.key;
        final nodeData = entry.value;
        
        if (nodeData is Map<String, dynamic>) {
          _knownNodes.add(nodeId);
          
          // This is an incoming data update from Gun.js
          print('WebSocketPeer: Processing PUT for node: $nodeId');
          
          // Note: The Gun instance will process this message via the gunMessages stream
        }
      }
    } catch (e) {
      print('WebSocketPeer: Error processing PUT message: $e');
    }
  }
  
  /// Handle bye messages
  void _handleBye(GunMessage message) {
    print('WebSocketPeer: Peer disconnecting: ${message.data}');
  }
  
  /// Handle DAM (Data Acknowledgment Message) messages
  void _handleDam(GunMessage message) {
    print('WebSocketPeer: Received acknowledgment: ${message.data}');
  }
  
  /// Handle OK acknowledgment messages
  void _handleOk(GunMessage message) {
    print('WebSocketPeer: Received OK response: ${message.data}');
  }
  
  /// Handle unknown message types
  void _handleUnknown(GunMessage message) {
    print('WebSocketPeer: Received unknown message type: ${message.data}');
  }
  
  /// Get peer statistics
  Map<String, dynamic> getStats() {
    return {
      'url': url,
      'isConnected': isConnected,
      'knownNodes': _knownNodes.length,
      'transport': _transport is WebSocketTransport 
          ? (_transport as WebSocketTransport).getStats()
          : {'type': _transport.runtimeType.toString()},
    };
  }
  
  /// Get known node keys from this peer
  Set<String> get knownNodes => Set.unmodifiable(_knownNodes);
  
  /// Check if this peer knows about a specific node
  bool knowsNode(String key) => _knownNodes.contains(key);
}
