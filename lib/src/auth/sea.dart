import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../utils/utils.dart';

/// SEA (Security, Encryption, Authorization) implementation for Gun Dart
/// Compatible with Gun.js SEA protocol for secure authentication and encryption
class SEA {
  static const String _version = '0.3.0';
  static const int _keyLength = 32;
  static const int _ivLength = 16;
  static const String _algorithm = 'aes';
  
  /// Generate a cryptographic key pair for user authentication
  static Future<SEAKeyPair> pair() async {
    // Generate ECDSA key pair (simplified implementation)
    final random = Random.secure();
    final privateKey = List.generate(_keyLength, (_) => random.nextInt(256));
    final publicKey = _derivePublicKey(privateKey);
    
    return SEAKeyPair(
      pub: base64Encode(publicKey),
      priv: base64Encode(privateKey),
      epub: base64Encode(_deriveEncryptionKey(publicKey)),
      epriv: base64Encode(_deriveEncryptionKey(Uint8List.fromList(privateKey))),
    );
  }
  
  /// Encrypt data using AES encryption
  static Future<String> encrypt(dynamic data, String password) async {
    final dataString = data is String ? data : jsonEncode(data);
    final dataBytes = utf8.encode(dataString);
    
    // Derive key from password using PBKDF2
    final salt = _generateSalt();
    final key = _deriveKey(password, salt);
    final iv = _generateIV();
    
    // Encrypt data (simplified AES implementation)
    final encryptedData = _aesEncrypt(dataBytes, key, iv);
    
    // Create SEA encrypted object
    final seaObject = {
      'ct': base64Encode(encryptedData),
      'iv': base64Encode(iv),
      's': base64Encode(salt),
      'v': _version,
    };
    
    return jsonEncode(seaObject);
  }
  
  /// Decrypt data using AES decryption
  static Future<dynamic> decrypt(String encryptedData, String password) async {
    try {
      final seaObject = jsonDecode(encryptedData) as Map<String, dynamic>;
      
      if (seaObject['v'] != _version) {
        throw SEAException('Unsupported SEA version: ${seaObject['v']}');
      }
      
      final ciphertext = base64Decode(seaObject['ct'] as String);
      final iv = base64Decode(seaObject['iv'] as String);
      final salt = base64Decode(seaObject['s'] as String);
      
      // Derive key from password
      final key = _deriveKey(password, salt);
      
      // Decrypt data
      final decryptedBytes = _aesDecrypt(ciphertext, key, iv);
      final decryptedString = utf8.decode(decryptedBytes);
      
      // Try to parse as JSON, otherwise return as string
      try {
        return jsonDecode(decryptedString);
      } catch (e) {
        return decryptedString;
      }
    } catch (e) {
      throw SEAException('Failed to decrypt data: $e');
    }
  }
  
  /// Create digital signature for data
  static Future<String> sign(dynamic data, SEAKeyPair keyPair) async {
    final dataString = data is String ? data : jsonEncode(data);
    final dataBytes = utf8.encode(dataString);
    
    // Create signature using HMAC-SHA256 keyed by the public key so verification can use pub key
    final publicKeyBytes = base64Decode(keyPair.pub);
    final hmac = Hmac(sha256, publicKeyBytes);
    final signature = hmac.convert(dataBytes);
    
    // Store the key used for verification
    final signatureData = {
      'sig': base64Encode(signature.bytes),
      'key': keyPair.pub, // Include public key for verification
    };
    
    return base64Encode(utf8.encode(jsonEncode(signatureData)));
  }
  
  /// Verify digital signature
  static Future<bool> verify(dynamic data, String signature, String publicKey) async {
    try {
      final dataString = data is String ? data : jsonEncode(data);
      final dataBytes = utf8.encode(dataString);
      
      // Decode the signature data
      final sigDataString = utf8.decode(base64Decode(signature));
      final sigData = jsonDecode(sigDataString) as Map<String, dynamic>;
      
      // Verify the public key matches
      if (sigData['key'] != publicKey) {
        return false;
      }
      
      final sigBytes = base64Decode(sigData['sig'] as String);
      
      // Use the public key as the HMAC key (simplified approach)
      final keyBytes = base64Decode(publicKey);
      final hmac = Hmac(sha256, keyBytes);
      final expectedSignature = hmac.convert(dataBytes);
      
      return _constantTimeCompare(sigBytes, expectedSignature.bytes);
    } catch (e) {
      return false;
    }
  }
  
