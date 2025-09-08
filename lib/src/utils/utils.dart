import 'dart:math';

/// Utility functions for Gun Dart
class Utils {
  static final Random _random = Random();
  
  /// Generate a random string of specified length
  static String randomString(int length, [String? chars]) {
    chars ??= '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
    return String.fromCharCodes(Iterable.generate(
      length, (_) => chars!.codeUnitAt(_random.nextInt(chars.length))));
  }
  
  /// Generate a unique identifier
  static String generateId([int length = 16]) {
    return randomString(length);
  }
  
  /// Check if an object is plain (JSON-serializable)
  static bool isPlain(dynamic obj) {
    if (obj == null) return true;
    if (obj is bool || obj is num || obj is String) return true;
    if (obj is List) {
      return obj.every(isPlain);
    }
    if (obj is Map) {
      return obj.values.every(isPlain) && obj.keys.every((k) => k is String);
    }
    return false;
  }
  
  /// Deep copy an object
  static dynamic deepCopy(dynamic obj) {
    if (obj == null || obj is bool || obj is num || obj is String) {
      return obj;
    }
    if (obj is List) {
      return obj.map(deepCopy).toList();
    }
    if (obj is Map) {
      return obj.map((key, value) => MapEntry(key, deepCopy(value)));
    }
    // For non-JSON types, return as-is (or throw)
    return obj;
  }
  
  /// Check if two objects are deeply equal
  static bool deepEqual(dynamic a, dynamic b) {
    if (identical(a, b)) return true;
    if (a.runtimeType != b.runtimeType) return false;
    
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (int i = 0; i < a.length; i++) {
        if (!deepEqual(a[i], b[i])) return false;
      }
      return true;
    }
    
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key) || !deepEqual(a[key], b[key])) {
          return false;
        }
      }
      return true;
    }
    
    return a == b;
  }
  
  /// Merge two maps deeply
  static Map<String, dynamic> deepMerge(
    Map<String, dynamic> target,
    Map<String, dynamic> source,
  ) {
    final result = Map<String, dynamic>.from(target);
    
    for (final entry in source.entries) {
      final key = entry.key;
      final value = entry.value;
      
      if (result.containsKey(key) && 
          result[key] is Map && 
          value is Map) {
        result[key] = deepMerge(
          result[key] as Map<String, dynamic>,
          value as Map<String, dynamic>,
        );
      } else {
        result[key] = deepCopy(value);
      }
    }
    
    return result;
  }
  
  /// Check if a map is empty (ignoring metadata keys starting with _)
  static bool isEmpty(Map<String, dynamic> map) {
    return map.keys.where((k) => !k.startsWith('_')).isEmpty;
  }
  
  /// Get keys from a map excluding metadata
  static List<String> getDataKeys(Map<String, dynamic> map) {
    return map.keys.where((k) => !k.startsWith('_')).toList();
  }
  
  /// Hash a string using a simple algorithm
  static int hashString(String str) {
    if (str.isEmpty) return 0;
    int hash = 0;
    for (int i = 0; i < str.length; i++) {
      final char = str.codeUnitAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & 0xFFFFFFFF; // Convert to 32-bit integer
    }
    return hash;
  }
  
  /// Convert milliseconds timestamp to DateTime
  static DateTime timestampToDateTime(int timestamp) {
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }
  
  /// Convert DateTime to milliseconds timestamp
  static int dateTimeToTimestamp(DateTime dateTime) {
    return dateTime.millisecondsSinceEpoch;
  }
  
  /// Sanitize a string for use as a key
  static String sanitizeKey(String key) {
    return key.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  }
  
  /// Check if a string matches a pattern
  static bool matchPattern(String text, String pattern) {
    if (pattern.isEmpty) return text.isEmpty;
    if (pattern == '*') return true;
    if (pattern.startsWith('*') && pattern.endsWith('*')) {
      final middle = pattern.substring(1, pattern.length - 1);
      return text.contains(middle);
    }
    if (pattern.startsWith('*')) {
      final suffix = pattern.substring(1);
      return text.endsWith(suffix);
    }
    if (pattern.endsWith('*')) {
      final prefix = pattern.substring(0, pattern.length - 1);
      return text.startsWith(prefix);
    }
    return text == pattern;
  }
}
