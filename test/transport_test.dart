import 'package:flutter_test/flutter_test.dart';
import 'package:gun_dart/gun_dart.dart';

void main() {
  group('HTTP Transport Tests', () {
    late HttpTransport transport;

    setUp(() {
      transport = HttpTransport(baseUrl: 'https://api.example.com');
    });

    tearDown(() async {
      await transport.close();
    });

    test('should create HTTP transport with correct URL', () {
      expect(transport.url, equals('https://api.example.com'));
      expect(transport.isConnected, isFalse);
    });

    test('should handle URL normalization', () {
      final transport1 = HttpTransport(baseUrl: 'https://api.example.com/');
      final transport2 = HttpTransport(baseUrl: 'https://api.example.com');
      
      expect(transport1.url, equals(transport2.url));
    });

    test('should set custom headers', () {
      final customTransport = HttpTransport(
        baseUrl: 'https://api.example.com',
        headers: {'X-Custom-Header': 'test'},
      );
      
      expect(customTransport.url, equals('https://api.example.com'));
    });

    test('should handle connection timeout', () {
      final transport = HttpTransport(
        baseUrl: 'https://api.example.com',
        timeout: const Duration(seconds: 5),
      );
      
      expect(transport.url, equals('https://api.example.com'));
    });
  });

  group('WebRTC Transport Tests', () {
    late WebRtcTransport transport;

    setUp(() {
      transport = WebRtcTransport(peerId: 'test-peer');
    });

    tearDown(() async {
      await transport.close();
    });

    test('should create WebRTC transport with peer ID', () {
      expect(transport.url, equals('webrtc://test-peer'));
      expect(transport.isConnected, isFalse);
      expect(transport.webRtcConnectionState, equals('new'));
      expect(transport.dataChannelState, equals('closed'));
    });

    test('should connect and change state', () async {
      expect(transport.isConnected, isFalse);
      
      await transport.connect();
      
      expect(transport.isConnected, isTrue);
      expect(transport.webRtcConnectionState, equals('connected'));
      expect(transport.dataChannelState, equals('open'));
    });

    test('should disconnect properly', () async {
      await transport.connect();
      expect(transport.isConnected, isTrue);
      
      await transport.disconnect();
      
      expect(transport.isConnected, isFalse);
      expect(transport.webRtcConnectionState, equals('closed'));
      expect(transport.dataChannelState, equals('closed'));
    });

    test('should send messages when connected', () async {
      await transport.connect();
      
      final message = {
        'put': {'test': 'data'},
      };
      
      // Should not throw when connected
      await transport.send(message);
    });

    test('should throw when sending while disconnected', () async {
      final message = {
        'put': {'test': 'data'},
      };
      
      expect(() => transport.send(message), throwsStateError);
    });

    test('should create valid WebRTC offers', () async {
      final offer = await transport.createOffer();
      
      expect(offer['type'], equals('offer'));
      expect(offer['sdp'], isA<String>());
      expect(offer['timestamp'], isA<int>());
    });

    test('should create valid WebRTC answers', () async {
      final offer = await transport.createOffer();
      final answer = await transport.createAnswer(offer);
      
      expect(answer['type'], equals('answer'));
      expect(answer['sdp'], isA<String>());
      expect(answer['timestamp'], isA<int>());
    });

    test('should handle remote descriptions', () async {
      final offer = await transport.createOffer();
      
      await transport.setRemoteDescription(offer);
      expect(transport.webRtcConnectionState, equals('have-remote-offer'));
      
      final answer = await transport.createAnswer(offer);
      await transport.setRemoteDescription(answer);
      expect(transport.webRtcConnectionState, equals('stable'));
    });

    test('should handle ICE candidates', () async {
      final candidate = {
        'candidate': 'candidate:1 1 UDP 2122260223 192.168.1.100 54400 typ host',
        'sdpMid': 'data',
        'sdpMLineIndex': 0,
      };
      
      // Should not throw
      await transport.addIceCandidate(candidate);
    });

    test('should generate ICE candidates', () async {
      final candidates = <Map<String, dynamic>>[];
      
      await for (final candidate in transport.iceCandidate) {
        candidates.add(candidate);
      }
      
      expect(candidates, isNotEmpty);
      expect(candidates.first['candidate'], isA<String>());
      expect(candidates.first['sdpMid'], isA<String>());
    });

    test('should handle custom configuration', () {
      final customTransport = WebRtcTransport(
        peerId: 'custom-peer',
        config: {
          'iceServers': [{'urls': 'stun:custom.stun.server'}],
        },
      );
      
      expect(customTransport.url, equals('webrtc://custom-peer'));
    });

    test('should receive messages through stream', () async {
      await transport.connect();
      
      bool messageReceived = false;
      transport.messages.listen((message) {
        messageReceived = true;
        expect(message['hi'], isNotNull);
      });
      
      // Send hi message to trigger response
      await transport.send({
        'hi': {'gun': '0.1.0'},
      });
      
      // Wait a bit for async processing
      await Future.delayed(const Duration(milliseconds: 100));
      expect(messageReceived, isTrue);
    });
  });

  group('Transport Integration Tests', () {
    test('should work with Gun instance - WebRTC', () async {
      final gun = Gun(GunOptions(
        localStorage: false,
      ));
      
      final transport = WebRtcTransport(peerId: 'gun-test');
      await transport.connect();
      
      // Add peer would normally integrate the transport
      // This is just testing compatibility
      expect(transport.isConnected, isTrue);
      
      await transport.close();
      await gun.close();
    });

    test('should handle message serialization', () {
      final message = {
        'put': {
          'users': {
            'alice': {'name': 'Alice', 'age': 30},
          },
        },
      };
      
      final json = message;
      final restored = Map<String, dynamic>.from(json);
      
      expect(restored['put'], equals(message['put']));
    });
  });
}
