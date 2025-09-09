import 'package:flutter_test/flutter_test.dart';
import '../lib/src/network/protocol_version.dart';

/// Tests for Gun.js protocol version support and compatibility
void main() {
  group('Protocol Version Support', () {
    group('Version Parsing', () {
      test('should parse standard Gun.js versions', () {
        expect(ProtocolVersion.parseVersion('0.2020.1235'), equals('0.2020.1235'));
        expect(ProtocolVersion.parseVersion('0.2019.416'), equals('0.2019.416'));
        expect(ProtocolVersion.parseVersion('0.2018.1201'), equals('0.2018.1201'));
      });
      
      test('should parse version with v prefix', () {
        expect(ProtocolVersion.parseVersion('v0.2020.1235'), equals('0.2020.1235'));
        expect(ProtocolVersion.parseVersion('v1.0.0'), equals('1.0.0'));
      });
      
      test('should parse version from object', () {
        expect(ProtocolVersion.parseVersion({'gun': '0.2020.1235'}), equals('0.2020.1235'));
        expect(ProtocolVersion.parseVersion({'version': '0.2019.416'}), equals('0.2019.416'));
        expect(ProtocolVersion.parseVersion({'v': '0.2018.1201'}), equals('0.2018.1201'));
      });
      
      test('should handle invalid versions', () {
        expect(ProtocolVersion.parseVersion(null), isNull);
        expect(ProtocolVersion.parseVersion(123), isNull);
        expect(ProtocolVersion.parseVersion({}), isNull);
      });
    });
    
    group('Version Compatibility', () {
      test('should check version compatibility correctly', () {
        expect(ProtocolVersion.areCompatible('0.2020.1235', '0.2020.1235'), isTrue);
        expect(ProtocolVersion.areCompatible('0.2019.416', '0.2019.416'), isTrue);
        expect(ProtocolVersion.areCompatible('0.2018.1201', '0.2018.1201'), isTrue);
      });
      
      test('should handle incompatible versions', () {
        expect(ProtocolVersion.areCompatible('0.2020.1235', '0.9.x'), isFalse);
        expect(ProtocolVersion.areCompatible('unknown', '0.2020.1235'), isFalse);
      });
      
      test('should check capabilities compatibility', () {
        final caps2020 = ProtocolVersion.getCapabilities('0.2020.1235');
        final caps2019 = ProtocolVersion.getCapabilities('0.2019.416');
        final capsLegacy = ProtocolVersion.getCapabilities('0.9.x');
        
        expect(caps2020?.supportsDAMErrors, isTrue);
        expect(caps2019?.supportsDAMErrors, isFalse);
        expect(capsLegacy?.supportsSEA, isFalse);
      });
    });
    
    group('Version Negotiation', () {
      test('should negotiate best compatible version', () {
        final result = ProtocolVersion.negotiateVersion(
          localVersion: '0.2020.1235',
          remoteVersions: ['0.2020.1235', '0.2019.416', '0.2018.1201'],
        );
        
        expect(result.success, isTrue);
        expect(result.negotiatedVersion, equals('0.2020.1235'));
        expect(result.capabilities?.supportsDAMErrors, isTrue);
      });
      
      test('should handle no compatible version', () {
        final result = ProtocolVersion.negotiateVersion(
          localVersion: '0.2020.1235',
          remoteVersions: ['0.9.x', 'unknown'],
        );
        
        expect(result.success, isFalse);
        expect(result.error, contains('No compatible version found'));
      });
      
      test('should handle unknown local version', () {
        final result = ProtocolVersion.negotiateVersion(
          localVersion: 'unknown',
          remoteVersions: ['0.2020.1235'],
        );
        
        expect(result.success, isFalse);
        expect(result.error, contains('Unknown local version'));
      });
    });
    
    group('Message Formatting', () {
      test('should format messages for v2020', () {
        final caps = ProtocolVersion.getCapabilities('0.2020.1235')!;
        final message = {'get': {'#': 'test'}};
        
        final formatted = ProtocolVersion.formatMessage(message, caps);
        
        expect(formatted.containsKey('@'), isTrue);
        expect(formatted['get'], equals({'#': 'test'}));
      });
      
      test('should format handshake messages for v2020', () {
        final caps = ProtocolVersion.getCapabilities('0.2020.1235')!;
        final message = {
          'hi': {'version': '0.2020.1235'},
          '@': 'test123'
        };
        
        final formatted = ProtocolVersion.formatMessage(message, caps);
        final hi = formatted['hi'] as Map<String, dynamic>;
        
        expect(hi.containsKey('gun'), isTrue);
        expect(hi.containsKey('pid'), isTrue);
      });
      
      test('should format DAM messages for older versions', () {
        final caps2019 = ProtocolVersion.getCapabilities('0.2019.416')!;
        final message = {
          'dam': {'message': 'Error occurred', 'code': 'ERR001'},
          '@': 'test123'
        };
        
        final formatted = ProtocolVersion.formatMessage(message, caps2019);
        
        expect(formatted['dam'], isA<String>());
        expect(formatted['dam'], equals('Error occurred'));
      });
      
      test('should format legacy messages', () {
        final capsLegacy = ProtocolVersion.getCapabilities('0.9.x')!;
        final message = {
          'put': {'test': 'value'},
          '@': 'test123',
          'extra': 'field'
        };
        
        final formatted = ProtocolVersion.formatMessage(message, capsLegacy);
        
        expect(formatted.containsKey('put'), isTrue);
        expect(formatted.containsKey('@'), isFalse); // Removed in legacy
        expect(formatted.containsKey('extra'), isFalse); // Removed in legacy
      });
    });
    
    group('Message Parsing', () {
      test('should parse handshake messages', () {
        final message = {
          'hi': {
            'gun': '0.2020.1235',
            'pid': 'peer123'
          },
          '@': 'msg123'
        };
        final caps = ProtocolVersion.getCapabilities('0.2020.1235');
        
        final parsed = ProtocolVersion.parseMessage(message, caps);
        
        expect(parsed.type, equals(MessageType.handshake));
        expect(parsed.remoteVersion, equals('0.2020.1235'));
        expect(parsed.messageId, equals('msg123'));
        expect(parsed.handshakeData?['pid'], equals('peer123'));
      });
      
      test('should parse put messages', () {
        final message = {
          'put': {
            'test/node': {'value': 42}
          },
          '@': 'msg456'
        };
        final caps = ProtocolVersion.getCapabilities('0.2020.1235');
        
        final parsed = ProtocolVersion.parseMessage(message, caps);
        
        expect(parsed.type, equals(MessageType.put));
        expect(parsed.putData?['test/node']?['value'], equals(42));
      });
      
      test('should parse get messages', () {
        final message = {
          'get': {'#': 'test/node'},
          '@': 'msg789'
        };
        final caps = ProtocolVersion.getCapabilities('0.2020.1235');
        
        final parsed = ProtocolVersion.parseMessage(message, caps);
        
        expect(parsed.type, equals(MessageType.get));
        expect(parsed.getData?['#'], equals('test/node'));
      });
      
      test('should parse DAM messages', () {
        final message = {
          'dam': 'Node not found',
          '@': 'error123',
          '#': 'original456'
        };
        final caps = ProtocolVersion.getCapabilities('0.2020.1235');
        
        final parsed = ProtocolVersion.parseMessage(message, caps);
        
        expect(parsed.type, equals(MessageType.dam));
        expect(parsed.errorData, equals('Node not found'));
        expect(parsed.ackId, equals('original456'));
      });
      
      test('should parse bye messages', () {
        final message = {'bye': 'peer123'};
        final caps = ProtocolVersion.getCapabilities('0.2020.1235');
        
        final parsed = ProtocolVersion.parseMessage(message, caps);
        
        expect(parsed.type, equals(MessageType.bye));
      });
      
      test('should handle unknown messages', () {
        final message = {'unknown': 'field'};
        final caps = ProtocolVersion.getCapabilities('0.2020.1235');
        
        final parsed = ProtocolVersion.parseMessage(message, caps);
        
        expect(parsed.type, equals(MessageType.unknown));
      });
    });
    
    group('Handshake Creation', () {
      test('should create handshake with default version', () {
        final handshake = ProtocolVersion.createHandshakeMessage();
        final hi = handshake['hi'] as Map<String, dynamic>;
        
        expect(handshake.containsKey('@'), isTrue);
        expect(hi['gun'], equals('0.2020.1235'));
        expect(hi['dart'], equals('0.2.1'));
        expect(hi.containsKey('pid'), isTrue);
        expect(hi['versions'], contains('0.2020.1235'));
      });
      
      test('should create handshake with custom peer ID', () {
        final handshake = ProtocolVersion.createHandshakeMessage(peerId: 'custom123');
        final hi = handshake['hi'] as Map<String, dynamic>;
        
        expect(hi['pid'], equals('custom123'));
      });
      
      test('should create handshake with supported versions', () {
        final handshake = ProtocolVersion.createHandshakeMessage(
          supportedVersions: ['0.2020.1235', '0.2019.416']
        );
        final hi = handshake['hi'] as Map<String, dynamic>;
        
        expect(hi['versions'], containsAll(['0.2020.1235', '0.2019.416']));
      });
    });
    
    group('Capability Detection', () {
      test('should detect capabilities for known versions', () {
        final caps2020 = ProtocolVersion.getCapabilities('0.2020.1235');
        expect(caps2020?.supportsHAM, isTrue);
        expect(caps2020?.supportsWireProtocol, isTrue);
        expect(caps2020?.supportsSEA, isTrue);
        expect(caps2020?.supportsDAMErrors, isTrue);
        
        final caps2018 = ProtocolVersion.getCapabilities('0.2018.1201');
        expect(caps2018?.supportsHAM, isTrue);
        expect(caps2018?.supportsDAMErrors, isFalse);
        expect(caps2018?.supportsPeerHandshake, isFalse);
        
        final capsLegacy = ProtocolVersion.getCapabilities('0.9.x');
        expect(capsLegacy?.supportsHAM, isTrue);
        expect(capsLegacy?.supportsWireProtocol, isFalse);
        expect(capsLegacy?.supportsSEA, isFalse);
      });
      
      test('should handle unknown versions', () {
        final caps = ProtocolVersion.getCapabilities('unknown.version');
        expect(caps, isNull);
      });
      
      test('should match version patterns', () {
        final caps = ProtocolVersion.getCapabilities('0.9.5'); // Should match 0.9.x
        expect(caps, isNotNull);
        expect(caps?.messageFormat, equals(MessageFormat.legacy));
      });
    });
    
    group('Version Matrix', () {
      test('should check compatibility matrix', () {
        expect(VersionMatrix.isCompatible('0.2020.1235', '0.2019.416'), isTrue);
        expect(VersionMatrix.isCompatible('0.2019.416', '0.2018.1201'), isTrue);
        expect(VersionMatrix.isCompatible('0.2018.1201', '0.2018.1201'), isTrue);
      });
      
      test('should get compatible versions', () {
        final compatible2020 = VersionMatrix.getCompatibleVersions('0.2020.1235');
        expect(compatible2020, containsAll(['0.2020.1235', '0.2019.416', '0.2018.1201']));
        
        final compatibleLegacy = VersionMatrix.getCompatibleVersions('0.9.x');
        expect(compatibleLegacy, equals(['0.9.x']));
      });
      
      test('should handle unknown versions in matrix', () {
        final compatible = VersionMatrix.getCompatibleVersions('unknown');
        expect(compatible, isEmpty);
      });
    });
  });
}
