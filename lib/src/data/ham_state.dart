import '../utils/utils.dart';

/// HAM (Hypothetical Amnesia Machine) State implementation
/// Compatible with Gun.js HAM conflict resolution algorithm
/// 
/// HAM uses field-level timestamps for precise conflict resolution
/// and machine state counters for ordering operations correctly.
class HAMState {
  /// Field-level timestamps (key -> timestamp)
  /// This is the '>' field in Gun.js node metadata
  final Map<String, num> state;
  
  /// Machine state counter for this node
  /// Incremented for each operation on this machine
  final num machineState;
  
  /// Unique node identifier
  /// This corresponds to the '#' field in Gun.js
  final String nodeId;
  
  /// Machine identifier for this HAM instance
  final String machineId;
  
  const HAMState({
    required this.state,
    required this.machineState, 
    required this.nodeId,
    required this.machineId,
  });
  
  /// Create a new HAM state for a node
  factory HAMState.create(String nodeId, [String? machineId]) {
    return HAMState(
      state: {},
      machineState: 0,
      nodeId: nodeId,
      machineId: machineId ?? Utils.randomString(8),
    );
  }
  
  /// Create HAM state from Gun.js wire format
  factory HAMState.fromWireFormat(Map<String, dynamic> wireData) {
    final meta = wireData['_'] as Map<String, dynamic>? ?? {};
    final nodeId = meta['#'] as String? ?? '';
    final state = <String, num>{};
    
    // Parse the '>' field which contains field timestamps
    if (meta['>'] is Map) {
      final stateData = meta['>'] as Map;
      for (final entry in stateData.entries) {
        if (entry.value is num) {
          state[entry.key] = entry.value;
        }
      }
    }
    
    return HAMState(
      state: state,
      machineState: meta['machine'] as num? ?? 0,
      nodeId: nodeId,
      machineId: meta['machineId'] as String? ?? Utils.randomString(8),
    );
  }
  
  /// Convert to Gun.js wire format metadata
  Map<String, dynamic> toWireFormat() {
    return {
      '#': nodeId,
      '>': Map<String, dynamic>.from(state),
      'machine': machineState,
      'machineId': machineId,
    };
  }
  
  /// Update field timestamp
  HAMState updateField(String field, [num? timestamp]) {
    timestamp ??= _generateTimestamp();
    
    final newState = Map<String, num>.from(state);
    newState[field] = timestamp;
    
    return HAMState(
      state: newState,
      machineState: machineState + 1,
      nodeId: nodeId,
      machineId: machineId,
    );
  }
  
  /// Update multiple fields
  HAMState updateFields(List<String> fields, [num? timestamp]) {
    timestamp ??= _generateTimestamp();
    
    final newState = Map<String, num>.from(state);
    for (final field in fields) {
      newState[field] = timestamp;
    }
    
    return HAMState(
      state: newState,
      machineState: machineState + fields.length,
      nodeId: nodeId,
      machineId: machineId,
    );
  }
  
  /// Check if this HAM state is newer than another for a specific field
  bool isFieldNewer(String field, HAMState other) {
    final thisTime = state[field] ?? 0;
    final otherTime = other.state[field] ?? 0;
    
    if (thisTime > otherTime) return true;
    if (thisTime < otherTime) return false;
    
    // If timestamps are equal, use machine state as tie-breaker
    if (machineState > other.machineState) return true;
    if (machineState < other.machineState) return false;
    
    // If machine states are equal, use machine ID for deterministic ordering
    return machineId.compareTo(other.machineId) > 0;
  }
  
  /// Check if any field in this HAM state is newer than the other
  bool hasNewerFields(HAMState other) {
    for (final field in state.keys) {
      if (isFieldNewer(field, other)) return true;
    }
    return false;
  }
  
