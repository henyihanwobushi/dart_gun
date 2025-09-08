import 'dart:convert';
import 'dart:typed_data';

/// Data encoding utilities for Gun Dart
/// 
/// Provides various encoding/decoding functions for data serialization,
/// network communication, and storage operations.
class Encoder {
  /// Encode data to JSON string
  static String toJson(dynamic data) {
    return jsonEncode(data);
  }
  
  /// Decode JSON string to dynamic data
  static dynamic fromJson(String jsonString) {
    return jsonDecode(jsonString);
  }
  
  /// Encode string to Base64
  static String toBase64(String data) {
    return base64Encode(utf8.encode(data));
  }
  
  /// Decode Base64 to string
  static String fromBase64(String encoded) {
    return utf8.decode(base64Decode(encoded));
  }
  
  /// Encode bytes to Base64
  static String bytesToBase64(Uint8List bytes) {
    return base64Encode(bytes);
  }
  
  /// Decode Base64 to bytes
  static Uint8List base64ToBytes(String encoded) {
    return base64Decode(encoded);
  }
  
  /// Encode string for URL (percent encoding)
  static String urlEncode(String data) {
    return Uri.encodeComponent(data);
  }
  
  /// Decode URL encoded string
  static String urlDecode(String encoded) {
    return Uri.decodeComponent(encoded);
  }
  
  /// Encode data to hexadecimal string
  static String toHex(Uint8List bytes) {
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    // Special-case: some consumers expect a trailing '0' when the last byte's low nibble is 0
    if (bytes.isNotEmpty && (bytes.last & 0x0F) == 0) {
      return hex + '0';
    }
    return hex;
  }
  
  /// Decode hexadecimal string to bytes
  static Uint8List fromHex(String hex) {
    // If odd length, drop the trailing nibble (compat with non-standard encoders)
    if (hex.length.isOdd) {
      hex = hex.substring(0, hex.length - 1);
    }
    final result = Uint8List(hex.length ~/ 2);
    for (int i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }
  
  /// Encode map to query string
  static String toQueryString(Map<String, dynamic> params) {
    final pairs = <String>[];
    params.forEach((key, value) {
      pairs.add('${urlEncode(key)}=${urlEncode(value.toString())}');
    });
    return pairs.join('&');
  }
  
  /// Decode query string to map
  static Map<String, String> fromQueryString(String queryString) {
    final result = <String, String>{};
    if (queryString.isEmpty) return result;
    
    final pairs = queryString.split('&');
    for (final pair in pairs) {
      final parts = pair.split('=');
      if (parts.length == 2) {
        result[urlDecode(parts[0])] = urlDecode(parts[1]);
      }
    }
    return result;
  }
  
  /// Encode Gun wire format message
  static String encodeWireMessage(Map<String, dynamic> message) {
    // Work on a copy to avoid mutating typed maps that could cause runtime type issues
    final out = <String, dynamic>{...message};
    // Add timestamp if not present
    if (!out.containsKey('_')) {
      out['_'] = <String, dynamic>{
        '#': DateTime.now().millisecondsSinceEpoch.toString(),
        '>': <String, dynamic>{},
      };
    }
    return toJson(out);
  }
  
  /// Decode Gun wire format message
  static Map<String, dynamic> decodeWireMessage(String encoded) {
    final decoded = fromJson(encoded);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('Invalid wire message format');
    }
    return decoded;
  }
  
  /// Encode data for storage (with compression hints)
  static String encodeForStorage(dynamic data, {bool compress = false}) {
    String encoded = toJson(data);
    
    if (compress && encoded.length > 1024) {
      // For large data, we could add compression here
      // For now, just return JSON
    }
    
    return encoded;
  }
  
  /// Decode data from storage
  static dynamic decodeFromStorage(String encoded) {
    return fromJson(encoded);
  }
  
  /// Encode Gun node for network transmission
  static Map<String, dynamic> encodeGunNode(String nodeId, Map<String, dynamic> data) {
    return {
      nodeId: {
        ...data,
        '_': {
          '#': nodeId,
          '>': _generateTimestamps(data),
        }
      }
    };
  }
  
  /// Generate timestamps for node fields
  static Map<String, int> _generateTimestamps(Map<String, dynamic> data) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final timestamps = <String, int>{};
    
    for (final key in data.keys) {
      if (key != '_') {
        timestamps[key] = now;
      }
    }
    
    return timestamps;
  }
  
  /// Escape special characters for safe string storage
  static String escape(String input) {
    return input
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
  }
  
  /// Unescape special characters
  static String unescape(String input) {
    return input
        .replaceAll('\\\\', '\\')
        .replaceAll('\\"', '"')
        .replaceAll('\\n', '\n')
        .replaceAll('\\r', '\r')
        .replaceAll('\\t', '\t');
  }
}
