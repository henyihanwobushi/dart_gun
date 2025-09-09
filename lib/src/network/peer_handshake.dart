import 'dart:async';
import '../utils/utils.dart';
import 'gun_wire_protocol.dart';

/// Gun.js compatible peer handshake and discovery system
/// 
/// This class manages the complete handshake lifecycle between Gun Dart
/// and Gun.js peers, ensuring full protocol compatibility.
class PeerHandshakeManager {
  final Map<String, PeerInfo> _peers = {};
  final Map<String, Timer> _handshakeTimeouts = {};
  final Map<String, Completer<PeerInfo>> _pendingHandshakes = {};
  
  /// Gun Dart version string for handshakes
  static const String gunVersion = 'dart-0.3.0';
  
  /// Default handshake timeout (5 seconds)
  static const Duration handshakeTimeout = Duration(seconds: 5);
  
  /// Generate a unique peer ID
  String generatePeerId() {
    return 'dart-${Utils.randomString(8)}';
  }
  
  /// Initiate handshake with a peer
  /// 
  /// Returns a Future that completes with peer info when handshake succeeds
  Future<PeerInfo> initiateHandshake(String peerId, Function(Map<String, dynamic>) sendMessage) async {
    final messageId = Utils.randomString(8);
    final completer = Completer<PeerInfo>();
    
    // Store pending handshake
    _pendingHandshakes[messageId] = completer;
    
    // Set up timeout
    final timer = Timer(handshakeTimeout, () {
      if (!completer.isCompleted) {
        _pendingHandshakes.remove(messageId);
        completer.completeError(TimeoutException('Handshake timeout', handshakeTimeout));
      }
    });
    _handshakeTimeouts[messageId] = timer;
    
    // Send handshake message
    final hiMessage = GunWireProtocol.createHiMessage(
      messageId: messageId,
      version: gunVersion,
      peerId: peerId,
    );
    
    await sendMessage(hiMessage);
    
    return completer.future;
  }
  
  /// Handle incoming handshake message
  /// 
  /// Returns response message to send back, or null if no response needed
  Future<Map<String, dynamic>?> handleHandshakeMessage(
    Map<String, dynamic> message,
    String localPeerId,
    Function(Map<String, dynamic>) sendMessage,
  ) async {
    final wireMessage = GunWireProtocol.parseMessage(message);
    
    if (wireMessage.hi != null && wireMessage.ackId == null) {
      return await _handleHiMessage(wireMessage, localPeerId, sendMessage);
    } else if (wireMessage.hi != null && wireMessage.ackId != null) {
      return await _handleHandshakeAck(wireMessage);
    } else if (wireMessage.bye != null) {
      return await _handleByeMessage(wireMessage);
    } else if (wireMessage.ok != null && wireMessage.ackId != null) {
      return await _handleHandshakeAck(wireMessage);
    }
    
    return null;
  }
  
  /// Handle 'hi' handshake initiation
  Future<Map<String, dynamic>?> _handleHiMessage(
    GunWireMessage wireMessage,
    String localPeerId,
    Function(Map<String, dynamic>) sendMessage,
  ) async {
    final hiData = wireMessage.hi!;
    final remotePeerVersion = hiData['gun'] as String?;
    final remotePeerId = hiData['pid'] as String?;
    
    if (remotePeerVersion == null || remotePeerId == null) {
      // Invalid handshake - send error
      return GunWireProtocol.createDamMessage(
        'Invalid handshake: missing version or peer ID',
        replyToMessageId: wireMessage.messageId,
      );
    }
    
    // Check version compatibility
    if (!_isVersionCompatible(remotePeerVersion)) {
      return GunWireProtocol.createDamMessage(
        'Incompatible Gun version: $remotePeerVersion',
        replyToMessageId: wireMessage.messageId,
      );
    }
    
    // Register the peer
    final peerInfo = PeerInfo(
      id: remotePeerId,
      version: remotePeerVersion,
      status: PeerStatus.connected,
      connectedAt: DateTime.now(),
    );
    
    _peers[remotePeerId] = peerInfo;
    
    // Send handshake response
    final responseMessage = GunWireProtocol.createHiMessage(
      version: gunVersion,
      peerId: localPeerId,
    );
    
    // Add acknowledgment to original message
    if (wireMessage.messageId != null) {
      responseMessage['#'] = wireMessage.messageId;
    }
    
    return responseMessage;
  }
  
  /// Handle 'bye' disconnect message
  Future<Map<String, dynamic>?> _handleByeMessage(GunWireMessage wireMessage) async {
    // Extract peer ID from bye message
    String? peerId;
    
    if (wireMessage.bye is Map<String, dynamic>) {
      peerId = (wireMessage.bye as Map<String, dynamic>)['#'] as String?;
    } else if (wireMessage.bye is String) {
      peerId = wireMessage.bye as String;
    }
    
    if (peerId != null && _peers.containsKey(peerId)) {
      final peer = _peers[peerId]!;
      _peers[peerId] = peer.copyWith(
        status: PeerStatus.disconnected,
        disconnectedAt: DateTime.now(),
      );
    }
    
    // Send acknowledgment if requested
    if (wireMessage.messageId != null) {
      return GunWireProtocol.createAckMessage(wireMessage.messageId!);
    }
    
    return null;
  }
  
