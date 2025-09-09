import 'dart:math';
import '../utils/utils.dart';

/// Gun.js compatible metadata manager
/// 
/// Handles automatic creation, validation, and maintenance of Gun.js
/// compatible metadata for all nodes in the system.
class MetadataManager {
  static final Random _random = Random();
  static String? _machineId;
  static int _machineState = 0;
  
  /// Get or generate machine ID for this Gun instance
  static String get machineId {
    _machineId ??= Utils.randomString(8);
    return _machineId!;
  }
  
  /// Generate next machine state
  static int get nextMachineState => ++_machineState;
  
  /// Create Gun.js compatible metadata for a node
  /// 
  /// Creates the `_` metadata field with:
  /// - `#`: Unique node ID
  /// - `>`: HAM timestamps for each field
  /// - `machine`: Machine state counter
  /// - `machineId`: Machine identifier
  static Map<String, dynamic> createMetadata({
    required String nodeId,
    required Map<String, dynamic> data,
    Map<String, num>? existingTimestamps,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final timestamps = <String, num>{};
    
    // Start with existing timestamps
    if (existingTimestamps != null) {
      timestamps.addAll(existingTimestamps);
    }
    
    // Create timestamps for each data field
    for (final key in data.keys) {
      if (key != '_') {  // Skip metadata field itself
        timestamps[key] = existingTimestamps?[key] ?? now;
      }
    }
    
    return {
      '#': nodeId,
      '>': timestamps,
      'machine': nextMachineState,
      'machineId': machineId,
    };
  }
  
  /// Add or update metadata for a data node
  /// 
  /// Takes raw data and returns data with proper Gun.js metadata
  static Map<String, dynamic> addMetadata({
    required String nodeId,
    required Map<String, dynamic> data,
    Map<String, dynamic>? existingMetadata,
  }) {
    // Extract existing timestamps if available
    Map<String, num>? existingTimestamps;
    if (existingMetadata != null && existingMetadata['>'] is Map) {
      final timestampMap = existingMetadata['>'] as Map<String, dynamic>;
      existingTimestamps = timestampMap.map((key, value) => 
          MapEntry(key, value is num ? value : DateTime.now().millisecondsSinceEpoch));
    }
    
    // Create new metadata
    final metadata = createMetadata(
      nodeId: nodeId,
      data: data,
      existingTimestamps: existingTimestamps,
    );
    
    // Combine data with metadata
    final result = Map<String, dynamic>.from(data);
    result['_'] = metadata;
    return result;
  }
  
  /// Extract metadata from a Gun.js node
  /// 
  /// Returns the `_` metadata field or null if not found
  static Map<String, dynamic>? extractMetadata(Map<String, dynamic> node) {
    final metadata = node['_'];
    return metadata is Map<String, dynamic> ? metadata : null;
  }
  
  /// Get node ID from metadata
  static String? getNodeId(Map<String, dynamic> node) {
    final metadata = extractMetadata(node);
    return metadata?['#'] as String?;
  }
  
  /// Get HAM timestamps from metadata
  static Map<String, num>? getTimestamps(Map<String, dynamic> node) {
    final metadata = extractMetadata(node);
    final timestamps = metadata?['>'];
    
    if (timestamps is Map<String, dynamic>) {
      return timestamps.map((key, value) => 
          MapEntry(key, value is num ? value : 0));
    }
    
    return null;
  }
  
  /// Validate that a node has proper Gun.js metadata
  /// 
  /// Returns true if the node has valid metadata structure
  static bool isValidNode(Map<String, dynamic> node) {
    final metadata = extractMetadata(node);
    if (metadata == null) return false;
    
    // Check required fields
    if (!metadata.containsKey('#')) return false;  // Node ID required
    if (!metadata.containsKey('>')) return false;  // Timestamps required
    
    // Validate node ID
    final nodeId = metadata['#'];
    if (nodeId is! String || nodeId.isEmpty) return false;
    
    // Validate timestamps
    final timestamps = metadata['>'];
    if (timestamps is! Map) return false;
    
    return true;
  }
  
  /// Merge two nodes with HAM conflict resolution
  /// 
  /// Merges data from two nodes using HAM timestamps to resolve conflicts
  static Map<String, dynamic> mergeNodes(
    Map<String, dynamic> current,
    Map<String, dynamic> incoming,
  ) {
    final currentTimestamps = getTimestamps(current) ?? <String, num>{};
    final incomingTimestamps = getTimestamps(incoming) ?? <String, num>{};
    final currentNodeId = getNodeId(current);
    final incomingNodeId = getNodeId(incoming);
    
    // Use the node ID from the incoming data if current doesn't have one
    final nodeId = currentNodeId ?? incomingNodeId;
    if (nodeId == null) {
      throw StateError('Cannot merge nodes without node IDs');
    }
    
    final mergedData = <String, dynamic>{};
    final mergedTimestamps = <String, num>{};
    
    // Get all field names from both nodes
    final allFields = <String>{
      ...current.keys.where((k) => k != '_'),
      ...incoming.keys.where((k) => k != '_'),
    };
    
    // Resolve each field using HAM timestamps
    for (final field in allFields) {
      final currentValue = current[field];
      final incomingValue = incoming[field];
      final currentTime = currentTimestamps[field] ?? 0;
      final incomingTime = incomingTimestamps[field] ?? 0;
      
      if (incomingTime > currentTime) {
        // Incoming value is newer
        mergedData[field] = incomingValue;
        mergedTimestamps[field] = incomingTime;
      } else if (currentTime > incomingTime) {
        // Current value is newer
        if (currentValue != null) {
          mergedData[field] = currentValue;
          mergedTimestamps[field] = currentTime;
        }
      } else {
        // Same timestamp - use deterministic resolution
        // In Gun.js, this uses lexicographic comparison
        final currentStr = currentValue?.toString() ?? '';
        final incomingStr = incomingValue?.toString() ?? '';
        
        if (incomingStr.compareTo(currentStr) > 0) {
          mergedData[field] = incomingValue;
        } else if (currentValue != null) {
          mergedData[field] = currentValue;
        }
        mergedTimestamps[field] = currentTime;
      }
    }
    
    // Create merged node with proper metadata using the merged timestamps
    final metadata = {
      '#': nodeId,
      '>': mergedTimestamps,
      'machine': nextMachineState,
      'machineId': machineId,
    };
    
    final result = Map<String, dynamic>.from(mergedData);
    result['_'] = metadata;
    return result;
  }
  
  /// Generate a unique node ID compatible with Gun.js
  /// 
  /// Creates a node ID that matches Gun.js patterns and uniqueness requirements
  static String generateNodeId([String? basePath]) {
    if (basePath != null && basePath.isNotEmpty) {
      // Use the path as the node ID for path-based nodes
      return basePath;
    }
    
    // Generate a unique ID using timestamp and randomness
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomSuffix = Utils.randomString(6);
    return '$timestamp-$randomSuffix';
  }
  
  /// Update timestamps for modified fields
  /// 
  /// Updates only the fields that have changed, preserving existing timestamps
  /// for unchanged fields
  static Map<String, dynamic> updateTimestamps({
    required Map<String, dynamic> node,
    required Map<String, dynamic> changes,
  }) {
    final metadata = extractMetadata(node);
    if (metadata == null) {
      throw StateError('Cannot update timestamps for node without metadata');
    }
    
    final existingTimestamps = getTimestamps(node) ?? <String, num>{};
    final nodeId = getNodeId(node)!;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // Update timestamps only for changed fields
    final updatedTimestamps = Map<String, num>.from(existingTimestamps);
    for (final field in changes.keys) {
      if (field != '_') {  // Skip metadata field
        updatedTimestamps[field] = now;
      }
    }
    
    // Create updated data
    final updatedData = Map<String, dynamic>.from(node);
    updatedData.addAll(changes);
    
    // Update metadata
    updatedData['_'] = createMetadata(
      nodeId: nodeId,
      data: updatedData,
      existingTimestamps: updatedTimestamps,
    );
    
    return updatedData;
  }
  
  /// Convert node to Gun.js wire format
  /// 
  /// Ensures the node is in proper Gun.js wire format for network transmission
  static Map<String, dynamic> toWireFormat(Map<String, dynamic> node) {
    if (!isValidNode(node)) {
      throw StateError('Cannot convert invalid node to wire format');
    }
    
    // Gun.js wire format is the same as our internal format
    // Just ensure proper structure
    return Map<String, dynamic>.from(node);
  }
  
  /// Create node from Gun.js wire format
  /// 
  /// Parses a node from Gun.js wire format and validates metadata
  static Map<String, dynamic> fromWireFormat(Map<String, dynamic> wireData) {
    // Validate the wire format
    if (!isValidNode(wireData)) {
      throw FormatException('Invalid Gun.js wire format: missing or invalid metadata');
    }
    
    return Map<String, dynamic>.from(wireData);
  }
  
  /// Clean up metadata for a node before deletion
  /// 
  /// Removes metadata references and cleans up related data
  static void cleanupMetadata(String nodeId) {
    // In a full implementation, this would:
    // 1. Remove any references to this node ID
    // 2. Clean up graph connections
    // 3. Notify peers of deletion
    // For now, this is a placeholder
  }
}

/// Metadata validation result
class MetadataValidationResult {
  final bool isValid;
  final List<String> errors;
  
