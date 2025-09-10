import 'dart:async';
import '../utils/utils.dart';

/// Represents a Gun.js compatible graph query
/// 
/// Gun.js queries follow these patterns:
/// 
/// Simple node query:
/// {
///   "get": {
///     "#": "users/alice"
///   },
///   "@": "query-id-123"
/// }
/// 
/// Graph traversal query:
/// {
///   "get": {
///     "#": "users",
///     ".": {
///       "#": "alice"
///     }
///   },
///   "@": "query-id-456"
/// }
/// 
/// Multi-level traversal:
/// {
///   "get": {
///     "#": "users",
///     ".": {
///       "#": "alice",
///       ".": {
///         "#": "profile"
///       }
///     }
///   },
///   "@": "query-id-789"
/// }
class GunQuery {
  /// The root node ID to query
  final String nodeId;
  
  /// Path segments for graph traversal
  final List<String> path;
  
  /// Query identifier for tracking responses
  final String queryId;
  
  /// Optional callback for query results
  final Function? callback;
  
  /// Timestamp when query was created
  final DateTime timestamp;
  
  /// Optional filter function for result filtering
  final Function? filterFn;
  
  /// Optional map function for result transformation
  final Function? mapFn;
  
  GunQuery({
    required this.nodeId,
    this.path = const [],
    String? queryId,
    this.callback,
    this.filterFn,
    this.mapFn,
  }) : queryId = queryId ?? Utils.randomString(8),
       timestamp = DateTime.now();
  
  /// Create a simple node query
  factory GunQuery.node(String nodeId, {String? queryId, Function? callback}) {
    return GunQuery(
      nodeId: nodeId,
      path: [],
      queryId: queryId,
      callback: callback,
    );
  }
  
  /// Create a graph traversal query
  factory GunQuery.traverse(String rootNode, List<String> path, {String? queryId, Function? callback}) {
    return GunQuery(
      nodeId: rootNode,
      path: path,
      queryId: queryId,
      callback: callback,
    );
  }
  
  /// Create a query with filter function
  GunQuery filter(Function filterFunction) {
    return GunQuery(
      nodeId: nodeId,
      path: path,
      queryId: Utils.randomString(8), // New query ID for filtered query
      callback: callback,
      filterFn: filterFunction,
      mapFn: mapFn,
    );
  }
  
  /// Create a query with map function
  GunQuery map(Function mapFunction) {
    return GunQuery(
      nodeId: nodeId,
      path: path,
      queryId: Utils.randomString(8), // New query ID for mapped query
      callback: callback,
      filterFn: filterFn,
      mapFn: mapFunction,
    );
  }
  
  /// Convert to Gun.js wire format
  Map<String, dynamic> toWireFormat() {
    final query = <String, dynamic>{};
    
    if (path.isEmpty) {
      // Simple node query
      query['get'] = {
        '#': nodeId,
      };
    } else {
      // Graph traversal query
      query['get'] = _buildTraversalQuery(nodeId, path);
    }
    
    // Add query ID for tracking
    query['@'] = queryId;
    
    return query;
  }
  
  /// Build nested traversal query structure
  Map<String, dynamic> _buildTraversalQuery(String currentNode, List<String> remainingPath) {
    final result = <String, dynamic>{
      '#': currentNode,
    };
    
    if (remainingPath.isNotEmpty) {
      final nextNode = remainingPath.first;
      final restPath = remainingPath.skip(1).toList();
      
      result['.'] = _buildTraversalQuery(nextNode, restPath);
    }
    
    return result;
  }
  
  /// Parse Gun.js wire format into GunQuery
  static GunQuery fromWireFormat(Map<String, dynamic> wireData) {
    final queryId = wireData['@'] as String? ?? Utils.randomString(8);
    final getQueryRaw = wireData['get'];
    
    if (getQueryRaw == null) {
      throw ArgumentError('Invalid query format: missing get field');
    }
    
    Map<String, dynamic> getQuery;
    if (getQueryRaw is Map<String, dynamic>) {
      getQuery = getQueryRaw;
    } else if (getQueryRaw is Map) {
      getQuery = Map<String, dynamic>.from(getQueryRaw);
    } else {
      throw ArgumentError('Invalid query format: get field is not a map');
    }
    
    final nodeId = getQuery['#'] as String?;
    if (nodeId == null) {
      throw ArgumentError('Invalid query format: missing node ID');
    }
    
    final path = _extractPath(getQuery);
    
    return GunQuery(
      nodeId: nodeId,
      path: path,
      queryId: queryId,
    );
  }
  
  /// Extract path from nested query structure
  static List<String> _extractPath(Map<String, dynamic> queryData) {
    final path = <String>[];
    var current = queryData;
    
    while (current.containsKey('.')) {
      final nextLevelRaw = current['.'];
      
      Map<String, dynamic> nextLevel;
      if (nextLevelRaw is Map<String, dynamic>) {
        nextLevel = nextLevelRaw;
      } else if (nextLevelRaw is Map) {
        nextLevel = Map<String, dynamic>.from(nextLevelRaw);
      } else {
        break; // Invalid structure, stop parsing
      }
      
      final nodeId = nextLevel['#'] as String?;
      
      if (nodeId != null) {
        path.add(nodeId);
      }
      
      current = nextLevel;
    }
    
    return path;
  }
  
  /// Get the full path including root node
  List<String> get fullPath => [nodeId, ...path];
  
  /// Get the target node ID (last in path)
  String get targetNodeId => path.isEmpty ? nodeId : path.last;
  
  /// Check if this is a simple node query (no traversal)
  bool get isSimple => path.isEmpty;
  
  /// Check if this is a graph traversal query
  bool get isTraversal => path.isNotEmpty;
  
