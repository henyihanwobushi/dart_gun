import '../utils/utils.dart';

/// Gun.js compatible wire protocol implementation
/// 
/// This class provides message formatting and parsing that matches
/// the Gun.js wire protocol exactly for full interoperability.
class GunWireProtocol {
  
  /// Create a Gun.js compatible 'get' message
  /// 
  /// Example output:
  /// {
  ///   "get": {"#": "users/alice"},
  ///   "@": "msg-id-12345"
  /// }
  static Map<String, dynamic> createGetMessage(String key, {String? messageId}) {
    return {
      'get': {'#': key},
      '@': messageId ?? _generateMessageId(),
    };
  }
  
  /// Create a Gun.js compatible 'put' message with HAM metadata
  /// 
  /// Example output:
  /// {
  ///   "put": {
  ///     "users/alice": {
  ///       "name": "Alice",
  ///       "_": {
  ///         "#": "users/alice",
  ///         ">": {"name": 1640995200000}
  ///       }
  ///     }
  ///   },
  ///   "@": "msg-id-12345"
  /// }
  static Map<String, dynamic> createPutMessage(
    String key, 
    Map<String, dynamic> data, {
    String? messageId,
    Map<String, num>? hamState,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final state = hamState ?? <String, num>{};
    
    // Add HAM state for each field in the data
    for (final field in data.keys) {
      if (field != '_') {  // Don't add state for metadata field
        state[field] = state[field] ?? now;
      }
    }
    
    final nodeData = {
      ...data,
      '_': {
        '#': key,
        '>': state,
      }
    };
    
    return {
      'put': {key: nodeData},
      '@': messageId ?? _generateMessageId(),
    };
  }
  
  /// Create a Gun.js compatible 'hi' handshake message
  /// 
  /// Example output:
  /// {
  ///   "hi": {
  ///     "gun": "dart-0.2.1",
  ///     "pid": "dart-peer-abc123"
  ///   },
  ///   "@": "handshake-456"
  /// }
  static Map<String, dynamic> createHiMessage({
    String? messageId,
    String version = 'dart-0.2.1',
    String? peerId,
  }) {
    return {
      'hi': {
        'gun': version,
        'pid': peerId ?? 'dart-peer-${_generatePeerId()}',
      },
      '@': messageId ?? _generateMessageId(),
    };
  }
  
  /// Create a Gun.js compatible 'bye' disconnect message
  /// 
  /// Example output:
  /// {
  ///   "bye": {"#": "peer-id"},
  ///   "@": "bye-msg-789"
  /// }
  static Map<String, dynamic> createByeMessage({
    String? messageId,
    String? peerId,
  }) {
    return {
      'bye': peerId != null ? {'#': peerId} : {},
      '@': messageId ?? _generateMessageId(),
    };
  }
  
  /// Create a Gun.js compatible 'dam' error message
  /// 
  /// Example output:
  /// {
  ///   "dam": "Error message here",
  ///   "@": "error-msg-123",
  ///   "#": "original-msg-456"
  /// }
  static Map<String, dynamic> createDamMessage(
    String errorMessage, {
    String? messageId,
    String? replyToMessageId,
  }) {
    final message = <String, dynamic>{
      'dam': errorMessage,
      '@': messageId ?? _generateMessageId(),
    };
    
    if (replyToMessageId != null) {
      message['#'] = replyToMessageId;
    }
    
    return message;
  }
  
  /// Create acknowledgment message
  /// 
  /// Example output:
  /// {
  ///   "ok": true,
  ///   "@": "ack-msg-789",
  ///   "#": "original-msg-123"
  /// }
  static Map<String, dynamic> createAckMessage(
    String originalMessageId, {
    String? messageId,
    dynamic result,
  }) {
    return {
      'ok': result ?? true,
      '@': messageId ?? _generateMessageId(),
      '#': originalMessageId,
    };
  }
  
  /// Parse incoming Gun.js wire message
  /// 
  /// Returns a GunWireMessage object with parsed content
  static GunWireMessage parseMessage(Map<String, dynamic> rawMessage) {
    try {
      // Clean PUT data if present to handle complex Gun.js metadata
      Map<String, dynamic>? cleanedPut;
      final rawPut = _castToStringDynamicMap(rawMessage['put']);
      if (rawPut != null) {
        cleanedPut = _cleanGunJSMetadata(rawPut);
      }
      
      return GunWireMessage(
        get: _castToStringDynamicMap(rawMessage['get']),
        put: cleanedPut,
        hi: _castToStringDynamicMap(rawMessage['hi']),
        bye: rawMessage['bye'],
        dam: _safeStringCast(rawMessage['dam']),
        ok: rawMessage['ok'],
        messageId: _safeStringCast(rawMessage['@']),
        ackId: _safeStringCast(rawMessage['#']),
        raw: rawMessage,
      );
    } catch (e) {
      print('GunWireProtocol: Error parsing message: $e');
      // Return a minimal wire message for unknown formats
      return GunWireMessage(
        dam: rawMessage['dam']?.toString(),
        ok: rawMessage['ok'],
        messageId: rawMessage['@']?.toString(),
        ackId: rawMessage['#']?.toString(),
        raw: rawMessage,
      );
    }
  }
  
  /// Safely cast to Map<String, dynamic> or return null
  static Map<String, dynamic>? _castToStringDynamicMap(dynamic value) {
    if (value == null) return null;
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return null;
  }
  
  /// Safely cast to String or return null
  static String? _safeStringCast(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    return value.toString();
  }
  
  /// Extract HAM state from node data
  static Map<String, num>? extractHamState(Map<String, dynamic> nodeData) {
    final metadata = nodeData['_'] as Map<String, dynamic>?;
    if (metadata == null) return null;
    
    final state = metadata['>'] as Map<String, dynamic>?;
    if (state == null) return null;
    
    return state.map((key, value) => MapEntry(key, value as num));
  }
  
  /// Extract node ID from node data
  static String? extractNodeId(Map<String, dynamic> nodeData) {
    final metadata = nodeData['_'] as Map<String, dynamic>?;
    return metadata?['#'] as String?;
  }
  
  /// Merge HAM states using Gun.js HAM algorithm
  static Map<String, num> mergeHamStates(
    Map<String, num> state1, 
    Map<String, num> state2,
  ) {
    final merged = <String, num>{...state1};
    
    for (final entry in state2.entries) {
      final key = entry.key;
      final value = entry.value;
      final existing = merged[key];
      
      if (existing == null || value > existing) {
        merged[key] = value;
      }
    }
    
    return merged;
  }
  
  /// Generate unique message ID
  static String _generateMessageId() {
    return Utils.randomString(8);
  }
  
  /// Generate unique peer ID
  static String _generatePeerId() {
    return Utils.randomString(8);
  }
  
  /// Clean up complex Gun.js metadata structures for proper HAM conflict resolution
  /// Gun.js can send complex nested metadata that needs to be simplified for dart_gun HAM logic
  static Map<String, dynamic> _cleanGunJSMetadata(Map<String, dynamic> putData) {
    print('GunWireProtocol: Cleaning Gun.js metadata for: ${putData.keys}');
    final cleaned = <String, dynamic>{};
    
    for (final entry in putData.entries) {
      final nodeId = entry.key;
      final nodeData = entry.value;
      
      if (nodeData is Map<String, dynamic>) {
        print('GunWireProtocol: Processing node $nodeId with fields: ${nodeData.keys}');
        final cleanedNodeData = <String, dynamic>{};
        
        // Extract the main data fields and clean up metadata
        for (final nodeEntry in nodeData.entries) {
          final fieldKey = nodeEntry.key;
          final fieldValue = nodeEntry.value;
          
          if (fieldKey == '_') {
            // Handle Gun.js metadata - simplify complex nested structures
            if (fieldValue is Map<String, dynamic>) {
              final simplifiedMeta = <String, dynamic>{};
              
              // Preserve node ID
              if (fieldValue.containsKey('#')) {
                simplifiedMeta['#'] = fieldValue['#'];
              }
              
              // Handle timestamps - flatten nested timestamp structures
              if (fieldValue.containsKey('>')) {
                final timestamps = fieldValue['>'];
                if (timestamps is Map<String, dynamic>) {
                  final cleanTimestamps = <String, dynamic>{};
                  
                  for (final tsEntry in timestamps.entries) {
                    final tsKey = tsEntry.key;
                    final tsValue = tsEntry.value;
                    
                    // Only include numeric timestamps, ignore nested references
                    if (tsValue is num && tsKey != '#' && tsKey != '>') {
                      cleanTimestamps[tsKey] = tsValue;
                    }
                  }
                  
                  if (cleanTimestamps.isNotEmpty) {
                    simplifiedMeta['>'] = cleanTimestamps;
                  }
                }
              }
              
              print('GunWireProtocol: Simplified metadata for $nodeId: $simplifiedMeta');
              cleanedNodeData['_'] = simplifiedMeta;
            } else {
              cleanedNodeData[fieldKey] = fieldValue;
            }
          } else if (fieldKey == '#' || fieldKey == '>') {
            // Skip top-level metadata fields that should be inside '_'
            print('GunWireProtocol: Skipping top-level metadata field: $fieldKey');
            continue;
          } else {
            // Regular data field - keep as-is
            cleanedNodeData[fieldKey] = fieldValue;
          }
        }
        
        print('GunWireProtocol: Cleaned node $nodeId: $cleanedNodeData');
        cleaned[nodeId] = cleanedNodeData;
      } else {
        // Non-map data, keep as-is
        cleaned[nodeId] = nodeData;
      }
    }
    
    print('GunWireProtocol: Final cleaned data: $cleaned');
    return cleaned;
  }
}

/// Parsed Gun.js wire message
class GunWireMessage {
  /// 'get' query data
  final Map<String, dynamic>? get;
  
