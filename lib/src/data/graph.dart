import 'dart:async';
import '../types/types.dart';
import 'crdt.dart';

/// Graph data structure implementation for Gun Dart
/// Maintains the distributed graph of nodes and their relationships
class Graph {
  final Map<String, GunNode> _nodes = {};
  final StreamController<GraphEvent> _eventController = StreamController.broadcast();
  
  /// Get a node by its ID
  GunNode? getNode(String id) {
    return _nodes[id];
  }
  
  /// Add or update a node in the graph
  void putNode(String id, Map<String, dynamic> data, [Map<String, int>? state]) {
    final now = DateTime.now();
    final existingNode = _nodes[id];
    
    if (existingNode != null) {
      // Merge with existing node using CRDT
      final mergedData = CRDT.mergeNodes(existingNode.data, data);
      _nodes[id] = existingNode.copyWith(
        data: mergedData,
        lastModified: now,
      );
    } else {
      // Create new node
      _nodes[id] = GunNode(
        id: id,
        data: Map.from(data),
        lastModified: now,
      );
    }
    
    // Emit graph event
    _eventController.add(GraphEvent(
      type: GraphEventType.nodeUpdated,
      nodeId: id,
      data: _nodes[id]!.data,
    ));
  }
  
  /// Remove a node from the graph
  void removeNode(String id) {
    final removed = _nodes.remove(id);
    if (removed != null) {
      _eventController.add(GraphEvent(
        type: GraphEventType.nodeRemoved,
        nodeId: id,
      ));
    }
  }
  
  /// Get all nodes
  Map<String, GunNode> get nodes => Map.unmodifiable(_nodes);
  
  /// Check if a node exists
  bool hasNode(String id) => _nodes.containsKey(id);
  
  /// Get all node IDs
  List<String> get nodeIds => _nodes.keys.toList();
  
  /// Find nodes by a predicate function
  List<GunNode> findNodes(bool Function(GunNode) predicate) {
    return _nodes.values.where(predicate).toList();
  }
  
  /// Get edges from a node (links to other nodes)
  List<String> getEdges(String nodeId) {
    final node = _nodes[nodeId];
    if (node == null) return [];
    
    final edges = <String>[];
    for (final value in node.data.values) {
      if (value is Map && value.containsKey('#')) {
        edges.add(value['#'] as String);
      }
    }
    return edges;
  }
  
  /// Create a link between two nodes
  void createLink(String fromId, String toId, String property) {
    final fromNode = _nodes[fromId];
    if (fromNode != null) {
      final newData = Map<String, dynamic>.from(fromNode.data);
      newData[property] = {'#': toId};
      putNode(fromId, newData);
    }
  }
  
  /// Remove a link between nodes
  void removeLink(String fromId, String property) {
    final fromNode = _nodes[fromId];
    if (fromNode != null) {
      final newData = Map<String, dynamic>.from(fromNode.data);
      newData.remove(property);
      putNode(fromId, newData);
    }
  }
  
  /// Traverse the graph starting from a node
  List<String> traverse(String startId, {int maxDepth = 10}) {
    final visited = <String>{};
    final toVisit = <String>[startId];
    final result = <String>[];
    var depth = 0;
    
    while (toVisit.isNotEmpty && depth < maxDepth) {
      final current = toVisit.removeAt(0);
      if (visited.contains(current)) continue;
      
      visited.add(current);
      result.add(current);
      
      final edges = getEdges(current);
      toVisit.addAll(edges.where((id) => !visited.contains(id)));
      depth++;
    }
    
    return result;
  }
  
  /// Get the event stream for graph changes
  Stream<GraphEvent> get events => _eventController.stream;
  
  /// Clear all nodes from the graph
  void clear() {
    _nodes.clear();
    _eventController.add(GraphEvent(
      type: GraphEventType.graphCleared,
      nodeId: '',
    ));
  }
  
  /// Get graph statistics
  GraphStats getStats() {
    return GraphStats(
      nodeCount: _nodes.length,
      totalEdges: _nodes.values.fold(0, (sum, node) => sum + getEdges(node.id).length),
    );
  }
  
  /// Dispose the graph and clean up resources
  void dispose() {
    _eventController.close();
    _nodes.clear();
  }
}

/// Types of events that can occur in the graph
enum GraphEventType {
  nodeUpdated,
  nodeRemoved,
  graphCleared,
}

/// Event emitted when the graph changes
class GraphEvent {
  final GraphEventType type;
  final String nodeId;
  final Map<String, dynamic>? data;
  final DateTime timestamp;
  
  GraphEvent({
    required this.type,
    required this.nodeId,
    this.data,
  }) : timestamp = DateTime.now();
}

/// Statistics about the graph
class GraphStats {
  final int nodeCount;
  final int totalEdges;
  
  const GraphStats({
    required this.nodeCount,
    required this.totalEdges,
  });
  
  @override
  String toString() {
    return 'GraphStats(nodes: $nodeCount, edges: $totalEdges)';
  }
}
