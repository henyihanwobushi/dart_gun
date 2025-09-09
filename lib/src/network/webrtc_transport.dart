import 'dart:async';
import 'dart:convert';
import 'transport.dart';

/// WebRTC data channel transport for Gun networking
/// 
/// Provides peer-to-peer communication over WebRTC data channels.
/// Ideal for direct browser-to-browser or mobile-to-mobile communication
/// without requiring intermediary servers.
/// 
/// Note: This is a simplified WebRTC implementation for demonstration.
/// In production, you would use packages like flutter_webrtc or similar.
class WebRtcTransport extends BaseTransport {
  final String _peerId;
  final Map<String, dynamic> _config;
  
  bool _isConnected = false;
  String? _connectionUrl;
  final StreamController<Map<String, dynamic>> _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<bool> _connectionStateController = StreamController<bool>.broadcast();
  
  // Simulated WebRTC connection state
  String _connectionState = 'new';
  String _dataChannelState = 'closed';
  final List<Map<String, dynamic>> _pendingMessages = [];

  WebRtcTransport({
    required String peerId,
    Map<String, dynamic>? config,
  })  : _peerId = peerId,
        _config = {
          'iceServers': [
            {'urls': 'stun:stun.l.google.com:19302'},
            {'urls': 'stun:stun1.l.google.com:19302'},
          ],
          'iceCandidatePoolSize': 10,
          ...?config,
        },
        super();

  @override
  String get url => _connectionUrl ?? 'webrtc://$_peerId';

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  @override
  Stream<bool> get connectionState => _connectionStateController.stream;

  /// WebRTC connection state string
  String get webRtcConnectionState => _connectionState;

  /// Data channel state
  String get dataChannelState => _dataChannelState;

