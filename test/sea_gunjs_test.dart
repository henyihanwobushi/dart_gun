import 'package:flutter_test/flutter_test.dart';
import '../lib/src/auth/sea_gunjs.dart';
import 'dart:convert';

void main() {
  group('SEAGunJS Tests', () {
    group('Key Pair Generation', () {
      test('should generate valid secp256k1 key pairs', () async {
        final keyPair = await SEAGunJS.pair();
        
        expect(keyPair.pub, isNotEmpty);
        expect(keyPair.priv, isNotEmpty);
        expect(keyPair.epub, isNotEmpty);
        expect(keyPair.epriv, isNotEmpty);
        
        // Gun.js uses base64url encoding
        expect(() => base64Url.decode(keyPair.pub), returnsNormally);
        expect(() => base64Url.decode(keyPair.priv), returnsNormally);
        expect(() => base64Url.decode(keyPair.epub), returnsNormally);
        expect(() => base64Url.decode(keyPair.epriv), returnsNormally);
      });
      
      test('should generate compressed public keys (33 bytes)', () async {
        final keyPair = await SEAGunJS.pair();
        final pubBytes = base64Url.decode(keyPair.pub);
        
        // Compressed secp256k1 public keys are 33 bytes
        expect(pubBytes.length, equals(33));
        
        // First byte should be 0x02 or 0x03 (compression flag)
        expect([0x02, 0x03], contains(pubBytes[0]));
      });
      
      test('should generate 32-byte private keys', () async {
        final keyPair = await SEAGunJS.pair();
        final privBytes = base64Url.decode(keyPair.priv);
        
        // secp256k1 private keys are 32 bytes
        expect(privBytes.length, equals(32));
      });
      
      test('should generate different key pairs each time', () async {
        final keyPair1 = await SEAGunJS.pair();
        final keyPair2 = await SEAGunJS.pair();
        
        expect(keyPair1.pub, isNot(equals(keyPair2.pub)));
        expect(keyPair1.priv, isNot(equals(keyPair2.priv)));
      });
    });
    
    group('Digital Signatures', () {
      test('should sign and verify data correctly', () async {
        final keyPair = await SEAGunJS.pair();
        final data = 'test message';
        
        final signature = await SEAGunJS.sign(data, keyPair);
        final isValid = await SEAGunJS.verify(data, signature, keyPair.pub);
        
        expect(signature, isNotEmpty);
        expect(isValid, isTrue);
      });
      
      test('should fail verification with wrong public key', () async {
        final keyPair1 = await SEAGunJS.pair();
        final keyPair2 = await SEAGunJS.pair();
        final data = 'test message';
        
        final signature = await SEAGunJS.sign(data, keyPair1);
        final isValid = await SEAGunJS.verify(data, signature, keyPair2.pub);
        
        expect(isValid, isFalse);
      });
      
      test('should fail verification with modified data', () async {
        final keyPair = await SEAGunJS.pair();
        final data = 'test message';
        final modifiedData = 'modified message';
        
        final signature = await SEAGunJS.sign(data, keyPair);
        final isValid = await SEAGunJS.verify(modifiedData, signature, keyPair.pub);
        
        expect(isValid, isFalse);
      });
      
      test('should handle JSON data signing', () async {
        final keyPair = await SEAGunJS.pair();
        final data = {'name': 'Alice', 'age': 30};
        
        final signature = await SEAGunJS.sign(data, keyPair);
        final isValid = await SEAGunJS.verify(data, signature, keyPair.pub);
        
        expect(isValid, isTrue);
      });
      
      test('should generate 64-byte signatures (secp256k1)', () async {
        final keyPair = await SEAGunJS.pair();
        final data = 'test message';
        
        final signature = await SEAGunJS.sign(data, keyPair);
        final signatureBytes = base64Url.decode(signature);
        
        // secp256k1 signatures are 64 bytes (32 for r + 32 for s)
        expect(signatureBytes.length, equals(64));
      });
    });
    
    group('Encryption and Decryption', () {
      test('should encrypt and decrypt data correctly', () async {
        final password = 'test-password';
        final data = 'secret message';
        
        final encrypted = await SEAGunJS.encrypt(data, password);
        final decrypted = await SEAGunJS.decrypt(encrypted, password);
        
        expect(decrypted, equals(data));
      });
      
      test('should fail decryption with wrong password', () async {
        final password = 'test-password';
        final wrongPassword = 'wrong-password';
        final data = 'secret message';
        
        final encrypted = await SEAGunJS.encrypt(data, password);
        
        expect(() => SEAGunJS.decrypt(encrypted, wrongPassword), 
               throwsA(isA<SEAException>()));
      });
      
      test('should handle JSON data encryption', () async {
        final password = 'test-password';
        final data = {'name': 'Alice', 'secret': 'password123'};
        
        final encrypted = await SEAGunJS.encrypt(data, password);
        final decrypted = await SEAGunJS.decrypt(encrypted, password);
        
        expect(decrypted, equals(data));
      });
      
      test('should produce Gun.js compatible encrypted format', () async {
        final password = 'test-password';
        final data = 'secret message';
        
        final encrypted = await SEAGunJS.encrypt(data, password);
        final encryptedObj = jsonDecode(encrypted) as Map<String, dynamic>;
        
        // Check Gun.js encrypted object structure
        expect(encryptedObj, containsPair('ct', isA<String>()));  // ciphertext
        expect(encryptedObj, containsPair('iv', isA<String>()));  // initialization vector
        expect(encryptedObj, containsPair('s', isA<String>()));   // salt
        expect(encryptedObj, containsPair('v', '0.3.0'));         // version
        
        // Verify base64 encoding
        expect(() => base64.decode(encryptedObj['ct']), returnsNormally);
        expect(() => base64.decode(encryptedObj['iv']), returnsNormally);
        expect(() => base64.decode(encryptedObj['s']), returnsNormally);
      });
    });
    
    group('Work Proof-of-Work', () {
      test('should generate and verify work proofs', () async {
        final data = 'test data';
        final salt = 'test-salt';
        final iterations = 100; // Reduced for testing
        
        final workString = await SEAGunJS.work(data, salt, iterations);
        final isValid = await SEAGunJS.verifyWork(workString, iterations);
        
        expect(isValid, isTrue);
      });
      
      test('should fail verification with wrong iterations', () async {
        final data = 'test data';
        final salt = 'test-salt';
        final iterations = 100;
        
        final workString = await SEAGunJS.work(data, salt, iterations);
        final isValid = await SEAGunJS.verifyWork(workString, 200);
        
        expect(isValid, isFalse);
      });
      
      test('should produce Gun.js compatible work format', () async {
        final data = 'test data';
        
        final workString = await SEAGunJS.work(data);
        final work = jsonDecode(workString) as Map<String, dynamic>;
        
        // Check work object structure
        expect(work, containsPair('data', data));
        expect(work, containsPair('salt', isA<String>()));
        expect(work, containsPair('proof', isA<String>()));
        expect(work, containsPair('iterations', isA<int>()));
      });
      
      test('should generate different proofs with different salts', () async {
        final data = 'test data';
        final iterations = 100;
        
        final work1 = await SEAGunJS.work(data, 'salt1', iterations);
        final work2 = await SEAGunJS.work(data, 'salt2', iterations);
        
        expect(work1, isNot(equals(work2)));
      });
    });
    
    group('SEAKeyPair Serialization', () {
      test('should serialize to and from JSON correctly', () async {
        final keyPair = await SEAGunJS.pair();
        
        final json = keyPair.toJson();
        final restored = SEAKeyPair.fromJson(json);
        
        expect(restored, equals(keyPair));
      });
      
      test('should have correct JSON structure', () async {
        final keyPair = await SEAGunJS.pair();
        final json = keyPair.toJson();
        
        expect(json, containsPair('pub', keyPair.pub));
        expect(json, containsPair('priv', keyPair.priv));
        expect(json, containsPair('epub', keyPair.epub));
        expect(json, containsPair('epriv', keyPair.epriv));
      });
      
      test('should not expose private keys in toString', () async {
        final keyPair = await SEAGunJS.pair();
        final string = keyPair.toString();
        
        expect(string, contains('[hidden]'));
        expect(string, isNot(contains(keyPair.priv)));
        expect(string, isNot(contains(keyPair.epriv)));
      });
    });
    
    group('Error Handling', () {
      test('should handle invalid encrypted data', () async {
        final password = 'test-password';
        final invalidData = 'invalid-data';
        
        expect(() => SEAGunJS.decrypt(invalidData, password), 
               throwsA(isA<SEAException>()));
      });
      
      test('should handle invalid signatures gracefully', () async {
        final keyPair = await SEAGunJS.pair();
        final data = 'test data';
        final invalidSignature = 'invalid-signature';
        
        final isValid = await SEAGunJS.verify(data, invalidSignature, keyPair.pub);
        expect(isValid, isFalse);
      });
      
      test('should handle invalid work proofs gracefully', () async {
        final invalidWork = 'invalid-work';
        
        final isValid = await SEAGunJS.verifyWork(invalidWork);
        expect(isValid, isFalse);
      });
    });
    
    group('Gun.js Compatibility Features', () {
      test('should use base64url encoding (not standard base64)', () async {
        final keyPair = await SEAGunJS.pair();
        
        // base64url doesn't use + or / characters, uses - and _ instead
        expect(keyPair.pub, isNot(contains('+')));
        expect(keyPair.pub, isNot(contains('/')));
        expect(keyPair.priv, isNot(contains('+')));
        expect(keyPair.priv, isNot(contains('/')));
      });
      
      test('should use secp256k1 curve consistently', () {
        expect(SEAGunJS.curve, equals('secp256k1'));
      });
      
      test('should match Gun.js version format', () {
        expect(SEAGunJS.version, equals('0.3.0'));
      });
      
      test('should handle empty data correctly', () async {
        final keyPair = await SEAGunJS.pair();
        final password = 'test-password';
        
        // Test empty string
        final encrypted = await SEAGunJS.encrypt('', password);
        final decrypted = await SEAGunJS.decrypt(encrypted, password);
        expect(decrypted, equals(''));
        
        // Test empty object
        final emptyObj = <String, dynamic>{};
        final encryptedObj = await SEAGunJS.encrypt(emptyObj, password);
        final decryptedObj = await SEAGunJS.decrypt(encryptedObj, password);
        expect(decryptedObj, equals(emptyObj));
        
        // Test signing empty data
        final signature = await SEAGunJS.sign('', keyPair);
        final isValid = await SEAGunJS.verify('', signature, keyPair.pub);
        expect(isValid, isTrue);
      });
    });
  });
  
  group('SEAException Tests', () {
    test('should create SEAException with message', () {
      final exception = SEAException('test error');
      expect(exception.message, equals('test error'));
      expect(exception.toString(), equals('SEAException: test error'));
    });
  });
}