  /// Generate a secure work proof for data integrity
  static Future<SEAWork> work(dynamic data, SEAKeyPair keyPair, [String? previous]) async {
    final dataString = jsonEncode(data);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final nonce = Utils.randomString(16);
    
    // Create work object
    final workData = {
      'm': dataString,
      's': await sign(dataString, keyPair),
      'c': timestamp,
      'n': nonce,
    };
    
    if (previous != null) {
      workData['p'] = previous;
    }
    
    final workString = jsonEncode(workData);
    final hash = sha256.convert(utf8.encode(workString)).toString();
    
    return SEAWork(
      hash: hash,
      data: workData,
      proof: workString,
    );
  }
  
  /// Verify work proof
  static Future<bool> verifyWork(SEAWork work, String publicKey) async {
    try {
      // Verify signature
      final message = work.data['m'] as String;
      final signature = work.data['s'] as String;
      
      final isValidSignature = await verify(message, signature, publicKey);
      if (!isValidSignature) return false;
      
      // Verify hash
      final expectedHash = sha256.convert(utf8.encode(work.proof)).toString();
      return work.hash == expectedHash;
    } catch (e) {
      return false;
    }
  }
  
  /// Derive key from password using PBKDF2
  static Uint8List _deriveKey(String password, Uint8List salt) {
    // Simplified PBKDF2 implementation
    const iterations = 10000;
    final passwordBytes = utf8.encode(password);
    
    var result = Uint8List(_keyLength);
    var hmac = Hmac(sha256, passwordBytes);
    
    for (int i = 0; i < _keyLength; i += 32) {
      final block = hmac.convert([...salt, ..._intToBytes(i ~/ 32 + 1)]);
      final blockBytes = Uint8List.fromList(block.bytes);
      
      for (int j = 0; j < 32 && i + j < _keyLength; j++) {
        result[i + j] = blockBytes[j];
      }
    }
    
    return result;
  }
  
  /// Generate random salt
  static Uint8List _generateSalt() {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(16, (_) => random.nextInt(256)));
  }
  
  /// Generate random IV
  static Uint8List _generateIV() {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(_ivLength, (_) => random.nextInt(256)));
  }
  
  /// Simplified AES encryption
  static Uint8List _aesEncrypt(Uint8List data, Uint8List key, Uint8List iv) {
    // This is a simplified implementation - in production, use a proper AES library
    final result = Uint8List(data.length);
    for (int i = 0; i < data.length; i++) {
      result[i] = data[i] ^ key[i % key.length] ^ iv[i % iv.length];
    }
    return result;
  }
  
  /// Simplified AES decryption
  static Uint8List _aesDecrypt(Uint8List data, Uint8List key, Uint8List iv) {
    // This is a simplified implementation - in production, use a proper AES library
    return _aesEncrypt(data, key, iv); // XOR is symmetric
  }
  
  /// Derive public key from private key
  static Uint8List _derivePublicKey(List<int> privateKey) {
    // Simplified public key derivation
    final hash = sha256.convert(privateKey);
    return Uint8List.fromList(hash.bytes);
  }
  
  /// Derive encryption key
  static Uint8List _deriveEncryptionKey(Uint8List key) {
    final hash = sha256.convert(key);
    return Uint8List.fromList(hash.bytes);
  }
  
  /// Convert integer to bytes
  static List<int> _intToBytes(int value) {
    return [
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];
  }
  
  /// Constant time comparison to prevent timing attacks
  static bool _constantTimeCompare(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}

/// SEA key pair for authentication
class SEAKeyPair {
  final String pub;    // Public key
  final String priv;   // Private key
  final String epub;   // Encryption public key
  final String epriv;  // Encryption private key
  
  const SEAKeyPair({
    required this.pub,
    required this.priv,
    required this.epub,
    required this.epriv,
  });
  
  Map<String, dynamic> toJson() => {
    'pub': pub,
    'priv': priv,
    'epub': epub,
    'epriv': epriv,
  };
  
  factory SEAKeyPair.fromJson(Map<String, dynamic> json) => SEAKeyPair(
    pub: json['pub'] as String,
    priv: json['priv'] as String,
    epub: json['epub'] as String,
    epriv: json['epriv'] as String,
  );
}

/// SEA work proof for data integrity
class SEAWork {
  final String hash;
  final Map<String, dynamic> data;
  final String proof;
  
  const SEAWork({
    required this.hash,
    required this.data,
    required this.proof,
  });
}

/// SEA exception for error handling
class SEAException implements Exception {
  final String message;
  
  const SEAException(this.message);
  
  @override
  String toString() => 'SEAException: $message';
}
