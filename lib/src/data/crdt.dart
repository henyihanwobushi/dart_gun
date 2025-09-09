import 'ham_state.dart';

/// Conflict-free Replicated Data Types implementation for Gun Dart
/// Based on Gun.js CRDT algorithms for distributed data synchronization
/// Now uses HAM (Hypothetical Amnesia Machine) for Gun.js compatibility
class CRDT {
  /// Resolves conflicts between two values based on Gun's HAM (Hypothetical Amnesia Machine)
  /// Returns the value that should be used, or null if both should be rejected
  static dynamic resolve(dynamic current, dynamic incoming, 
      {DateTime? currentTime, DateTime? incomingTime}) {
    // If no current value exists, use incoming
    if (current == null) return incoming;
    
    // If no incoming value, keep current
    if (incoming == null) return current;
    
    // Use timestamps for conflict resolution (Last Write Wins with tie-breaking)
    currentTime ??= DateTime.now();
    incomingTime ??= DateTime.now();
    
    if (incomingTime.isAfter(currentTime)) {
      return incoming;
    } else if (currentTime.isAfter(incomingTime)) {
      return current;
    }
    
    // For tie-breaking when timestamps are equal, use deterministic comparison
    return _deterministicCompare(current, incoming);
  }
  
  /// Merges two Gun nodes using HAM timestamps, resolving conflicts for each property
  static Map<String, dynamic> mergeNodes(Map<String, dynamic> current, 
      Map<String, dynamic> incoming) {
    final result = Map<String, dynamic>.from(current);
    
    // Extract HAM states from metadata
    final currentHAM = current.containsKey('_') 
        ? HAMState.fromWireFormat(current)
        : HAMState.create('');
    final incomingHAM = incoming.containsKey('_')
        ? HAMState.fromWireFormat(incoming) 
        : HAMState.create('');
    
    // Merge HAM state first
    final mergedHAM = currentHAM.merge(incomingHAM);
    
    for (final key in incoming.keys) {
      if (key.startsWith('_')) {
        // Handle metadata fields specially - use merged HAM state
        if (key == '_') {
          result[key] = mergedHAM.toWireFormat();
        } else {
          result[key] = incoming[key];
        }
      } else {
        // Regular data field - use HAM-based CRDT resolution
        final currentVal = current[key];
        final incomingVal = incoming[key];
        final resolved = resolveWithHAM(key, currentVal, incomingVal, currentHAM, incomingHAM);
        if (resolved.value != null) {
          result[key] = resolved.value;
        }
      }
    }
    
    return result;
  }
  
  /// Merges two Gun nodes using HAM timestamps with explicit HAM states
  static Map<String, dynamic> mergeNodesWithHAM(
    Map<String, dynamic> current, 
    Map<String, dynamic> incoming,
    HAMState currentHAM,
    HAMState incomingHAM,
  ) {
    final result = Map<String, dynamic>.from(current);
    
    // Merge HAM state first
    final mergedHAM = currentHAM.merge(incomingHAM);
    
    for (final key in incoming.keys) {
      if (key.startsWith('_')) {
        // Handle metadata fields - use merged HAM state
        if (key == '_') {
          result[key] = mergedHAM.toWireFormat();
        }
      } else {
        // Regular data field - use HAM-based resolution
        final currentVal = current[key];
        final incomingVal = incoming[key];
        final resolved = HAMState.resolveConflict(key, currentVal, incomingVal, currentHAM, incomingHAM);
        result[key] = resolved.value;
      }
    }
    
    // Ensure metadata is present
    result['_'] = mergedHAM.toWireFormat();
    
    return result;
  }
  
  /// Resolve conflict using HAM timestamps
  static ResolvedValue resolveWithHAM(
    String field,
    dynamic current, 
    dynamic incoming,
    HAMState currentHAM,
    HAMState incomingHAM,
  ) {
    return HAMState.resolveConflict(field, current, incoming, currentHAM, incomingHAM);
  }
  
  /// Merges metadata between nodes
  static Map<String, dynamic> _mergeMeta(dynamic current, dynamic incoming) {
    if (current is! Map && incoming is! Map) {
      return {'#': incoming, '>': DateTime.now().millisecondsSinceEpoch};
    }
    
    final currentMeta = current is Map ? Map<String, dynamic>.from(current) : <String, dynamic>{};
    final incomingMeta = incoming is Map ? Map<String, dynamic>.from(incoming) : <String, dynamic>{};
    
    // Merge state timestamps
    for (final key in incomingMeta.keys) {
      if (key == '>') continue; // Skip the vector clock field
      final currentTime = currentMeta[key] as int? ?? 0;
      final incomingTime = incomingMeta[key] as int? ?? 0;
      if (incomingTime > currentTime) {
        currentMeta[key] = incomingTime;
      }
    }
    
    return currentMeta;
  }
  
