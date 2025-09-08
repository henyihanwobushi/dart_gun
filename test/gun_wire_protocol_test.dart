import 'package:flutter_test/flutter_test.dart';
import 'package:gun_dart/src/network/gun_wire_protocol.dart';

void main() {
  group('Gun.js Wire Protocol Tests', () {
    test('should create get message in Gun.js format', () {
      final message = GunWireProtocol.createGetMessage('users/alice');
      
      expect(message['get'], isNotNull);
      expect(message['get']['#'], equals('users/alice'));
      expect(message['@'], isNotNull);
      expect(message['@'], isA<String>());
    });
    
    test('should create put message with HAM metadata', () {
      final data = {'name': 'Alice', 'age': 30};
      final message = GunWireProtocol.createPutMessage('users/alice', data);
      
      expect(message['put'], isNotNull);
      expect(message['put']['users/alice'], isNotNull);
      
      final nodeData = message['put']['users/alice'];
      expect(nodeData['name'], equals('Alice'));
      expect(nodeData['age'], equals(30));
      
      // Check HAM metadata
      expect(nodeData['_'], isNotNull);
      expect(nodeData['_']['#'], equals('users/alice'));
      expect(nodeData['_']['>'], isNotNull);
      expect(nodeData['_']['>']['name'], isA<num>());
      expect(nodeData['_']['>']['age'], isA<num>());
      
      expect(message['@'], isNotNull);
      expect(message['@'], isA<String>());
    });
    
    test('should create hi handshake message', () {
      final message = GunWireProtocol.createHiMessage();
      
      expect(message['hi'], isNotNull);
      expect(message['hi']['gun'], equals('dart-0.2.1'));
      expect(message['hi']['pid'], isNotNull);
      expect(message['hi']['pid'], startsWith('dart-peer-'));
      expect(message['@'], isNotNull);
    });
    
    test('should create bye disconnect message', () {
      final message = GunWireProtocol.createByeMessage(peerId: 'test-peer');
      
      expect(message['bye'], isNotNull);
      expect(message['bye']['#'], equals('test-peer'));
      expect(message['@'], isNotNull);
    });
    
    test('should create dam error message', () {
      final message = GunWireProtocol.createDamMessage(
        'Test error',
        replyToMessageId: 'original-123',
      );
      
      expect(message['dam'], equals('Test error'));
      expect(message['@'], isNotNull);
      expect(message['#'], equals('original-123'));
    });
    
    test('should create ack message', () {
      final message = GunWireProtocol.createAckMessage(
        'original-456',
        result: {'success': true},
      );
      
      expect(message['ok'], equals({'success': true}));
      expect(message['@'], isNotNull);
      expect(message['#'], equals('original-456'));
    });
    
    test('should parse get message correctly', () {
      final rawMessage = {
        'get': {'#': 'users/bob'},
        '@': 'msg-123',
      };
      
      final parsed = GunWireProtocol.parseMessage(rawMessage);
      
      expect(parsed.type, equals(GunMessageType.get));
      expect(parsed.get, isNotNull);
      expect(parsed.get!['#'], equals('users/bob'));
      expect(parsed.messageId, equals('msg-123'));
      expect(parsed.requiresAck, isTrue);
    });
    
    test('should parse put message correctly', () {
      final rawMessage = {
        'put': {
          'users/charlie': {
            'name': 'Charlie',
            '_': {
              '#': 'users/charlie',
              '>': {'name': 1640995200000}
            }
          }
        },
        '@': 'msg-456',
      };
      
      final parsed = GunWireProtocol.parseMessage(rawMessage);
      
      expect(parsed.type, equals(GunMessageType.put));
      expect(parsed.put, isNotNull);
      expect(parsed.put!['users/charlie']['name'], equals('Charlie'));
      expect(parsed.messageId, equals('msg-456'));
      expect(parsed.requiresAck, isTrue);
    });
    
    test('should parse hi message correctly', () {
      final rawMessage = {
        'hi': {
          'gun': 'js-0.2020.1235',
          'pid': 'js-peer-abc',
        },
        '@': 'handshake-789',
      };
      
      final parsed = GunWireProtocol.parseMessage(rawMessage);
      
      expect(parsed.type, equals(GunMessageType.hi));
      expect(parsed.hi, isNotNull);
      expect(parsed.hi!['gun'], equals('js-0.2020.1235'));
      expect(parsed.hi!['pid'], equals('js-peer-abc'));
      expect(parsed.messageId, equals('handshake-789'));
      expect(parsed.requiresAck, isTrue);
    });
    
    test('should parse bye message correctly', () {
      final rawMessage = {
        'bye': {'#': 'leaving-peer'},
        '@': 'bye-101',
      };
      
      final parsed = GunWireProtocol.parseMessage(rawMessage);
      
      expect(parsed.type, equals(GunMessageType.bye));
      expect(parsed.bye, isNotNull);
      expect(parsed.messageId, equals('bye-101'));
    });
    
    test('should parse dam error message correctly', () {
      final rawMessage = {
        'dam': 'Something went wrong',
        '@': 'error-202',
        '#': 'failed-msg-303',
      };
      
      final parsed = GunWireProtocol.parseMessage(rawMessage);
      
      expect(parsed.type, equals(GunMessageType.dam));
      expect(parsed.dam, equals('Something went wrong'));
      expect(parsed.messageId, equals('error-202'));
      expect(parsed.ackId, equals('failed-msg-303'));
      expect(parsed.isError, isTrue);
      expect(parsed.isAck, isTrue);
    });
    
    test('should parse ack message correctly', () {
      final rawMessage = {
        'ok': true,
        '@': 'ack-404',
        '#': 'success-msg-505',
      };
      
      final parsed = GunWireProtocol.parseMessage(rawMessage);
      
      expect(parsed.type, equals(GunMessageType.ok));
      expect(parsed.ok, isTrue);
      expect(parsed.messageId, equals('ack-404'));
      expect(parsed.ackId, equals('success-msg-505'));
      expect(parsed.isAck, isTrue);
      expect(parsed.requiresAck, isFalse);
    });
    
    test('should extract HAM state from node data', () {
      final nodeData = {
        'name': 'Dave',
        'email': 'dave@example.com',
        '_': {
          '#': 'users/dave',
          '>': {
            'name': 1640995200000,
            'email': 1640995201000,
          }
        }
      };
      
      final hamState = GunWireProtocol.extractHamState(nodeData);
      
      expect(hamState, isNotNull);
      expect(hamState!['name'], equals(1640995200000));
      expect(hamState['email'], equals(1640995201000));
    });
    
    test('should extract node ID from node data', () {
      final nodeData = {
        'data': 'test',
        '_': {
          '#': 'test/node/123',
          '>': {'data': 1000}
        }
      };
      
      final nodeId = GunWireProtocol.extractNodeId(nodeData);
      
      expect(nodeId, equals('test/node/123'));
    });
    
    test('should merge HAM states correctly', () {
      final state1 = {
        'field1': 1000,
        'field2': 2000,
      };
      
      final state2 = {
        'field1': 1500,  // Newer
        'field2': 1800,  // Older
        'field3': 3000,  // New field
      };
      
      final merged = GunWireProtocol.mergeHamStates(state1, state2);
      
      expect(merged['field1'], equals(1500));  // Newer wins
      expect(merged['field2'], equals(2000));  // Original wins
      expect(merged['field3'], equals(3000));  // New field added
    });
    
    test('should handle custom message IDs', () {
      final customId = 'custom-msg-id-123';
      final message = GunWireProtocol.createGetMessage('test', messageId: customId);
      
      expect(message['@'], equals(customId));
    });
    
    test('should handle custom HAM state in put messages', () {
      final data = {'field': 'value'};
      final customHamState = {'field': 5000};
      
      final message = GunWireProtocol.createPutMessage(
        'test/node',
        data,
        hamState: customHamState,
      );
      
      final nodeData = message['put']['test/node'];
      final hamState = nodeData['_']['>'];
      
      expect(hamState['field'], equals(5000));
    });
    
    test('should not overwrite existing HAM state', () {
      final data = {'field1': 'value1', 'field2': 'value2'};
      final existingHamState = {'field1': 5000};
      
      final message = GunWireProtocol.createPutMessage(
        'test/node',
        data,
        hamState: existingHamState,
      );
      
      final nodeData = message['put']['test/node'];
      final hamState = nodeData['_']['>'];
      
      expect(hamState['field1'], equals(5000));  // Existing preserved
      expect(hamState['field2'], isA<num>());    // New field added
    });
    
    test('should handle messages without metadata fields', () {
      final nodeDataWithoutMeta = {'name': 'Test'};
      
      final hamState = GunWireProtocol.extractHamState(nodeDataWithoutMeta);
      final nodeId = GunWireProtocol.extractNodeId(nodeDataWithoutMeta);
      
      expect(hamState, isNull);
      expect(nodeId, isNull);
    });
    
    test('should identify message types correctly', () {
      final getMsg = GunWireProtocol.parseMessage({'get': {'#': 'test'}});
      final putMsg = GunWireProtocol.parseMessage({'put': {}});
      final hiMsg = GunWireProtocol.parseMessage({'hi': {}});
      final byeMsg = GunWireProtocol.parseMessage({'bye': {}});
      final damMsg = GunWireProtocol.parseMessage({'dam': 'error'});
      final okMsg = GunWireProtocol.parseMessage({'ok': true});
      final unknownMsg = GunWireProtocol.parseMessage({'unknown': 'field'});
      
      expect(getMsg.type, equals(GunMessageType.get));
      expect(putMsg.type, equals(GunMessageType.put));
      expect(hiMsg.type, equals(GunMessageType.hi));
      expect(byeMsg.type, equals(GunMessageType.bye));
      expect(damMsg.type, equals(GunMessageType.dam));
      expect(okMsg.type, equals(GunMessageType.ok));
      expect(unknownMsg.type, equals(GunMessageType.unknown));
    });
    
    test('should generate unique message IDs', () {
      final ids = <String>{};
      
      for (int i = 0; i < 100; i++) {
        final message = GunWireProtocol.createGetMessage('test');
        final id = message['@'] as String;
        expect(ids.contains(id), isFalse, reason: 'Duplicate message ID: $id');
        ids.add(id);
      }
    });
  });
}
