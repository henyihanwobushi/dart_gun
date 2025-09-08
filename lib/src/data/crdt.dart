
/// Conflict-free Replicated Data Types implementation for Gun Dart
/// Based on Gun.js CRDT algorithms for distributed data synchronization
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
  
  /// Merges two Gun nodes, resolving conflicts for each property
  static Map<String, dynamic> mergeNodes(Map<String, dynamic> current, 
      Map<String, dynamic> incoming) {
    final result = Map<String, dynamic>.from(current);
    
    for (final key in incoming.keys) {
      if (key.startsWith('_')) {
        // Handle metadata fields specially
        if (key == '_') {
          // Node metadata - merge timestamps
          result[key] = _mergeMeta(current[key], incoming[key]);
        } else {
          result[key] = incoming[key];
        }
      } else {
        // Regular data field - use CRDT resolution
        final currentVal = current[key];
        final incomingVal = incoming[key];
        final resolved = resolve(currentVal, incomingVal);
        if (resolved != null) {
          result[key] = resolved;
        }
      }
    }
    
    return result;
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
  
  /// Creates a Gun state vector for a value
  static Map<String, int> createState(String key, [int? timestamp]) {
    return {key: timestamp ?? generateTimestamp()};
  }
  
  /// Checks if one state vector is newer than another
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
}
