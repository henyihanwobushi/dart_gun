/// Gun.js compatible SEA (Security, Encryption, Authorization) implementation
///
/// This file provides a compatibility layer that exposes the Gun.js compatible
/// SEA implementation under the expected `SEA` class name while maintaining
/// backward compatibility with the legacy API.

import 'dart:convert';
import 'package:crypto/crypto.dart';

// Import the Gun.js compatible implementation
import 'sea_gunjs.dart' as gunjs;
import '../utils/utils.dart';

// Type aliases for backward compatibility
typedef SEAKeyPair = gunjs.SEAKeyPair;
typedef SEAException = gunjs.SEAException;

/// Gun.js compatible SEA (Security, Encryption, Authorization) class
/// 
/// This provides backward compatibility with the legacy API while using
/// the Gun.js compatible implementation underneath.
class SEA {
  /// Generate a Gun.js compatible cryptographic key pair
  static Future<SEAKeyPair> pair() => gunjs.SEAGunJS.pair();
  
  /// Gun.js compatible encryption
  static Future<String> encrypt(dynamic data, String password) => 
      gunjs.SEAGunJS.encrypt(data, password);
  
  /// Gun.js compatible decryption
  static Future<dynamic> decrypt(String encryptedData, String password) => 
      gunjs.SEAGunJS.decrypt(encryptedData, password);
  
  /// Gun.js compatible digital signature
  static Future<String> sign(dynamic data, SEAKeyPair keyPair) => 
      gunjs.SEAGunJS.sign(data, keyPair);
  
  /// Gun.js compatible signature verification
  static Future<bool> verify(dynamic data, String signature, String publicKey) => 
      gunjs.SEAGunJS.verify(data, signature, publicKey);
  
  /// Legacy-compatible work function
  /// 
  /// This adapts the Gun.js work format to match the legacy API expectations
  static Future<SEAWork> work(dynamic data, SEAKeyPair keyPair, [String? previous]) async {
    final dataString = jsonEncode(data);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final nonce = Utils.randomString(16);
    
    // Create work object similar to legacy format
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
  
  /// Legacy-compatible work verification
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
}

/// Work proof structure for backward compatibility
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
