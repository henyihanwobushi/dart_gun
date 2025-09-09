import 'package:test/test.dart';
import 'dart:async';

import '../lib/src/network/peer_handshake.dart';
import '../lib/src/network/gun_wire_protocol.dart';
import '../lib/src/utils/utils.dart';

void main() {
  group('PeerHandshakeManager Tests', () {
    late PeerHandshakeManager handshakeManager;
    late List<Map<String, dynamic>> sentMessages;
    late Function(Map<String, dynamic>) mockSendMessage;
    
    setUp(() {
      handshakeManager = PeerHandshakeManager();
      sentMessages = [];
      mockSendMessage = (message) {
        sentMessages.add(message);
        return Future.value();
      };
    });
    
    tearDown(() async {
      await handshakeManager.dispose();
    });
    
    test('should generate unique peer IDs', () {
      final peerId1 = handshakeManager.generatePeerId();
      final peerId2 = handshakeManager.generatePeerId();
      
      expect(peerId1, isNot(equals(peerId2)));
      expect(peerId1, startsWith('dart-'));
      expect(peerId2, startsWith('dart-'));
      expect(peerId1.length, equals(13)); // "dart-" + 8 random chars
    });
    
    test('should initiate handshake with proper Gun.js format', () async {
      final peerId = handshakeManager.generatePeerId();
      
      // Start handshake (don't await - it will timeout)
      final handshakeFuture = handshakeManager.initiateHandshake(
        peerId,
        mockSendMessage,
      );
      
      // Give it time to send the message
      await Future.delayed(Duration(milliseconds: 10));
      
      expect(sentMessages.length, equals(1));
      
      final sentMessage = sentMessages.first;
      expect(sentMessage['hi'], isNotNull);
      expect(sentMessage['hi']['gun'], equals('dart-0.3.0'));
      expect(sentMessage['hi']['pid'], equals(peerId));
      expect(sentMessage['@'], isNotNull);
      
      // Cancel the handshake to avoid timeout
      try {
        await handshakeFuture.timeout(Duration(milliseconds: 50));
      } catch (e) {
        // Expected timeout
      }
    });
    
    test('should handle incoming hi message and respond', () async {
      final localPeerId = 'dart-local123';
      final remotePeerId = 'gunjs-remote456';
      
      final incomingHi = {
        'hi': {
          'gun': '0.2020.1235',
          'pid': remotePeerId,
        },
        '@': 'handshake-msg-789',
      };
      
      final response = await handshakeManager.handleHandshakeMessage(
        incomingHi,
        localPeerId,
        mockSendMessage,
      );
      
      expect(response, isNotNull);
      expect(response!['hi'], isNotNull);
      expect(response['hi']['gun'], equals('dart-0.3.0'));
      expect(response['hi']['pid'], equals(localPeerId));
      expect(response['#'], equals('handshake-msg-789')); // Ack original message
      
      // Check that peer was registered
      final peerInfo = handshakeManager.getPeerInfo(remotePeerId);
      expect(peerInfo, isNotNull);
      expect(peerInfo!.version, equals('0.2020.1235'));
      expect(peerInfo.status, equals(PeerStatus.connected));
    });
    
    test('should handle handshake acknowledgment', () async {
      final peerId = handshakeManager.generatePeerId();
      
      // Start handshake
      final handshakeFuture = handshakeManager.initiateHandshake(
        peerId,
        mockSendMessage,
      );
      
      await Future.delayed(Duration(milliseconds: 10));
      final originalMessage = sentMessages.first;
      final messageId = originalMessage['@'];
      
      // Send acknowledgment response
      final ackResponse = {
        'ok': true,
        'hi': {
          'gun': '0.2020.1235',
          'pid': 'gunjs-peer-abc',
        },
        '@': 'response-msg-456',
        '#': messageId, // Acknowledge original message
      };
      
      await handshakeManager.handleHandshakeMessage(
        ackResponse,
        peerId,
        mockSendMessage,
      );
      
      // The handshake should complete successfully
      final peerInfo = await handshakeFuture;
      expect(peerInfo.id, equals('gunjs-peer-abc'));
      expect(peerInfo.version, equals('0.2020.1235'));
      expect(peerInfo.status, equals(PeerStatus.connected));
    });
    
    test('should handle handshake timeout', () async {
      final peerId = handshakeManager.generatePeerId();
      
      expect(
        () => handshakeManager.initiateHandshake(peerId, mockSendMessage)
            .timeout(Duration(milliseconds: 100)),
        throwsA(isA<TimeoutException>()),
      );
    });
    
    test('should reject invalid handshake messages', () async {
      final localPeerId = 'dart-local123';
      
      // Missing version
      final invalidHi1 = {
        'hi': {
          'pid': 'some-peer',
        },
        '@': 'invalid-msg-1',
      };
      
      final response1 = await handshakeManager.handleHandshakeMessage(
        invalidHi1,
        localPeerId,
        mockSendMessage,
      );
      
      expect(response1, isNotNull);
      expect(response1!['dam'], isNotNull);
      expect(response1['dam'], contains('missing version or peer ID'));
      
      // Missing peer ID
      final invalidHi2 = {
        'hi': {
          'gun': '0.2020.1235',
        },
        '@': 'invalid-msg-2',
      };
      
      final response2 = await handshakeManager.handleHandshakeMessage(
        invalidHi2,
        localPeerId,
        mockSendMessage,
      );
      
      expect(response2, isNotNull);
      expect(response2!['dam'], isNotNull);
      expect(response2['dam'], contains('missing version or peer ID'));
    });
    
    test('should handle bye messages for graceful disconnection', () async {
      final localPeerId = 'dart-local123';
      final remotePeerId = 'gunjs-remote456';
      
      // First establish connection
      final incomingHi = {
        'hi': {
          'gun': '0.2020.1235',
          'pid': remotePeerId,
        },
        '@': 'handshake-msg-789',
      };
      
      await handshakeManager.handleHandshakeMessage(
        incomingHi,
        localPeerId,
        mockSendMessage,
      );
      
      // Verify peer is connected
      expect(handshakeManager.getPeerInfo(remotePeerId)?.status, 
          equals(PeerStatus.connected));
      
      // Send bye message
      final byeMessage = {
        'bye': {'#': remotePeerId},
        '@': 'bye-msg-123',
      };
      
      final response = await handshakeManager.handleHandshakeMessage(
        byeMessage,
        localPeerId,
        mockSendMessage,
      );
      
      expect(response, isNotNull);
      expect(response!['ok'], isNotNull);
      expect(response['#'], equals('bye-msg-123')); // Ack bye message
      
      // Verify peer is disconnected
      expect(handshakeManager.getPeerInfo(remotePeerId)?.status, 
          equals(PeerStatus.disconnected));
    });
    
    test('should generate disconnect messages for all peers', () async {
      final localPeerId = 'dart-local123';
      
      // Add some connected peers
      final peer1Hi = {
        'hi': {'gun': '0.2020.1235', 'pid': 'peer1'},
        '@': 'msg1',
      };
      final peer2Hi = {
        'hi': {'gun': '0.2020.1235', 'pid': 'peer2'},
        '@': 'msg2',
      };
      
      await handshakeManager.handleHandshakeMessage(peer1Hi, localPeerId, mockSendMessage);
      await handshakeManager.handleHandshakeMessage(peer2Hi, localPeerId, mockSendMessage);
      
      expect(handshakeManager.getConnectedPeers().length, equals(2));
      
      // Disconnect all
      final byeMessages = await handshakeManager.disconnectAll(localPeerId);
      
      expect(byeMessages.length, equals(2));
      for (final message in byeMessages) {
        expect(message['bye'], isNotNull);
        expect(message['@'], isNotNull);
      }
      
      // All peers should be marked as disconnected
      expect(handshakeManager.getConnectedPeers().length, equals(0));
    });
    
    test('should provide accurate handshake statistics', () async {
      final localPeerId = 'dart-local123';
      
      // Initially no peers
      var stats = handshakeManager.getStats();
      expect(stats.totalPeers, equals(0));
      expect(stats.connectedPeers, equals(0));
      expect(stats.disconnectedPeers, equals(0));
      expect(stats.pendingHandshakes, equals(0));
      
      // Add connected peer
      final peerHi = {
        'hi': {'gun': '0.2020.1235', 'pid': 'peer1'},
        '@': 'msg1',
      };
      await handshakeManager.handleHandshakeMessage(peerHi, localPeerId, mockSendMessage);
      
      stats = handshakeManager.getStats();
      expect(stats.totalPeers, equals(1));
      expect(stats.connectedPeers, equals(1));
      expect(stats.disconnectedPeers, equals(0));
      
      // Start pending handshake
      final pendingFuture = handshakeManager.initiateHandshake(
        'local-peer',
        mockSendMessage,
      );
      
      await Future.delayed(Duration(milliseconds: 10));
      
      stats = handshakeManager.getStats();
      expect(stats.pendingHandshakes, equals(1));
      
      // Cancel pending handshake
      try {
        await pendingFuture.timeout(Duration(milliseconds: 50));
      } catch (e) {
        // Expected timeout
      }
    });
    
    test('should handle version compatibility checking', () async {
      final localPeerId = 'dart-local123';
      
      // Compatible version should work
      final compatibleHi = {
        'hi': {
          'gun': '0.2020.1235',
          'pid': 'compatible-peer',
        },
        '@': 'compatible-msg',
      };
      
      final response = await handshakeManager.handleHandshakeMessage(
        compatibleHi,
        localPeerId,
        mockSendMessage,
      );
      
      expect(response, isNotNull);
      expect(response!['hi'], isNotNull); // Should respond with hi
      expect(handshakeManager.getPeerInfo('compatible-peer'), isNotNull);
      
      // For now, we accept all non-empty versions
      // In production, implement semantic version checking
      final futureVersion = {
        'hi': {
          'gun': '1.0.0',
          'pid': 'future-peer',
        },
        '@': 'future-msg',
      };
      
      final futureResponse = await handshakeManager.handleHandshakeMessage(
        futureVersion,
        localPeerId,
        mockSendMessage,
      );
      
      expect(futureResponse, isNotNull);
      expect(futureResponse!['hi'], isNotNull);
    });
  });
  
  group('PeerInfo Tests', () {
    test('should create PeerInfo with all required fields', () {
      final now = DateTime.now();
      final peerInfo = PeerInfo(
        id: 'test-peer-123',
        version: '0.2020.1235',
        status: PeerStatus.connected,
        connectedAt: now,
      );
      
      expect(peerInfo.id, equals('test-peer-123'));
      expect(peerInfo.version, equals('0.2020.1235'));
      expect(peerInfo.status, equals(PeerStatus.connected));
      expect(peerInfo.connectedAt, equals(now));
      expect(peerInfo.disconnectedAt, isNull);
      expect(peerInfo.metadata, isEmpty);
    });
    
    test('should support copyWith for immutable updates', () {
      final original = PeerInfo(
        id: 'peer-123',
        version: '0.2020.1235',
        status: PeerStatus.connected,
        connectedAt: DateTime.now(),
      );
      
      final updated = original.copyWith(
        status: PeerStatus.disconnected,
        disconnectedAt: DateTime.now(),
      );
      
      expect(updated.id, equals(original.id));
      expect(updated.version, equals(original.version));
      expect(updated.connectedAt, equals(original.connectedAt));
      expect(updated.status, equals(PeerStatus.disconnected));
      expect(updated.disconnectedAt, isNotNull);
    });
    
    test('should serialize to and from JSON', () {
      final peerInfo = PeerInfo(
        id: 'test-peer',
        version: '0.2020.1235',
        status: PeerStatus.connected,
        connectedAt: DateTime.parse('2024-01-01T12:00:00Z'),
        metadata: {'extra': 'data'},
      );
      
      final json = peerInfo.toJson();
      expect(json['id'], equals('test-peer'));
      expect(json['version'], equals('0.2020.1235'));
      expect(json['status'], equals('connected'));
      expect(json['connectedAt'], equals('2024-01-01T12:00:00.000Z'));
      expect(json['metadata'], equals({'extra': 'data'}));
    });
  });
  
  group('HandshakeStats Tests', () {
    test('should provide meaningful string representation', () {
      final stats = HandshakeStats(
        totalPeers: 5,
        connectedPeers: 3,
        disconnectedPeers: 2,
        pendingHandshakes: 1,
      );
      
      final str = stats.toString();
      expect(str, contains('total: 5'));
      expect(str, contains('connected: 3'));
      expect(str, contains('disconnected: 2'));
      expect(str, contains('pending: 1'));
    });
  });
}