  /// Deterministic comparison for tie-breaking
  static dynamic _deterministicCompare(dynamic a, dynamic b) {
    if (a == b) return a;
    
    // Compare by type first
    final aType = _getTypeOrder(a);
    final bType = _getTypeOrder(b);
    
    if (aType != bType) {
      return aType > bType ? a : b;
    }
    
    // Same type comparison
    if (a is num && b is num) {
      return a > b ? a : b;
    }
    
    if (a is String && b is String) {
      return a.compareTo(b) > 0 ? a : b;
    }
    
    if (a is bool && b is bool) {
      return a ? a : b; // true > false
    }
    
    // For complex types, convert to string and compare
    final aStr = a.toString();
    final bStr = b.toString();
    return aStr.compareTo(bStr) > 0 ? a : b;
  }
  
  /// Gets type ordering for deterministic comparison
  static int _getTypeOrder(dynamic value) {
    if (value == null) return 0;
    if (value is bool) return 1;
    if (value is num) return 2;
    if (value is String) return 3;
    if (value is List) return 4;
    if (value is Map) return 5;
    return 6; // Other types
  }
  
  /// Generates a vector clock timestamp
  static int generateTimestamp() {
    return DateTime.now().millisecondsSinceEpoch;
  }
  
  /// Creates a Gun node with proper HAM metadata
  static Map<String, dynamic> createNode(String nodeId, Map<String, dynamic> data, [HAMState? hamState]) {
    var currentHAM = hamState ?? HAMState.create(nodeId);
    
    // Update HAM state for all data fields with unique timestamps
    for (final key in data.keys) {
      final timestamp = DateTime.now().millisecondsSinceEpoch + 
          DateTime.now().microsecond / 1000.0; // Add microsecond precision
      currentHAM = currentHAM.updateField(key, timestamp);
    }
    
    final result = Map<String, dynamic>.from(data);
    result['_'] = currentHAM.toWireFormat();
    
    return result;
  }
  
  /// Updates a Gun node with new data and HAM timestamps
  static Map<String, dynamic> updateNode(
    Map<String, dynamic> node, 
    String field, 
    dynamic value,
    [HAMState? hamState]
  ) {
    final currentHAM = hamState ?? (node.containsKey('_') 
        ? HAMState.fromWireFormat(node)
        : HAMState.create(''));
    
    final updatedHAM = currentHAM.updateField(field);
    final result = Map<String, dynamic>.from(node);
    result[field] = value;
    result['_'] = updatedHAM.toWireFormat();
    
    return result;
  }
  
  /// Creates a Gun state vector for a value (legacy compatibility)
  static Map<String, int> createState(String key, [int? timestamp]) {
    return {key: timestamp ?? generateTimestamp()};
  }
  
  /// Checks if one state vector is newer than another (legacy compatibility)
  static bool isNewer(Map<String, int>? incoming, Map<String, int>? current) {
    if (incoming == null) return false;
    if (current == null) return true;
    
    for (final key in incoming.keys) {
      final incomingTime = incoming[key] ?? 0;
      final currentTime = current[key] ?? 0;
      if (incomingTime > currentTime) return true;
    }
    return false;
  }
  
  /// Extract HAM state from a Gun node
  static HAMState extractHAMState(Map<String, dynamic> node) {
    if (node.containsKey('_')) {
      return HAMState.fromWireFormat(node);
    }
    return HAMState.create('');
  }
  
  /// Check if a node has valid HAM metadata
  static bool hasValidHAM(Map<String, dynamic> node) {
    if (!node.containsKey('_')) return false;
    final meta = node['_'];
    return meta is Map && meta.containsKey('#') && meta.containsKey('>');
  }
  
  /// Convert legacy vector clock format to HAM format
  static HAMState vectorClockToHAM(String nodeId, Map<String, int> vectorClock) {
    final state = <String, num>{};
    for (final entry in vectorClock.entries) {
      state[entry.key] = entry.value.toDouble();
    }
    return HAMState(
      state: state,
      machineState: 0,
      nodeId: nodeId,
      machineId: 'legacy',
    );
  }
}
