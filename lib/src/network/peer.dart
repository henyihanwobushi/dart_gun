import 'dart:async';
import '../types/types.dart';
import 'gun_wire_protocol.dart';
import 'transport.dart';
import 'websocket_transport.dart';
import 'peer_handshake.dart';
import '../utils/utils.dart';

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
    
    // Initiate Gun.js compatible handshake
    try {
      _remotePeerInfo = await _handshakeManager.initiateHandshake(
        _localPeerId,
        (message) => _transport.send(message),
      );
      print('WebSocketPeer: Handshake completed with ${_remotePeerInfo?.id}');
    } catch (e) {
      print('WebSocketPeer: Handshake failed: $e');
      // Continue even if handshake fails - some peers might not support it
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
        // First, try to handle as handshake message
        _handleHandshakeMessage(rawMessage);
        
        // Then handle as regular Gun message
        final gunMessage = GunMessage.fromJson(rawMessage);
        _handleGunMessage(gunMessage);
      } catch (e) {
        print('WebSocketPeer: Failed to parse message: $e');
        // Try to handle as wire protocol message directly
        try {
          _handleWireMessage(rawMessage);
        } catch (e2) {
          print('WebSocketPeer: Failed to handle wire message: $e2');
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
    final wireMessage = GunWireProtocol.parseMessage(rawMessage);
    
    // Handle different message types
    switch (wireMessage.type) {
      case GunMessageType.hi:
        await _handleHandshakeMessage(rawMessage);
        break;
      case GunMessageType.bye:
        await _handleHandshakeMessage(rawMessage);
        break;
      case GunMessageType.get:
        // Convert to GunMessage and handle normally
        final gunMessage = _wireMessageToGunMessage(wireMessage);
        _handleGunMessage(gunMessage);
        break;
      case GunMessageType.put:
        // Convert to GunMessage and handle normally
        final gunMessage = _wireMessageToGunMessage(wireMessage);
        _handleGunMessage(gunMessage);
        break;
      default:
        // Handle other message types normally
        final gunMessage = _wireMessageToGunMessage(wireMessage);
        _handleGunMessage(gunMessage);
        break;
    }
  }
  
  /// Convert wire message to Gun message format
  GunMessage _wireMessageToGunMessage(GunWireMessage wireMessage) {
    Map<String, dynamic> data = {};
    
    if (wireMessage.get != null) data.addAll(wireMessage.get!);
    if (wireMessage.put != null) data.addAll(wireMessage.put!);
    if (wireMessage.hi != null) data.addAll(wireMessage.hi!);
    if (wireMessage.bye != null) {
      if (wireMessage.bye is Map<String, dynamic>) {
        data.addAll(wireMessage.bye as Map<String, dynamic>);
      } else {
        data['bye'] = wireMessage.bye;
      }
    }
    if (wireMessage.dam != null) data['dam'] = wireMessage.dam;
    if (wireMessage.ok != null) data['ok'] = wireMessage.ok;
    
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
    // Extract node keys from the put data
    for (final key in message.data.keys) {
      _knownNodes.add(key);
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