  /// Create a copy with additional path segment
  GunQuery extend(String segment) {
    return GunQuery(
      nodeId: nodeId,
      path: [...path, segment],
      queryId: Utils.randomString(8), // New query ID for extended query
      callback: callback,
      filterFn: filterFn,
      mapFn: mapFn,
    );
  }
  
  @override
  String toString() {
    if (isSimple) {
      return 'GunQuery(node: $nodeId)';
    } else {
      return 'GunQuery(root: $nodeId, path: ${path.join('.')})';
    }
  }
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GunQuery &&
        other.nodeId == nodeId &&
        _listEquals(other.path, path) &&
        other.queryId == queryId;
  }
  
  @override
  int get hashCode {
    return Object.hash(nodeId, path.join('.'), queryId);
  }
  
  /// Deep equality check for lists
  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Query result containing the response data and metadata
class GunQueryResult {
  /// The original query that generated this result
  final GunQuery query;
  
  /// The response data
  final Map<String, dynamic>? data;
  
  /// Error message if query failed
  final String? error;
  
  /// Response timestamp
  final DateTime timestamp;
  
  /// Peer that provided the response
  final String? peerId;
  
  GunQueryResult({
    required this.query,
    this.data,
    this.error,
    String? peerId,
  }) : timestamp = DateTime.now(),
       peerId = peerId;
  
  /// Check if the query was successful
  bool get isSuccess => error == null; // In Gun.js, null data is a valid success response
  
  /// Check if the query failed
  bool get isError => error != null;
  
  /// Apply filter function to the result data
  GunQueryResult filter() {
    if (!isSuccess || data == null || query.filterFn == null) {
      return this;
    }
    
    try {
      final filteredData = <String, dynamic>{};
      data!.forEach((key, value) {
        // Apply filter function to each key-value pair
        if (query.filterFn!(value, key)) {
          filteredData[key] = value;
        }
      });
      return GunQueryResult(
        query: query,
        data: filteredData,
        peerId: peerId,
      );
    } catch (e) {
      return GunQueryResult(
        query: query,
        error: 'Filter function error: $e',
        peerId: peerId,
      );
    }
  }
  
  /// Apply map function to the result data
  GunQueryResult map() {
    if (!isSuccess || data == null || query.mapFn == null) {
      return this;
    }
    
    try {
      final mappedData = <String, dynamic>{};
      data!.forEach((key, value) {
        // Apply map function to each key-value pair
        final mappedValue = query.mapFn!(value, key);
        mappedData[key] = mappedValue;
      });
      return GunQueryResult(
        query: query,
        data: mappedData,
        peerId: peerId,
      );
    } catch (e) {
      return GunQueryResult(
        query: query,
        error: 'Map function error: $e',
        peerId: peerId,
      );
    }
  }
  
  /// Apply both filter and map functions if they exist
  GunQueryResult applyEnhancements() {
    var result = this;
    
    // Apply filter first, then map (if both exist)
    if (query.filterFn != null) {
      result = result.filter();
    }
    
    if (query.mapFn != null) {
      result = result.map();
    }
    
    return result;
  }
  
  @override
  String toString() {
    if (isSuccess) {
      return 'GunQueryResult(success, data: ${data?.keys.length} fields)';
    } else {
      return 'GunQueryResult(error: $error)';
    }
  }
}

/// Query manager for handling multiple concurrent queries
class GunQueryManager {
  final Map<String, GunQuery> _activeQueries = {};
  final Map<String, Timer> _queryTimeouts = {};
  final Duration _defaultTimeout = const Duration(seconds: 30);
  
  /// Track a new query
  void trackQuery(GunQuery query, {Duration? timeout}) {
    _activeQueries[query.queryId] = query;
    
    // Set up timeout
    final timeoutDuration = timeout ?? _defaultTimeout;
    _queryTimeouts[query.queryId] = Timer(timeoutDuration, () {
      _handleQueryTimeout(query.queryId);
    });
  }
  
  /// Handle query result
  void handleResult(String queryId, GunQueryResult result) {
    final query = _activeQueries[queryId];
    if (query == null) return;
    
    // Cancel timeout
    _queryTimeouts[queryId]?.cancel();
    _queryTimeouts.remove(queryId);
    
    // Remove from active queries
    _activeQueries.remove(queryId);
    
    // Execute callback if provided
    if (query.callback != null) {
      try {
        if (result.isSuccess) {
          query.callback!(result.data, null);
        } else {
          query.callback!(null, result.error);
        }
      } catch (e) {
        // Ignore callback errors
      }
    }
  }
  
  /// Handle query timeout
  void _handleQueryTimeout(String queryId) {
    final query = _activeQueries[queryId];
    if (query == null) return;
    
    _activeQueries.remove(queryId);
    _queryTimeouts.remove(queryId);
    
    // Execute callback with timeout error
    if (query.callback != null) {
      try {
        query.callback!(null, 'Query timeout after ${_defaultTimeout.inSeconds}s');
      } catch (e) {
        // Ignore callback errors
      }
    }
  }
  
  /// Get active query by ID
  GunQuery? getQuery(String queryId) => _activeQueries[queryId];
  
  /// Get all active queries
  List<GunQuery> get activeQueries => _activeQueries.values.toList();
  
  /// Clear all queries
  void clear() {
    for (final timer in _queryTimeouts.values) {
      timer.cancel();
    }
    _queryTimeouts.clear();
    _activeQueries.clear();
  }
  
  /// Get query statistics
  Map<String, dynamic> getStats() {
    return {
      'activeQueries': _activeQueries.length,
      'activeTimeouts': _queryTimeouts.length,
    };
  }
}
