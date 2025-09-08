import 'dart:async';
import 'types/types.dart';
import 'data/node.dart';
import 'data/crdt.dart';

/// Gun node implementation with full Gun.js-like functionality
/// This represents an individual node in the Gun graph database
class GunNodeImpl {
  final String _id;
  final Map<String, dynamic> _data;
  final Map<String, int> _vectorClock;
  final StreamController<NodeEvent> _eventController = StreamController.broadcast();
  
  GunNodeImpl(this._id, [Map<String, dynamic>? initialData]) 
      : _data = Map.from(initialData ?? {}),
        _vectorClock = {};
  
  /// Get the node ID
  String get id => _id;
  
  /// Get a copy of the current data
  Map<String, dynamic> get data => Map.unmodifiable(_data);
  
  /// Get the vector clock
  Map<String, int> get vectorClock => Map.unmodifiable(_vectorClock);
  
  /// Get a specific property value
  dynamic getValue(String key) => _data[key];
  
  /// Set a property value with CRDT semantics
  void setValue(String key, dynamic value, [int? timestamp]) {
    final ts = timestamp ?? CRDT.generateTimestamp();
    final currentTs = _vectorClock[key] ?? 0;
    
    // Only update if timestamp is newer
    if (ts >= currentTs) {
      final oldValue = _data[key];
      _data[key] = value;
      _vectorClock[key] = ts;
      
      // Emit change event
      _eventController.add(NodeEvent(
        type: NodeEventType.valueChanged,
        key: key,
        oldValue: oldValue,
        newValue: value,
        timestamp: ts,
      ));
    }
  }
  
  /// Remove a property
  void removeValue(String key) {
    if (_data.containsKey(key)) {
      final oldValue = _data.remove(key);
      _vectorClock.remove(key);
      
      _eventController.add(NodeEvent(
        type: NodeEventType.valueRemoved,
        key: key,
        oldValue: oldValue,
        timestamp: CRDT.generateTimestamp(),
      ));
    }
  }
  
  /// Check if the node has a property
  bool hasValue(String key) => _data.containsKey(key);
  
  /// Get all property keys
  List<String> get keys => _data.keys.toList();
  
  /// Merge data from another node using CRDT
  void merge(Map<String, dynamic> incomingData, [Map<String, int>? incomingClock]) {
    incomingClock ??= {};
    
    for (final entry in incomingData.entries) {
      final key = entry.key;
      final incomingValue = entry.value;
      final incomingTs = incomingClock[key] ?? CRDT.generateTimestamp();
      final currentTs = _vectorClock[key] ?? 0;
      
      if (incomingTs > currentTs) {
        setValue(key, incomingValue, incomingTs);
      } else if (incomingTs == currentTs && _data[key] != incomingValue) {
        // Tie-breaking using deterministic comparison
        final resolved = CRDT.resolve(_data[key], incomingValue);
        if (resolved != _data[key]) {
          setValue(key, resolved, incomingTs);
        }
      }
    }
  }
  
  /// Create a link to another node
  void createLink(String property, String targetId, [Map<String, dynamic>? metadata]) {
    final linkData = <String, dynamic>{'#': targetId};
    if (metadata != null) {
      linkData.addAll(metadata);
    }
    setValue(property, linkData);
  }
  
  /// Get all outgoing links
  List<GunLink> getLinks() {
    final links = <GunLink>[];
    for (final entry in _data.entries) {
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
  
  /// Check if this node has any links
  bool get hasLinks => getLinks().isNotEmpty;
  
  /// Convert to GunDataNode
  GunDataNode toGunDataNode() {
    return GunDataNode(
      id: _id,
      data: Map.from(_data),
      lastModified: DateTime.now(),
      vectorClock: Map.from(_vectorClock),
    );
  }
  
  /// Update from GunDataNode
  void fromGunDataNode(GunDataNode node) {
    merge(node.data, node.vectorClock);
  }
  
  /// Convert to wire format for network transmission
  Map<String, dynamic> toWireFormat() {
    final result = Map<String, dynamic>.from(_data);
    result['_'] = {
      '#': _id,
      '>': _vectorClock,
    };
    return result;
  }
  
  /// Update from wire format
  void fromWireFormat(Map<String, dynamic> wireData) {
    final meta = wireData['_'] as Map<String, dynamic>? ?? {};
    final incomingClock = meta['>'] as Map<String, int>? ?? {};
    
    final data = Map<String, dynamic>.from(wireData);
    data.remove('_');
    
    merge(data, incomingClock);
  }
  
  /// Subscribe to node changes
  StreamSubscription<NodeEvent> on(void Function(NodeEvent) listener) {
    return _eventController.stream.listen(listener);
  }
  
  /// Get the event stream
  Stream<NodeEvent> get events => _eventController.stream;
  
  /// Check if this node is empty
  bool get isEmpty => _data.isEmpty;
  
  /// Check if this node is newer than another based on vector clocks
  bool isNewerThan(GunNodeImpl other) {
    return CRDT.isNewer(_vectorClock, other._vectorClock);
  }
  
  /// Clear all data from the node
  void clear() {
    final oldData = Map.from(_data);
    _data.clear();
    _vectorClock.clear();
    
    _eventController.add(NodeEvent(
      type: NodeEventType.nodeCleared,
      key: '',
      oldValue: oldData,
      timestamp: CRDT.generateTimestamp(),
    ));
  }
  
  /// Dispose the node and clean up resources
  void dispose() {
    _eventController.close();
    _data.clear();
    _vectorClock.clear();
  }
  
  @override
  String toString() {
    return 'GunNodeImpl(id: $_id, data: $_data)';
  }
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GunNodeImpl && other._id == _id;
  }
  
  @override
  int get hashCode => _id.hashCode;
}

/// Types of events that can occur on a node
enum NodeEventType {
  valueChanged,
  valueRemoved,
  nodeCleared,
}

/// Event emitted when a node changes
class NodeEvent {
  final NodeEventType type;
  final String key;
  final dynamic oldValue;
  final dynamic newValue;
  final int timestamp;
  
  const NodeEvent({
    required this.type,
    required this.key,
    this.oldValue,
    this.newValue,
    required this.timestamp,
  });
  
  @override
  String toString() {
    return 'NodeEvent(type: $type, key: $key, oldValue: $oldValue, newValue: $newValue)';
  }
}