  const MetadataValidationResult({
    required this.isValid,
    this.errors = const [],
  });
  
  MetadataValidationResult.valid() : isValid = true, errors = const [];
  
  MetadataValidationResult.invalid(List<String> errors) 
      : isValid = false, errors = errors;
}

/// Extended metadata validation
class MetadataValidator {
  /// Perform comprehensive validation of node metadata
  static MetadataValidationResult validate(Map<String, dynamic> node) {
    final errors = <String>[];
    
    // Check if metadata exists
    final metadata = MetadataManager.extractMetadata(node);
    if (metadata == null) {
      errors.add('Missing metadata field (_)');
      return MetadataValidationResult.invalid(errors);
    }
    
    // Check node ID
    final nodeId = metadata['#'];
    if (nodeId == null) {
      errors.add('Missing node ID (#)');
    } else if (nodeId is! String || nodeId.isEmpty) {
      errors.add('Invalid node ID: must be non-empty string');
    }
    
    // Check timestamps
    final timestamps = metadata['>'];
    if (timestamps == null) {
      errors.add('Missing HAM timestamps (>)');
    } else if (timestamps is! Map) {
      errors.add('Invalid timestamps: must be a Map');
    } else {
      // Validate timestamp values
      for (final entry in (timestamps as Map<String, dynamic>).entries) {
        if (entry.value is! num) {
          errors.add('Invalid timestamp for field ${entry.key}: must be numeric');
        }
      }
    }
    
    // Check machine state (optional but recommended)
    final machineState = metadata['machine'];
    if (machineState != null && machineState is! num) {
      errors.add('Invalid machine state: must be numeric if present');
    }
    
    // Check machine ID (optional but recommended)
    final machineId = metadata['machineId'];
    if (machineId != null && (machineId is! String || machineId.isEmpty)) {
      errors.add('Invalid machine ID: must be non-empty string if present');
    }
    
    return errors.isEmpty 
        ? MetadataValidationResult.valid()
        : MetadataValidationResult.invalid(errors);
  }
}
