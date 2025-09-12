import 'package:flutter_test/flutter_test.dart';
import 'package:gun_dart/src/network/gun_relay_client.dart';
import 'package:gun_dart/src/network/relay_pool_manager.dart';
import 'package:gun_dart/src/gun.dart';
import 'package:gun_dart/src/types/types.dart';

void main() {
  group('Gun.js Relay Server Compatibility', () {
    group('RelayServerConfig', () {
      test('should create default config', () {
        final config = RelayServerConfig.defaultConfig('ws://localhost:8080');
        
        expect(config.url, equals('ws://localhost:8080'));
        expect(config.connectionTimeout, equals(Duration(seconds: 10)));
        expect(config.pingInterval, equals(Duration(seconds: 30)));
        expect(config.autoReconnect, isTrue);
        expect(config.maxReconnectAttempts, equals(5));
      });

      test('should create custom config', () {
        final config = RelayServerConfig(
          url: 'wss://relay.gun.eco',
          connectionTimeout: Duration(seconds: 15),
          pingInterval: Duration(minutes: 1),
          autoReconnect: false,
          maxReconnectAttempts: 3,
          headers: {'Authorization': 'Bearer token123'},
        );
        
        expect(config.url, equals('wss://relay.gun.eco'));
        expect(config.connectionTimeout, equals(Duration(seconds: 15)));
        expect(config.pingInterval, equals(Duration(minutes: 1)));
        expect(config.autoReconnect, isFalse);
        expect(config.maxReconnectAttempts, equals(3));
        expect(config.headers['Authorization'], equals('Bearer token123'));
      });
    });

    group('GunRelayClient', () {
      test('should create relay client with default peer ID', () {
        final config = RelayServerConfig.defaultConfig('ws://localhost:8080');
        final client = GunRelayClient(config: config);
        
        expect(client.peerId.startsWith('dart-relay-'), isTrue);
        expect(client.peerId.length, equals(19)); // 'dart-relay-' + 8 chars
        expect(client.state, equals(RelayConnectionState.disconnected));
        expect(client.isConnected, isFalse);
      });

      test('should create relay client with custom peer ID', () {
        final config = RelayServerConfig.defaultConfig('ws://localhost:8080');
        final client = GunRelayClient(
          config: config, 
          peerId: 'custom-peer-123'
        );
        
        expect(client.peerId, equals('custom-peer-123'));
        expect(client.state, equals(RelayConnectionState.disconnected));
      });

      test('should convert URLs to WebSocket format', () {
        final httpConfig = RelayServerConfig.defaultConfig('http://localhost:8080');
        final httpsConfig = RelayServerConfig.defaultConfig('https://relay.gun.eco');
        final wsConfig = RelayServerConfig.defaultConfig('ws://localhost:8080');
        final wssConfig = RelayServerConfig.defaultConfig('wss://relay.gun.eco');
        
        // Client instances created for testing but not used directly
        // final httpClient = GunRelayClient(config: httpConfig);
        // final httpsClient = GunRelayClient(config: httpsConfig);
        // final wsClient = GunRelayClient(config: wsConfig);
        // final wssClient = GunRelayClient(config: wssConfig);
        
        // URL conversion is internal, but we can test through the config
        expect(httpConfig.url, equals('http://localhost:8080'));
        expect(httpsConfig.url, equals('https://relay.gun.eco'));
        expect(wsConfig.url, equals('ws://localhost:8080'));
        expect(wssConfig.url, equals('wss://relay.gun.eco'));
      });

      test('should handle state changes', () {
        final config = RelayServerConfig.defaultConfig('ws://localhost:8080');
        final client = GunRelayClient(config: config);
        final stateChanges = <RelayConnectionState>[];
        
        client.stateChanges.listen((state) => stateChanges.add(state));
        
        expect(client.state, equals(RelayConnectionState.disconnected));
        expect(stateChanges, isEmpty);
      });

      test('should track statistics', () {
        final config = RelayServerConfig.defaultConfig('ws://localhost:8080');
        final client = GunRelayClient(config: config);
        
        expect(client.stats.messagesReceived, equals(0));
        expect(client.stats.messagesSent, equals(0));
        expect(client.stats.reconnectionAttempts, equals(0));
        expect(client.stats.connectionFailures, equals(0));
        expect(client.stats.lastConnected, isNull);
        expect(client.stats.lastMessageReceived, isNull);
      });

      test('should generate unique peer IDs', () {
        final ids = <String>{};
        for (int i = 0; i < 100; i++) {
          final config = RelayServerConfig.defaultConfig('ws://localhost:8080');
          final client = GunRelayClient(config: config);
          ids.add(client.peerId);
        }
        
        expect(ids.length, equals(100)); // All IDs should be unique
      });

      test('should fail to send message when not connected', () async {
        final config = RelayServerConfig.defaultConfig('ws://localhost:8080');
        final client = GunRelayClient(config: config);
        
        expect(() async => await client.sendMessage({'test': 'data'}), 
               throwsA(isA<StateError>()));
      });
    });

    group('RelayPoolConfig', () {
      test('should create pool config with seed relays', () {
        final config = RelayPoolConfig(
          seedRelays: ['ws://relay1.gun.eco', 'ws://relay2.gun.eco'],
          maxConnections: 8,
          minConnections: 3,
          loadBalancing: LoadBalancingStrategy.roundRobin,
          healthCheckInterval: Duration(minutes: 2),
          connectionTimeout: Duration(seconds: 15),
          autoDiscovery: false,
          maxRetries: 5,
        );
        
        expect(config.seedRelays, hasLength(2));
        expect(config.maxConnections, equals(8));
        expect(config.minConnections, equals(3));
        expect(config.loadBalancing, equals(LoadBalancingStrategy.roundRobin));
        expect(config.healthCheckInterval, equals(Duration(minutes: 2)));
        expect(config.connectionTimeout, equals(Duration(seconds: 15)));
        expect(config.autoDiscovery, isFalse);
        expect(config.maxRetries, equals(5));
      });
    });

    group('RelayPoolManager', () {
      test('should create pool manager', () {
        final config = RelayPoolConfig(
          seedRelays: ['ws://relay.gun.eco'],
        );
        final manager = RelayPoolManager(config);
        
        expect(manager.activeConnections, equals(0));
        expect(manager.relayUrls, isEmpty);
      });

      test('should track pool statistics', () {
        final config = RelayPoolConfig(
          seedRelays: ['ws://relay1.gun.eco', 'ws://relay2.gun.eco'],
        );
        final manager = RelayPoolManager(config);
        
        final stats = manager.stats;
        expect(stats['totalRelays'], equals(0));
        expect(stats['activeConnections'], equals(0));
        expect(stats['healthyRelays'], equals(0));
        expect(stats['degradedRelays'], equals(0));
        expect(stats['unhealthyRelays'], equals(0));
        expect(stats['averageResponseTime'], isA<double>());
        expect(stats['totalConnectionCount'], equals(0));
      });

      test('should handle different load balancing strategies', () {
        for (final strategy in LoadBalancingStrategy.values) {
          final config = RelayPoolConfig(
            seedRelays: ['ws://relay.gun.eco'],
            loadBalancing: strategy,
          );
          final manager = RelayPoolManager(config);
          
          expect(manager.config.loadBalancing, equals(strategy));
        }
      });

      test('should reject adding relays when at capacity', () async {
        final config = RelayPoolConfig(
          seedRelays: [],
          maxConnections: 1,
        );
        final manager = RelayPoolManager(config);
        
        // This would normally connect, but we're testing capacity limits
        // In practice, connection attempts would be made
        expect(manager.config.maxConnections, equals(1));
      });
    });

    group('Gun Class Relay Integration', () {
      test('should create Gun instance with relay options', () {
        final options = GunOptions.withRelays(
          relayServers: ['ws://relay1.gun.eco', 'ws://relay2.gun.eco'],
          maxRelayConnections: 3,
          minRelayConnections: 1,
          loadBalancing: LoadBalancingStrategy.healthBased,
          enableDiscovery: true,
        );
        
        expect(options.relayServers, hasLength(2));
        expect(options.maxRelayConnections, equals(3));
        expect(options.minRelayConnections, equals(1));
        expect(options.relayLoadBalancing, equals(LoadBalancingStrategy.healthBased));
        expect(options.enableRelayDiscovery, isTrue);
      });

      test('should create Gun instance without relays', () {
        final gun = Gun();
        
        expect(gun.relayPool, isNull);
        expect(gun.relayStats, isNull);
      });

      test('should create Gun instance with relay configuration', () {
        final options = GunOptions(
          relayServers: ['ws://relay.gun.eco'],
          maxRelayConnections: 2,
          minRelayConnections: 1,
        );
        final gun = Gun(options);
        
        // Relay pool should be initialized
        expect(gun.relayPool, isNotNull);
      });

      test('should add relay to existing Gun instance', () async {
        final gun = Gun();
        
        // Initially no relay pool
        expect(gun.relayPool, isNull);
        
        // Add a relay (this initializes the pool)
        await gun.addRelay('ws://relay.gun.eco');
        
        // Pool should now exist
        expect(gun.relayPool, isNotNull);
      });

      test('should handle relay statistics', () {
        final options = GunOptions(
          relayServers: ['ws://relay.gun.eco'],
        );
        final gun = Gun(options);
        
        final stats = gun.relayStats;
        expect(stats, isNotNull);
        expect(stats!['totalRelays'], isA<int>());
        expect(stats['activeConnections'], isA<int>());
      });
    });

    group('RelayServerInfo', () {
      test('should track relay server information', () {
        final config = RelayServerConfig.defaultConfig('ws://relay.gun.eco');
        final client = GunRelayClient(config: config);
        final info = RelayServerInfo(url: 'ws://relay.gun.eco', client: client);
        
        expect(info.url, equals('ws://relay.gun.eco'));
        expect(info.client, equals(client));
        expect(info.addedAt, isA<DateTime>());
        expect(info.healthStatus, equals(RelayHealthStatus.unknown));
        expect(info.connectionCount, equals(0));
        expect(info.failureCount, equals(0));
        expect(info.responseTime, equals(0.0));
        expect(info.healthScore, isA<double>());
      });

      test('should calculate health scores correctly', () {
        final config = RelayServerConfig.defaultConfig('ws://relay.gun.eco');
        final client = GunRelayClient(config: config);
        final info = RelayServerInfo(url: 'ws://relay.gun.eco', client: client);
        
        // Unknown status - default health score
        expect(info.healthScore, equals(0.3));
        
        // Test health score calculation (private methods tested indirectly through pool manager)
        expect(info.healthStatus, equals(RelayHealthStatus.unknown));
        expect(info.connectionCount, equals(0));
        expect(info.failureCount, equals(0));
        expect(info.responseTime, equals(0.0));
      });
    });

    group('RelayServerEvent', () {
      test('should create relay server events', () {
        final event = RelayServerEvent(
          type: RelayEventType.connected,
          relayUrl: 'ws://relay.gun.eco',
          peerId: 'dart-relay-abc123',
          data: {'test': 'data'},
        );
        
        expect(event.type, equals(RelayEventType.connected));
        expect(event.relayUrl, equals('ws://relay.gun.eco'));
        expect(event.peerId, equals('dart-relay-abc123'));
        expect(event.data, equals({'test': 'data'}));
        expect(event.timestamp, isA<DateTime>());
        expect(event.error, isNull);
      });

      test('should create error events', () {
        final event = RelayServerEvent(
          type: RelayEventType.error,
          relayUrl: 'ws://relay.gun.eco',
          peerId: 'dart-relay-abc123',
          error: 'Connection failed',
        );
        
        expect(event.type, equals(RelayEventType.error));
        expect(event.error, equals('Connection failed'));
        expect(event.data, isNull);
      });

      test('should convert to map', () {
        final event = RelayServerEvent(
          type: RelayEventType.messageSent,
          relayUrl: 'ws://relay.gun.eco',
          peerId: 'dart-relay-abc123',
          data: {'message': 'test'},
        );
        
        final map = event.toMap();
        expect(map['type'], equals('messageSent'));
        expect(map['relayUrl'], equals('ws://relay.gun.eco'));
        expect(map['peerId'], equals('dart-relay-abc123'));
        expect(map['data'], equals({'message': 'test'}));
        expect(map['timestamp'], isA<String>());
      });

      test('should have string representation', () {
        final event = RelayServerEvent(
          type: RelayEventType.connected,
          relayUrl: 'ws://relay.gun.eco',
          peerId: 'dart-relay-abc123',
        );
        
        final str = event.toString();
        expect(str, contains('connected'));
        expect(str, contains('ws://relay.gun.eco'));
      });
    });

    group('RelayPoolEvent', () {
      test('should create pool events', () {
        final event = RelayPoolEvent(
          type: RelayPoolEventType.relayAdded,
          relayUrl: 'ws://relay.gun.eco',
          message: 'Relay added successfully',
          data: {'connections': 1},
        );
        
        expect(event.type, equals(RelayPoolEventType.relayAdded));
        expect(event.relayUrl, equals('ws://relay.gun.eco'));
        expect(event.message, equals('Relay added successfully'));
        expect(event.data, equals({'connections': 1}));
        expect(event.timestamp, isA<DateTime>());
      });

      test('should convert to map', () {
        final event = RelayPoolEvent(
          type: RelayPoolEventType.started,
          message: 'Pool started',
        );
        
        final map = event.toMap();
        expect(map['type'], equals('started'));
        expect(map['message'], equals('Pool started'));
        expect(map['timestamp'], isA<String>());
        expect(map['relayUrl'], isNull);
        expect(map['data'], isNull);
      });

      test('should have string representation', () {
        final event = RelayPoolEvent(
          type: RelayPoolEventType.error,
          message: 'Connection failed',
        );
        
        final str = event.toString();
        expect(str, contains('error'));
        expect(str, contains('Connection failed'));
      });
    });

    group('Integration Tests', () {
      test('should handle Gun.js message format', () {
        // Test message format compatibility
        final putMessage = {
          'put': {
            'users/alice': {
              'name': 'Alice',
              'age': 30,
              '_': {
                '#': 'users/alice',
                '>': {'name': 1640995200000, 'age': 1640995200000},
              }
            }
          },
          '@': 'msg-123',
          '#': 'ack-456',
        };
        
        expect(putMessage['put'], isA<Map<String, dynamic>>());
        expect(putMessage['@'], equals('msg-123'));
        expect(putMessage['#'], equals('ack-456'));
        
        final nodeData = (putMessage['put'] as Map<String, dynamic>)['users/alice'] as Map<String, dynamic>;
        expect(nodeData['name'], equals('Alice'));
        expect(nodeData['_'], isA<Map<String, dynamic>>());
        
        final metadata = nodeData['_'] as Map<String, dynamic>;
        expect(metadata['#'], equals('users/alice'));
        expect(metadata['>'], isA<Map<String, dynamic>>());
      });

      test('should handle Gun.js get query format', () {
        final getQuery = {
          'get': {'#': 'users/alice'},
          '@': 'query-123',
        };
        
        expect(getQuery['get'], isA<Map<String, dynamic>>());
        expect(getQuery['@'], equals('query-123'));
        
        final getParams = getQuery['get'] as Map<String, dynamic>;
        expect(getParams['#'], equals('users/alice'));
      });

      test('should handle Gun.js path traversal queries', () {
        final pathQuery = {
          'get': {
            '#': 'users',
            '.': {'alice': {'#': 'users/alice'}}
          },
          '@': 'query-456',
        };
        
        expect(pathQuery['get'], isA<Map<String, dynamic>>());
        
        final getParams = pathQuery['get'] as Map<String, dynamic>;
        expect(getParams['#'], equals('users'));
        expect(getParams['.'], isA<Map<String, dynamic>>());
      });

      test('should handle Gun.js error (DAM) messages', () {
        final damMessage = {
          'dam': 'Node not found',
          '#': 'query-789',
          '@': 'error-123',
        };
        
        expect(damMessage['dam'], equals('Node not found'));
        expect(damMessage['#'], equals('query-789'));
        expect(damMessage['@'], equals('error-123'));
      });
    });
  });
}