  /// Merge with another HAM state, keeping the newest timestamp for each field
  HAMState merge(HAMState other) {
    final mergedState = Map<String, num>.from(state);
    
    // Merge field timestamps - keep the newer one for each field
    for (final entry in other.state.entries) {
      final field = entry.key;
      final otherTime = entry.value;
      final thisTime = mergedState[field] ?? 0;
      
      if (otherTime > thisTime) {
        mergedState[field] = otherTime;
      } else if (otherTime == thisTime) {
        // Use machine state for tie-breaking
        if (other.machineState > machineState) {
          mergedState[field] = otherTime;
        } else if (other.machineState == machineState) {
          // Use machine ID for deterministic ordering
          if (other.machineId.compareTo(machineId) > 0) {
            mergedState[field] = otherTime;
          }
        }
      }
    }
    
    return HAMState(
      state: mergedState,
      machineState: [machineState, other.machineState].reduce((a, b) => a > b ? a : b) + 1,
      nodeId: nodeId, // Keep our node ID
      machineId: machineId, // Keep our machine ID
    );
  }
  
  /// Get timestamp for a specific field
  num? getFieldTimestamp(String field) => state[field];
  
  /// Check if this HAM state has a timestamp for a field
  bool hasField(String field) => state.containsKey(field);
  
  /// Get all fields with timestamps
  List<String> get fields => state.keys.toList();
  
  /// Copy with updated machine state
  HAMState copyWith({
    Map<String, num>? state,
    num? machineState,
    String? nodeId,
    String? machineId,
  }) {
    return HAMState(
      state: state ?? Map.from(this.state),
      machineState: machineState ?? this.machineState,
      nodeId: nodeId ?? this.nodeId,
      machineId: machineId ?? this.machineId,
    );
  }
  
  /// Generate a HAM-compatible timestamp
  /// Uses milliseconds since epoch, compatible with Gun.js
  static num _generateTimestamp() {
    return DateTime.now().millisecondsSinceEpoch;
  }
  
  /// Resolve conflict between two values using HAM algorithm
  /// Returns the value that should be used based on HAM timestamps
  static ResolvedValue resolveConflict(
    String field,
    dynamic currentValue,
    dynamic incomingValue,
    HAMState currentHAM,
    HAMState incomingHAM,
  ) {
    // If incoming HAM is newer for this field, use incoming value
    if (incomingHAM.isFieldNewer(field, currentHAM)) {
      return ResolvedValue(incomingValue, incomingHAM);
    }
    
    // If current HAM is newer, keep current value
    if (currentHAM.isFieldNewer(field, incomingHAM)) {
      return ResolvedValue(currentValue, currentHAM);
    }
    
    // If timestamps are equal, use deterministic comparison
    final comparison = _deterministicCompare(currentValue, incomingValue);
    if (comparison > 0) {
      return ResolvedValue(currentValue, currentHAM);
    } else {
      return ResolvedValue(incomingValue, incomingHAM);
    }
  }
  
  /// Deterministic comparison for tie-breaking (copied from CRDT)
  static int _deterministicCompare(dynamic a, dynamic b) {
    if (a == b) return 0;
    
    // Compare by type first
    final aType = _getTypeOrder(a);
    final bType = _getTypeOrder(b);
    
    if (aType != bType) {
      return aType.compareTo(bType);
    }
    
    // Same type comparison
    if (a is num && b is num) {
      return a.compareTo(b);
    }
    
    if (a is String && b is String) {
      return a.compareTo(b);
    }
    
    if (a is bool && b is bool) {
      return a ? 1 : (b ? -1 : 0);
    }
    
    // For complex types, convert to string and compare
    final aStr = a.toString();
    final bStr = b.toString();
    return aStr.compareTo(bStr);
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
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HAMState &&
        other.nodeId == nodeId &&
        other.machineId == machineId &&
        other.machineState == machineState &&
        _mapEquals(other.state, state);
  }
  
  @override
  int get hashCode {
    return Object.hash(
      nodeId,
      machineId,
      machineState,
      state.toString(), // Simple hash for map
    );
  }
  
  @override
  String toString() {
    return 'HAMState(node: $nodeId, machine: $machineId, state: $machineState, fields: ${state.length})';
  }
  
  /// Deep equality check for maps
  static bool _mapEquals(Map<String, num> a, Map<String, num> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) return false;
    }
    return true;
  }
}

/// Result of HAM conflict resolution
class ResolvedValue {
  final dynamic value;
  final HAMState hamState;
  
  const ResolvedValue(this.value, this.hamState);
}