  /// Handle handshake acknowledgment
  Future<Map<String, dynamic>?> _handleHandshakeAck(GunWireMessage wireMessage) async {
    final ackId = wireMessage.ackId!;
    final completer = _pendingHandshakes.remove(ackId);
    final timer = _handshakeTimeouts.remove(ackId);
    
    timer?.cancel();
    
    if (completer != null && wireMessage.hi != null) {
      final hiData = wireMessage.hi!;
      final peerVersion = hiData['gun'] as String?;
      final peerId = hiData['pid'] as String?;
      
      if (peerVersion != null && peerId != null) {
        final peerInfo = PeerInfo(
          id: peerId,
          version: peerVersion,
          status: PeerStatus.connected,
          connectedAt: DateTime.now(),
        );
        
        _peers[peerId] = peerInfo;
        completer.complete(peerInfo);
      } else {
        completer.completeError(Exception('Invalid handshake response'));
      }
    }
    
    return null;
  }
  
  /// Send disconnect message to all peers
  Future<List<Map<String, dynamic>>> disconnectAll(String localPeerId) async {
    final messages = <Map<String, dynamic>>[];
    
    for (final peer in _peers.values.where((p) => p.status == PeerStatus.connected)) {
      messages.add(GunWireProtocol.createByeMessage(peerId: localPeerId));
      
      // Update peer status
      _peers[peer.id] = peer.copyWith(
        status: PeerStatus.disconnected,
        disconnectedAt: DateTime.now(),
      );
    }
    
    return messages;
  }
  
  /// Get list of connected peers
  List<PeerInfo> getConnectedPeers() {
    return _peers.values.where((p) => p.status == PeerStatus.connected).toList();
  }
  
  /// Get peer info by ID
  PeerInfo? getPeerInfo(String peerId) {
    return _peers[peerId];
  }
  
  /// Check if two Gun versions are compatible
  bool _isVersionCompatible(String version) {
    // For now, accept all versions
    // In production, implement semantic version checking
    return version.isNotEmpty;
  }
  
  /// Get handshake statistics
  HandshakeStats getStats() {
    final connected = _peers.values.where((p) => p.status == PeerStatus.connected).length;
    final disconnected = _peers.values.where((p) => p.status == PeerStatus.disconnected).length;
    final pending = _pendingHandshakes.length;
    
    return HandshakeStats(
      totalPeers: _peers.length,
      connectedPeers: connected,
      disconnectedPeers: disconnected,
      pendingHandshakes: pending,
    );
  }
  
  /// Clean up resources
  Future<void> dispose() async {
    // Cancel all pending timeouts
    for (final timer in _handshakeTimeouts.values) {
      timer.cancel();
    }
    
    // Complete all pending handshakes with error
    for (final completer in _pendingHandshakes.values) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('Handshake manager disposed'));
      }
    }
    
    _handshakeTimeouts.clear();
    _pendingHandshakes.clear();
    _peers.clear();
  }
}

/// Information about a connected peer
class PeerInfo {
  final String id;
  final String version;
  final PeerStatus status;
  final DateTime connectedAt;
  final DateTime? disconnectedAt;
  final Map<String, dynamic> metadata;
  
  const PeerInfo({
    required this.id,
    required this.version,
    required this.status,
    required this.connectedAt,
    this.disconnectedAt,
    this.metadata = const {},
  });
  
  PeerInfo copyWith({
    String? id,
    String? version,
    PeerStatus? status,
    DateTime? connectedAt,
    DateTime? disconnectedAt,
    Map<String, dynamic>? metadata,
  }) {
    return PeerInfo(
      id: id ?? this.id,
      version: version ?? this.version,
      status: status ?? this.status,
      connectedAt: connectedAt ?? this.connectedAt,
      disconnectedAt: disconnectedAt ?? this.disconnectedAt,
      metadata: metadata ?? this.metadata,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'version': version,
      'status': status.name,
      'connectedAt': connectedAt.toIso8601String(),
      if (disconnectedAt != null) 'disconnectedAt': disconnectedAt!.toIso8601String(),
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
  
  @override
  String toString() => 'PeerInfo(id: $id, version: $version, status: $status)';
}

/// Peer connection status
enum PeerStatus {
  connecting,
  connected,
  disconnected,
  error,
}

/// Handshake statistics
class HandshakeStats {
  final int totalPeers;
  final int connectedPeers;
  final int disconnectedPeers;
  final int pendingHandshakes;
  
  const HandshakeStats({
    required this.totalPeers,
    required this.connectedPeers,
    required this.disconnectedPeers,
    required this.pendingHandshakes,
  });
  
  @override
  String toString() {
    return 'HandshakeStats(total: $totalPeers, connected: $connectedPeers, '
        'disconnected: $disconnectedPeers, pending: $pendingHandshakes)';
  }
}
