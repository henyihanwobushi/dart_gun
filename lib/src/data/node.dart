import '../types/types.dart';
import 'ham_state.dart';

/// Enhanced node data structure for Gun Dart
/// Extends the basic GunNode with HAM state for Gun.js compatibility
class GunDataNode extends GunNode {
  /// HAM state for conflict resolution (Gun.js compatible)
  final HAMState hamState;
  
  /// Version number for this node
  final int version;
  
  const GunDataNode({
    required super.id,
    required super.data,
    super.meta = const {},
    required super.lastModified,
    required this.hamState,
    this.version = 0,
  });
  
  /// Create a new GunDataNode with auto-generated HAM state
  factory GunDataNode.create({
    required String id,
    required Map<String, dynamic> data,
    Map<String, dynamic> meta = const {},
    DateTime? lastModified,
    String? machineId,
    int version = 0,
  }) {
    final ham = HAMState.create(id, machineId);
    
    // Update HAM state for all initial data fields
    final initialHam = data.keys.isEmpty 
        ? ham 
        : ham.updateFields(data.keys.toList());
    
    return GunDataNode(
      id: id,
      data: data,
      meta: meta,
      lastModified: lastModified ?? DateTime.now(),
      hamState: initialHam,
      version: version,
    );
  }
  
  @override
  GunDataNode copyWith({
    String? id,
    Map<String, dynamic>? data,
    Map<String, dynamic>? meta,
    DateTime? lastModified,
    HAMState? hamState,
    int? version,
  }) {
    return GunDataNode(
      id: id ?? this.id,
      data: data ?? Map.from(this.data),
      meta: meta ?? Map.from(this.meta),
      lastModified: lastModified ?? this.lastModified,
      hamState: hamState ?? this.hamState,
      version: version ?? this.version + 1,
    );
  }
  
  /// Update this node with new data using HAM conflict resolution
  GunDataNode merge(Map<String, dynamic> newData, HAMState newHAM) {
    final mergedData = <String, dynamic>{};
    
    // Merge existing data with new data using HAM resolution
    final allFields = {...data.keys, ...newData.keys};
    
    for (final field in allFields) {
      final currentValue = data[field];
      final newValue = newData[field];
      
      if (currentValue == null) {
        // New field, use incoming value
        mergedData[field] = newValue;
      } else if (newValue == null) {
        // Field deleted in incoming, check HAM timestamps
        if (newHAM.hasField(field) && newHAM.isFieldNewer(field, hamState)) {
          // Delete field if incoming HAM is newer
          continue;
        } else {
          // Keep current value if current HAM is newer or equal
          mergedData[field] = currentValue;
        }
      } else {
        // Both have values, resolve using HAM
        final resolved = HAMState.resolveConflict(
          field,
          currentValue,
          newValue,
          hamState,
          newHAM,
        );
        mergedData[field] = resolved.value;
      }
    }
    
    return copyWith(
      data: mergedData,
      hamState: hamState.merge(newHAM),
      lastModified: DateTime.now(),
    );
  }
  
  /// Get the value of a specific property
  dynamic getValue(String key) => data[key];
  
  /// Set the value of a specific property
  GunDataNode setValue(String key, dynamic value, [num? timestamp]) {
    final newData = Map<String, dynamic>.from(data);
    newData[key] = value;
    
    final newHAM = hamState.updateField(key, timestamp);
    
    return copyWith(
      data: newData,
      hamState: newHAM,
    );
  }
  
  /// Remove a property from this node
  GunDataNode removeValue(String key) {
    final newData = Map<String, dynamic>.from(data);
    newData.remove(key);
    
    return copyWith(data: newData);
  }
  
  /// Check if this node has a specific property
  bool hasValue(String key) => data.containsKey(key);
  
  /// Get all property keys
  List<String> get keys => data.keys.toList();
  
  /// Check if this node contains links to other nodes
  bool get hasLinks {
    return data.values.any((value) => 
        value is Map && value.containsKey('#'));
  }
  
  /// Get all links from this node
  List<GunLink> getLinks() {
    final links = <GunLink>[];
    for (final entry in data.entries) {
      if (entry.value is Map && (entry.value as Map).containsKey('#')) {
        final linkMap = entry.value as Map<String, dynamic>;
        links.add(GunLink(
          reference: linkMap['#'] as String,
          meta: Map<String, dynamic>.from(linkMap)..remove('#'),
        ));
      }
    }
    return links;
  }
  
  /// Create a link to another node
  GunDataNode createLink(String property, String targetId, [Map<String, dynamic>? linkMeta]) {
    final linkData = <String, dynamic>{'#': targetId};
    if (linkMeta != null) {
      linkData.addAll(linkMeta);
    }
    
    return setValue(property, linkData);
  }
  
  /// Check if this node has newer fields than another based on HAM state
  bool hasNewerFields(GunDataNode other) {
    return hamState.hasNewerFields(other.hamState);
  }
  
  /// Convert to Gun wire format for network transmission
  Map<String, dynamic> toWireFormat() {
    final result = Map<String, dynamic>.from(data);
    final hamMeta = hamState.toWireFormat();
    
    result['_'] = {
      ...hamMeta,
      'version': version,
      'modified': lastModified.toIso8601String(),
    };
    
    if (meta.isNotEmpty) {
      result['_'].addAll(meta);
    }
    
    return result;
  }
  
  /// Create from Gun wire format
  factory GunDataNode.fromWireFormat(Map<String, dynamic> wireData) {
    final meta = wireData['_'] as Map<String, dynamic>? ?? {};
    final id = meta['#'] as String? ?? '';
    final version = meta['version'] as int? ?? 0;
    final modifiedStr = meta['modified'] as String?;
    
    // Create HAM state from wire format
    final hamState = HAMState.fromWireFormat(wireData);
    
    final data = Map<String, dynamic>.from(wireData);
    data.remove('_');
    
    return GunDataNode(
      id: id,
      data: data,
      meta: Map<String, dynamic>.from(meta)..removeWhere((k, v) => 
          ['#', '>', 'version', 'modified', 'machine', 'machineId'].contains(k)),
      lastModified: modifiedStr != null 
          ? DateTime.parse(modifiedStr) 
          : DateTime.now(),
      hamState: hamState,
      version: version,
    );
  }
  
  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'hamState': hamState.toWireFormat(),
      'version': version,
    };
  }
  
  /// Create from JSON with HAM state support
  factory GunDataNode.fromJson(Map<String, dynamic> json) {
    // Create a wire format structure for HAM parsing
    final hamData = json['hamState'] as Map<String, dynamic>? ?? {};
    final wireData = {
      '_': hamData,
      ...json['data'] as Map<String, dynamic>? ?? {},
    };
    
    final hamState = HAMState.fromWireFormat(wireData);
    
    return GunDataNode(
      id: json['id'] as String,
      data: json['data'] as Map<String, dynamic>,
      meta: json['meta'] as Map<String, dynamic>? ?? {},
      lastModified: DateTime.parse(json['lastModified'] as String),
      hamState: hamState,
      version: json['version'] as int? ?? 0,
    );
  }
}
