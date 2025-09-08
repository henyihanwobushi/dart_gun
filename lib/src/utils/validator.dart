import 'dart:convert';

/// Data validation utilities for Gun Dart
/// 
/// Provides comprehensive data validation, schema checking,
/// and data sanitization functions.
class Validator {
  /// Validate if a value is not null and not empty
  static bool isNotEmpty(dynamic value) {
    if (value == null) return false;
    if (value is String) return value.isNotEmpty;
    if (value is List) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return true;
  }
  
  /// Validate if a string is a valid email address
  static bool isValidEmail(String email) {
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    return emailRegex.hasMatch(email);
  }
  
  /// Validate if a string is a valid URL
  static bool isValidUrl(String url) {
    try {
      final uri = Uri.parse(url);
      // Require a scheme and a non-empty host
      return uri.hasScheme && uri.host.isNotEmpty;
    } catch (e) {
      return false;
    }
  }
  
  /// Validate if a string matches a pattern
  static bool matchesPattern(String value, String pattern) {
    try {
      final regex = RegExp(pattern);
      return regex.hasMatch(value);
    } catch (e) {
      return false;
    }
  }
  
  /// Validate if a value is of the expected type
  static bool isType<T>(dynamic value) {
    return value is T;
  }
  
  /// Validate if a number is within a range
  static bool isInRange(num value, num min, num max) {
    return value >= min && value <= max;
  }
  
  /// Validate if a string length is within bounds
  static bool isValidLength(String value, {int? min, int? max}) {
    final length = value.length;
    if (min != null && length < min) return false;
    if (max != null && length > max) return false;
    return true;
  }
  
  /// Validate if a password meets security requirements
  static bool isStrongPassword(String password, {
    int minLength = 8,
    bool requireUppercase = true,
    bool requireLowercase = true,
    bool requireNumbers = true,
    bool requireSpecialChars = true,
  }) {
    if (password.length < minLength) return false;
    
    if (requireUppercase && !password.contains(RegExp(r'[A-Z]'))) {
      return false;
    }
    
    if (requireLowercase && !password.contains(RegExp(r'[a-z]'))) {
      return false;
    }
    
    if (requireNumbers && !password.contains(RegExp(r'[0-9]'))) {
      return false;
    }
    
    if (requireSpecialChars && !password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
      return false;
    }
    
    return true;
  }
  
  /// Validate Gun node structure
  static bool isValidGunNode(Map<String, dynamic> node) {
    // Must have metadata
    if (!node.containsKey('_')) return false;
    
    final meta = node['_'];
    if (meta is! Map<String, dynamic>) return false;
    
    // Must have node ID
    if (!meta.containsKey('#') || meta['#'] is! String) return false;
    
    // Must have timestamp metadata
    if (!meta.containsKey('>') || meta['>'] is! Map) return false;
    
    return true;
  }
  
  /// Validate Gun key format
  static bool isValidGunKey(String key) {
    // Keys cannot be empty
    if (key.isEmpty) return false;
    
    // Keys cannot contain certain characters
    final invalidChars = RegExp(r'[\\/.#\[\]\s]');
    if (key.contains(invalidChars)) return false;
    
    // Keys cannot start with underscore (reserved)
    if (key.startsWith('_')) return false;
    
    return true;
  }
  
  /// Validate JSON structure
  static bool isValidJson(String jsonString) {
    try {
      // ignore: unused_local_variable
      final decoded = jsonDecode(jsonString);
      return true;
    } catch (e) {
      return false;
    }
  }
  
  /// Sanitize user input by removing dangerous characters
  static String sanitizeInput(String input, {
    bool allowHtml = false,
    bool allowSpecialChars = true,
  }) {
    String sanitized = input.trim();
    
    if (!allowHtml) {
      // Remove HTML tags
      sanitized = sanitized.replaceAll(RegExp(r'<[^>]*>'), '');
    }
    
    if (!allowSpecialChars) {
      // Remove potentially dangerous special characters
      sanitized = sanitized.replaceAll(RegExp(r'[<>"\\]'), '');
    }
    
    return sanitized;
  }
  
  /// Validate and sanitize Gun data before storage
  static Map<String, dynamic>? validateAndSanitizeGunData(dynamic data) {
    if (data == null) return null;
    
    Map<String, dynamic> dataMap;
    if (data is Map<String, dynamic>) {
      dataMap = Map.from(data);
    } else {
      // Wrap non-map data
      dataMap = {'_value': data};
    }
    
    // Remove invalid keys
    dataMap.removeWhere((key, value) => !isValidGunKey(key) && key != '_' && key != '_value');
    
    // Sanitize string values
    dataMap.forEach((key, value) {
      if (value is String) {
        dataMap[key] = sanitizeInput(value);
      }
    });
    
    return dataMap;
  }
  
  /// Validate schema compliance
  static ValidationResult validateSchema(dynamic data, Map<String, dynamic> schema) {
    final errors = <String>[];
    
    if (data is! Map<String, dynamic>) {
      errors.add('Data must be a Map');
      return ValidationResult(false, errors);
    }
    
    final dataMap = data;
    
    // Check required fields
    final required = schema['required'] as List<String>? ?? [];
    for (final field in required) {
      if (!dataMap.containsKey(field)) {
        errors.add('Missing required field: $field');
      }
    }
    
    // Check field types
    final properties = schema['properties'] as Map<String, dynamic>? ?? {};
    properties.forEach((field, fieldSchema) {
      if (dataMap.containsKey(field)) {
        final value = dataMap[field];
        final expectedType = fieldSchema['type'] as String?;
        
        if (expectedType != null) {
          bool isValidType = false;
          switch (expectedType) {
            case 'string':
              isValidType = value is String;
              break;
            case 'number':
              isValidType = value is num;
              break;
            case 'integer':
              isValidType = value is int;
              break;
            case 'boolean':
              isValidType = value is bool;
              break;
            case 'array':
              isValidType = value is List;
              break;
            case 'object':
              isValidType = value is Map;
              break;
          }
          
          if (!isValidType) {
            errors.add('Field $field must be of type $expectedType');
          }
        }
      }
    });
    
    return ValidationResult(errors.isEmpty, errors);
  }
  
  /// Check if data exceeds size limits
  static bool isWithinSizeLimit(dynamic data, int maxSizeBytes) {
    try {
      final jsonString = jsonEncode(data);
      final sizeBytes = utf8.encode(jsonString).length;
      return sizeBytes <= maxSizeBytes;
    } catch (e) {
      return false;
    }
  }
  
  /// Validate network message format
  static bool isValidNetworkMessage(Map<String, dynamic> message) {
    // Must have at least one recognized Gun message type
    final validTypes = ['get', 'put', 'hi', 'bye', 'dam'];
    return validTypes.any((type) => message.containsKey(type));
  }
}

/// Result of schema validation
class ValidationResult {
  final bool isValid;
  final List<String> errors;
  
  const ValidationResult(this.isValid, this.errors);
  
  @override
  String toString() {
    if (isValid) return 'Valid';
    return 'Invalid: ${errors.join(', ')}';
  }
}
