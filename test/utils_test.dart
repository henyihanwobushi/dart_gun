import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:gun_dart/src/utils/encoder.dart';
import 'package:gun_dart/src/utils/validator.dart';

void main() {
  group('Encoder Tests', () {
    test('should encode/decode JSON', () {
      final data = {'name': 'Alice', 'age': 30};
      final encoded = Encoder.toJson(data);
      final decoded = Encoder.fromJson(encoded);
      
      expect(decoded, equals(data));
    });

    test('should encode/decode Base64 strings', () {
      const original = 'Hello, World!';
      final encoded = Encoder.toBase64(original);
      final decoded = Encoder.fromBase64(encoded);
      
      expect(decoded, equals(original));
      expect(encoded, isA<String>());
    });

    test('should encode/decode Base64 bytes', () {
      final original = Uint8List.fromList([1, 2, 3, 4, 5]);
      final encoded = Encoder.bytesToBase64(original);
      final decoded = Encoder.base64ToBytes(encoded);
      
      expect(decoded, equals(original));
    });

    test('should encode/decode URLs', () {
      const original = 'hello world & special chars!';
      final encoded = Encoder.urlEncode(original);
      final decoded = Encoder.urlDecode(encoded);
      
      expect(decoded, equals(original));
      expect(encoded, contains('%'));
    });

    test('should encode/decode hex strings', () {
      final original = Uint8List.fromList([255, 128, 64, 32, 16]);
      final encoded = Encoder.toHex(original);
      final decoded = Encoder.fromHex(encoded);
      
      expect(decoded, equals(original));
      expect(encoded, equals('ff804020100'));
    });

    test('should encode/decode query strings', () {
      final params = {'name': 'Alice Smith', 'age': '30', 'city': 'New York'};
      final encoded = Encoder.toQueryString(params);
      final decoded = Encoder.fromQueryString(encoded);
      
      expect(decoded['name'], equals('Alice Smith'));
      expect(decoded['age'], equals('30'));
      expect(encoded, contains('&'));
    });

    test('should encode/decode Gun wire messages', () {
      final message = {'put': {'users/alice': {'name': 'Alice'}}};
      final encoded = Encoder.encodeWireMessage(message);
      final decoded = Encoder.decodeWireMessage(encoded);
      
      expect(decoded['put'], isNotNull);
      expect(decoded['_'], isNotNull); // Timestamp added
    });

    test('should encode Gun nodes', () {
      final data = {'name': 'Alice', 'age': 30};
      final encoded = Encoder.encodeGunNode('users/alice', data);
      
      expect(encoded['users/alice'], isNotNull);
      expect(encoded['users/alice']['_'], isNotNull);
      expect(encoded['users/alice']['_']['#'], equals('users/alice'));
      expect(encoded['users/alice']['_']['>'], isA<Map>());
    });

    test('should escape/unescape strings', () {
      const original = 'Hello "World"\nNew line\tTab';
      final escaped = Encoder.escape(original);
      final unescaped = Encoder.unescape(escaped);
      
      expect(unescaped, equals(original));
      expect(escaped, contains('\\n'));
      expect(escaped, contains('\\"'));
    });

    test('should encode/decode storage data', () {
      final data = {'nested': {'data': 'test', 'number': 42}};
      final encoded = Encoder.encodeForStorage(data);
      final decoded = Encoder.decodeFromStorage(encoded);
      
      expect(decoded, equals(data));
    });
  });

  group('Validator Tests', () {
    test('should validate non-empty values', () {
      expect(Validator.isNotEmpty('hello'), isTrue);
      expect(Validator.isNotEmpty([1, 2, 3]), isTrue);
      expect(Validator.isNotEmpty({'a': 1}), isTrue);
      expect(Validator.isNotEmpty(42), isTrue);
      
      expect(Validator.isNotEmpty(''), isFalse);
      expect(Validator.isNotEmpty([]), isFalse);
      expect(Validator.isNotEmpty({}), isFalse);
      expect(Validator.isNotEmpty(null), isFalse);
    });

    test('should validate email addresses', () {
      expect(Validator.isValidEmail('test@example.com'), isTrue);
      expect(Validator.isValidEmail('user.name+tag@domain.co.uk'), isTrue);
      
      expect(Validator.isValidEmail('invalid-email'), isFalse);
      expect(Validator.isValidEmail('@domain.com'), isFalse);
      expect(Validator.isValidEmail('test@'), isFalse);
    });

    test('should validate URLs', () {
      expect(Validator.isValidUrl('https://www.example.com'), isTrue);
      expect(Validator.isValidUrl('http://localhost:3000'), isTrue);
      expect(Validator.isValidUrl('ftp://files.example.com'), isTrue);
      
      expect(Validator.isValidUrl('not-a-url'), isFalse);
      expect(Validator.isValidUrl('http://'), isFalse);
      expect(Validator.isValidUrl('://missing-scheme'), isFalse);
    });

    test('should validate patterns', () {
      expect(Validator.matchesPattern('test123', r'test\d+'), isTrue);
      expect(Validator.matchesPattern('hello@world.com', r'.+@.+\..+'), isTrue);
      
      expect(Validator.matchesPattern('test', r'\d+'), isFalse);
      expect(Validator.matchesPattern('invalid', r'^valid'), isFalse);
    });

    test('should validate types', () {
      expect(Validator.isType<String>('hello'), isTrue);
      expect(Validator.isType<int>(42), isTrue);
      expect(Validator.isType<List>([1, 2, 3]), isTrue);
      
      expect(Validator.isType<String>(42), isFalse);
      expect(Validator.isType<int>('hello'), isFalse);
    });

    test('should validate number ranges', () {
      expect(Validator.isInRange(5, 0, 10), isTrue);
      expect(Validator.isInRange(0, 0, 10), isTrue);
      expect(Validator.isInRange(10, 0, 10), isTrue);
      
      expect(Validator.isInRange(-1, 0, 10), isFalse);
      expect(Validator.isInRange(11, 0, 10), isFalse);
    });

    test('should validate string lengths', () {
      expect(Validator.isValidLength('hello', min: 3, max: 10), isTrue);
      expect(Validator.isValidLength('hi', min: 1), isTrue);
      expect(Validator.isValidLength('test', max: 5), isTrue);
      
      expect(Validator.isValidLength('hi', min: 5), isFalse);
      expect(Validator.isValidLength('toolong', max: 3), isFalse);
    });

    test('should validate strong passwords', () {
      expect(Validator.isStrongPassword('StrongPass123!'), isTrue);
      expect(Validator.isStrongPassword('MySecure#Pass1'), isTrue);
      
      expect(Validator.isStrongPassword('weak'), isFalse); // Too short
      expect(Validator.isStrongPassword('nouppercase123!'), isFalse);
      expect(Validator.isStrongPassword('NOLOWERCASE123!'), isFalse);
      expect(Validator.isStrongPassword('NoNumbers!'), isFalse);
      expect(Validator.isStrongPassword('NoSpecialChars123'), isFalse);
    });

    test('should validate Gun nodes', () {
      final validNode = {
        'name': 'Alice',
        '_': {
          '#': 'users/alice',
          '>': {'name': 1234567890}
        }
      };
      
      final invalidNode1 = {'name': 'Alice'}; // No metadata
      final invalidNode2 = {
        'name': 'Alice',
        '_': {'#': 'users/alice'} // No timestamps
      };
      
      expect(Validator.isValidGunNode(validNode), isTrue);
      expect(Validator.isValidGunNode(invalidNode1), isFalse);
      expect(Validator.isValidGunNode(invalidNode2), isFalse);
    });

    test('should validate Gun keys', () {
      expect(Validator.isValidGunKey('users'), isTrue);
      expect(Validator.isValidGunKey('user123'), isTrue);
      expect(Validator.isValidGunKey('user-name'), isTrue);
      
      expect(Validator.isValidGunKey(''), isFalse); // Empty
      expect(Validator.isValidGunKey('_private'), isFalse); // Starts with _
      expect(Validator.isValidGunKey('user/path'), isFalse); // Contains /
      expect(Validator.isValidGunKey('user key'), isFalse); // Contains space
    });

    test('should validate JSON', () {
      expect(Validator.isValidJson('{"name": "Alice"}'), isTrue);
      expect(Validator.isValidJson('[1, 2, 3]'), isTrue);
      expect(Validator.isValidJson('"string"'), isTrue);
      
      expect(Validator.isValidJson('{name: "Alice"}'), isFalse); // Invalid JSON
      expect(Validator.isValidJson('{"name": }'), isFalse); // Incomplete
    });

    test('should sanitize input', () {
      const dangerous = '<script>alert("xss")</script>Hello';
      final sanitized = Validator.sanitizeInput(dangerous);
      expect(sanitized, equals('alert("xss")Hello'));
      
      const withSpecialChars = 'Hello<>"World';
      final sanitizedSpecial = Validator.sanitizeInput(withSpecialChars, allowSpecialChars: false);
      expect(sanitizedSpecial, equals('HelloWorld'));
    });

    test('should validate and sanitize Gun data', () {
      final validData = {'name': 'Alice', 'age': 30};
      final result1 = Validator.validateAndSanitizeGunData(validData);
      expect(result1, equals(validData));
      
      final invalidData = {'_invalid': 'data', 'name': '<script>bad</script>'};
      final result2 = Validator.validateAndSanitizeGunData(invalidData);
      expect(result2?['_invalid'], isNull);
      expect(result2?['name'], equals('bad'));
      
      // Non-map data should be wrapped
      final result3 = Validator.validateAndSanitizeGunData('simple string');
      expect(result3?['_value'], equals('simple string'));
    });

    test('should validate schemas', () {
      final schema = {
        'required': ['name', 'email'],
        'properties': {
          'name': {'type': 'string'},
          'age': {'type': 'number'},
          'email': {'type': 'string'},
          'active': {'type': 'boolean'}
        }
      };
      
      final validData = {
        'name': 'Alice',
        'age': 30,
        'email': 'alice@example.com',
        'active': true
      };
      
      final invalidData = {
        'name': 'Alice',
        'age': 'thirty', // Should be number
        // Missing required email
        'active': 'yes' // Should be boolean
      };
      
      final result1 = Validator.validateSchema(validData, schema);
      expect(result1.isValid, isTrue);
      expect(result1.errors, isEmpty);
      
      final result2 = Validator.validateSchema(invalidData, schema);
      expect(result2.isValid, isFalse);
      expect(result2.errors, hasLength(3)); // Missing email, wrong age type, wrong active type
    });

    test('should validate size limits', () {
      final smallData = {'name': 'Alice'};
      final largeData = {'data': 'x' * 10000}; // Large string
      
      expect(Validator.isWithinSizeLimit(smallData, 1000), isTrue);
      expect(Validator.isWithinSizeLimit(largeData, 100), isFalse);
      expect(Validator.isWithinSizeLimit(largeData, 20000), isTrue);
    });

    test('should validate network messages', () {
      final validMessage1 = {'get': {'#': 'users/alice'}};
      final validMessage2 = {'put': {'users/alice': {'name': 'Alice'}}};
      final validMessage3 = {'hi': {'gun': '0.2.0'}};
      
      final invalidMessage = {'invalid': 'message'};
      
      expect(Validator.isValidNetworkMessage(validMessage1), isTrue);
      expect(Validator.isValidNetworkMessage(validMessage2), isTrue);
      expect(Validator.isValidNetworkMessage(validMessage3), isTrue);
      expect(Validator.isValidNetworkMessage(invalidMessage), isFalse);
    });
  });

  group('ValidationResult Tests', () {
    test('should create valid result', () {
      final result = ValidationResult(true, []);
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
      expect(result.toString(), equals('Valid'));
    });

    test('should create invalid result with errors', () {
      final result = ValidationResult(false, ['Error 1', 'Error 2']);
      expect(result.isValid, isFalse);
      expect(result.errors, hasLength(2));
      expect(result.toString(), contains('Invalid'));
      expect(result.toString(), contains('Error 1'));
    });
  });
}