  /// 'put' operation data
  final Map<String, dynamic>? put;
  
  /// 'hi' handshake data
  final Map<String, dynamic>? hi;
  
  /// 'bye' disconnect data
  final dynamic bye;
  
  /// 'dam' error message
  final String? dam;
  
  /// 'ok' acknowledgment data
  final dynamic ok;
  
  /// Message ID ('@' field)
  final String? messageId;
  
  /// Acknowledgment ID ('#' field)
  final String? ackId;
  
  /// Raw message data
  final Map<String, dynamic> raw;
  
  const GunWireMessage({
    this.get,
    this.put,
    this.hi,
    this.bye,
    this.dam,
    this.ok,
    this.messageId,
    this.ackId,
    required this.raw,
  });
  
  /// Get message type
  GunMessageType get type {
    if (get != null) return GunMessageType.get;
    if (put != null) return GunMessageType.put;
    if (hi != null) return GunMessageType.hi;
    if (bye != null) return GunMessageType.bye;
    if (dam != null) return GunMessageType.dam;
    if (ok != null) return GunMessageType.ok;
    return GunMessageType.unknown;
  }
  
  /// Check if this message is an acknowledgment
  bool get isAck => ackId != null;
  
  /// Check if this message is an error
  bool get isError => dam != null;
  
  /// Check if this message requires acknowledgment
  bool get requiresAck => messageId != null && !isAck;
  
  @override
  String toString() => 'GunWireMessage(type: $type, id: $messageId, ack: $ackId)';
}

/// Gun.js message types
enum GunMessageType {
  get,
  put,
  hi,
  bye,
  dam,
  ok,
  unknown,
}