  @override
  Future<void> connect() async {
    if (_isConnected) return;

    try {
      print('WebRTC transport initiating connection to peer $_peerId');
      
      // Simulate WebRTC connection process
      await _simulateWebRtcHandshake();
      
      _isConnected = true;
      _connectionState = 'connected';
      _dataChannelState = 'open';
      _connectionUrl = 'webrtc://$_peerId';
      _connectionStateController.add(true);
      
      print('WebRTC transport connected to peer $_peerId');
      
      // Send hi message
      await send({
        'hi': {'gun': '0.1.0', 'peer': 'dart_webrtc'},
      });
      
      // Process any pending messages
      for (final message in _pendingMessages) {
        _messageController.add(message);
      }
      _pendingMessages.clear();
      
    } catch (e) {
      _isConnected = false;
      _connectionState = 'failed';
      print('WebRTC transport connection failed: $e');
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    if (!_isConnected) return;

    try {
      // Send bye message
      await send({
        'bye': {'peer': 'dart_webrtc'},
      });
    } catch (e) {
      print('Failed to send bye message: $e');
    }

    _isConnected = false;
    _connectionState = 'closed';
    _dataChannelState = 'closed';
    _connectionUrl = null;
    _connectionStateController.add(false);
    
    print('WebRTC transport disconnected from peer $_peerId');
  }

  @override
  Future<void> send(Map<String, dynamic> message) async {
    if (!_isConnected) {
      throw StateError('WebRTC transport is not connected');
    }

    if (_dataChannelState != 'open') {
      throw StateError('WebRTC data channel is not open');
    }

    try {
      // Simulate sending message over WebRTC data channel
      final messageData = jsonEncode(message);
      await _simulateDataChannelSend(messageData);
      
      print('WebRTC message sent');
    } catch (e) {
      print('Failed to send WebRTC message: $e');
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    await disconnect();
    await _messageController.close();
    await _connectionStateController.close();
  }

  /// Create an offer for establishing WebRTC connection
  Future<Map<String, dynamic>> createOffer() async {
    if (_isConnected) {
      throw StateError('Connection already established');
    }

    // Simulate WebRTC offer creation
    return {
      'type': 'offer',
      'sdp': _generateMockSdp('offer'),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }

  /// Create an answer for WebRTC connection
  Future<Map<String, dynamic>> createAnswer(Map<String, dynamic> offer) async {
    if (_isConnected) {
      throw StateError('Connection already established');
    }

    // Validate offer
    if (offer['type'] != 'offer' || offer['sdp'] == null) {
      throw ArgumentError('Invalid WebRTC offer');
    }

    // Simulate WebRTC answer creation
    return {
      'type': 'answer',
      'sdp': _generateMockSdp('answer'),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }

  /// Set remote description (offer or answer)
  Future<void> setRemoteDescription(Map<String, dynamic> description) async {
    final type = description['type'];
    final sdp = description['sdp'];
    
    if (type == null || sdp == null) {
      throw ArgumentError('Invalid remote description');
    }

    print('WebRTC setting remote description: $type');
    
    // Simulate processing remote description
    await Future.delayed(const Duration(milliseconds: 100));
    
    if (type == 'offer') {
      _connectionState = 'have-remote-offer';
    } else if (type == 'answer') {
      _connectionState = 'stable';
    }
  }

  /// Add ICE candidate
  Future<void> addIceCandidate(Map<String, dynamic> candidate) async {
    final candidateString = candidate['candidate'];
    final sdpMid = candidate['sdpMid'];
    final sdpMLineIndex = candidate['sdpMLineIndex'];
    
    if (candidateString == null) {
      throw ArgumentError('Invalid ICE candidate');
    }

    print('WebRTC adding ICE candidate: $candidateString');
    
    // Simulate ICE candidate processing
    await Future.delayed(const Duration(milliseconds: 50));
  }

  /// Get local ICE candidates (simulated)
  Stream<Map<String, dynamic>> get iceCandidate async* {
    // Simulate ICE candidate gathering
    await Future.delayed(const Duration(milliseconds: 200));
    
    final candidates = [
      {
        'candidate': 'candidate:1 1 UDP 2122260223 192.168.1.100 54400 typ host',
        'sdpMid': 'data',
        'sdpMLineIndex': 0,
      },
      {
        'candidate': 'candidate:2 1 UDP 1686052607 203.0.113.100 54401 typ srflx raddr 192.168.1.100 rport 54400',
        'sdpMid': 'data', 
        'sdpMLineIndex': 0,
      },
    ];
    
    for (final candidate in candidates) {
      yield candidate;
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  /// Simulate WebRTC handshake process
  Future<void> _simulateWebRtcHandshake() async {
    // Simulate connection establishment phases
    _connectionState = 'connecting';
    await Future.delayed(const Duration(milliseconds: 300));
    
    _connectionState = 'connected';
    await Future.delayed(const Duration(milliseconds: 100));
    
    _dataChannelState = 'connecting';
    await Future.delayed(const Duration(milliseconds: 200));
    
    _dataChannelState = 'open';
  }

  /// Simulate sending data over WebRTC data channel
  Future<void> _simulateDataChannelSend(String data) async {
    // Simulate network latency
    await Future.delayed(const Duration(milliseconds: 10));
    
    // Simulate receiving echo or response (for testing)
    if (data.contains('"hi"') && !_messageController.isClosed) {
      Timer(const Duration(milliseconds: 50), () {
        if (!_messageController.isClosed) {
          _messageController.add({
            'hi': {'gun': '0.1.0', 'peer': _peerId},
          });
        }
      });
    }
  }

  /// Generate mock SDP for testing
  String _generateMockSdp(String type) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '''v=0
o=- $timestamp 2 IN IP4 127.0.0.1
s=-
t=0 0
a=group:BUNDLE data
a=msid-semantic: WMS
m=application 9 DTLS/SCTP 5000
c=IN IP4 0.0.0.0
a=ice-ufrag:${_generateRandomString(4)}
a=ice-pwd:${_generateRandomString(22)}
a=ice-options:trickle
a=fingerprint:sha-256 ${_generateRandomString(95, ':').toUpperCase()}
a=setup:${type == 'offer' ? 'actpass' : 'active'}
a=mid:data
a=sctpmap:5000 webrtc-datachannel 1024''';
  }

  /// Generate random string for mock data
  String _generateRandomString(int length, [String separator = '']) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = DateTime.now().millisecondsSinceEpoch;
    var result = '';
    
    for (int i = 0; i < length; i++) {
      if (separator.isNotEmpty && i > 0 && i % 2 == 0) {
        result += separator;
      }
      result += chars[(random + i) % chars.length];
    }
    
    return result;
  }
}
