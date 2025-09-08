import '../types/types.dart';
import 'crdt.dart';

/// Enhanced node data structure for Gun Dart
/// Extends the basic GunNode with additional functionality
class GunDataNode extends GunNode {
  /// Vector clock for CRDT synchronization
  final Map<String, int> vectorClock;
  
  /// Version number for this node
  final int version;
  
  const GunDataNode({
    required super.id,
    required super.data,
    super.meta = const {},
    required super.lastModified,
    this.vectorClock = const {},
    this.version = 0,
  });
  
  @override
  GunDataNode copyWith({
    String? id,
    Map<String, dynamic>? data,
    Map<String, dynamic>? meta,
    DateTime? lastModified,
    Map<String, int>? vectorClock,
    int? version,
  }) {
    return GunDataNode(
      id: id ?? this.id,
      data: data ?? Map.from(this.data),
      meta: meta ?? Map.from(this.meta),
      lastModified: lastModified ?? this.lastModified,
      vectorClock: vectorClock ?? Map.from(this.vectorClock),
      version: version ?? this.version + 1,
    );
  }
  
  /// Update this node with new data using CRDT merge
  GunDataNode merge(Map<String, dynamic> newData, [Map<String, int>? newClock]) {
    final mergedData = CRDT.mergeNodes(data, newData);
    final mergedClock = Map<String, int>.from(vectorClock);
    
    if (newClock != null) {
      for (final entry in newClock.entries) {
        final existing = mergedClock[entry.key] ?? 0;
        if (entry.value > existing) {
          mergedClock[entry.key] = entry.value;
        }
      }
    }
    
    return copyWith(
      data: mergedData,
      vectorClock: mergedClock,
      lastModified: DateTime.now(),
    );
  }
  
  /// Get the value of a specific property
  dynamic getValue(String key) => data[key];
  
  /// Set the value of a specific property
  GunDataNode setValue(String key, dynamic value, [int? timestamp]) {
    final newData = Map<String, dynamic>.from(data);
    newData[key] = value;
    
    final newClock = Map<String, int>.from(vectorClock);
    newClock[key] = timestamp ?? CRDT.generateTimestamp();
    
    return copyWith(
      data: newData,
      vectorClock: newClock,
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
  
  /// Check if this node is newer than another based on vector clocks
  bool isNewerThan(GunDataNode other) {
    return CRDT.isNewer(vectorClock, other.vectorClock);
  }
  
  /// Convert to Gun wire format for network transmission
  Map<String, dynamic> toWireFormat() {
    final result = Map<String, dynamic>.from(data);
    result['_'] = {
      '#': id,
      '>': vectorClock,
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
    final vectorClock = meta['>'] as Map<String, int>? ?? {};
    final version = meta['version'] as int? ?? 0;
    final modifiedStr = meta['modified'] as String?;
    
    final data = Map<String, dynamic>.from(wireData);
    data.remove('_');
    
    return GunDataNode(
      id: id,
      data: data,
      meta: Map<String, dynamic>.from(meta)..removeWhere((k, v) => 
          ['#', '>', 'version', 'modified'].contains(k)),
      lastModified: modifiedStr != null 
          ? DateTime.parse(modifiedStr) 
          : DateTime.now(),
      vectorClock: vectorClock,
      version: version,
    );
  }
  
  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'vectorClock': vectorClock,
      'version': version,
    };
  }
  
  /// Create from JSON with vector clock support
  factory GunDataNode.fromJson(Map<String, dynamic> json) {
    return GunDataNode(
      id: json['id'] as String,
      data: json['data'] as Map<String, dynamic>,
      meta: json['meta'] as Map<String, dynamic>? ?? {},
      lastModified: DateTime.parse(json['lastModified'] as String),
      vectorClock: Map<String, int>.from(json['vectorClock'] as Map? ?? {}),
      version: json['version'] as int? ?? 0,
    );
  }
}
