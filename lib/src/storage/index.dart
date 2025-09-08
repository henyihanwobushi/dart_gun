import 'dart:async';
import 'dart:collection';

/// Data indexing system for Gun Dart
/// 
/// Provides efficient indexing and querying capabilities for large datasets.
/// Supports various index types for different query patterns.
abstract class DataIndex {
  /// Index name
  String get name;
  
  /// Add a key-value pair to the index
  void add(String key, dynamic value);
  
  /// Remove a key from the index
  void remove(String key);
  
  /// Update an existing key with new value
  void update(String key, dynamic oldValue, dynamic newValue);
  
  /// Query the index
  List<String> query(IndexQuery query);
  
  /// Clear all index data
  void clear();
  
  /// Get index statistics
  IndexStats getStats();
}

/// Simple hash index for exact matches
class HashIndex implements DataIndex {
  @override
  final String name;
  
  final Map<dynamic, Set<String>> _index = {};
  
  HashIndex(this.name);
  
  @override
  void add(String key, dynamic value) {
    _index.putIfAbsent(value, () => <String>{}).add(key);
  }
  
  @override
  void remove(String key) {
    _index.values.forEach((keys) => keys.remove(key));
    // Remove empty sets
    _index.removeWhere((value, keys) => keys.isEmpty);
  }
  
  @override
  void update(String key, dynamic oldValue, dynamic newValue) {
    if (oldValue != null) {
      _index[oldValue]?.remove(key);
      if (_index[oldValue]?.isEmpty == true) {
        _index.remove(oldValue);
      }
    }
    if (newValue != null) {
      add(key, newValue);
    }
  }
  
  @override
  List<String> query(IndexQuery query) {
    if (query is EqualityQuery) {
      return _index[query.value]?.toList() ?? [];
    }
    if (query is InQuery) {
      final result = <String>{};
      for (final value in query.values) {
        result.addAll(_index[value] ?? <String>{});
      }
      return result.toList();
    }
    return [];
  }
  
  @override
  void clear() {
    _index.clear();
  }
  
  @override
  IndexStats getStats() {
    return IndexStats(
      name: name,
      type: 'hash',
      keyCount: _index.values.fold<int>(0, (sum, keys) => sum + keys.length),
      memoryUsage: _estimateMemoryUsage(),
    );
  }
  
  int _estimateMemoryUsage() {
    // Rough estimation in bytes
    return _index.length * 50 + 
           _index.values.fold<int>(0, (sum, keys) => sum + keys.length * 20);
  }
}

/// Range index for numeric comparisons
class RangeIndex implements DataIndex {
  @override
  final String name;
  
  final SplayTreeMap<num, Set<String>> _index = SplayTreeMap<num, Set<String>>();
  
  RangeIndex(this.name);
  
  @override
  void add(String key, dynamic value) {
    if (value is num) {
      _index.putIfAbsent(value, () => <String>{}).add(key);
    }
  }
  
  @override
  void remove(String key) {
    _index.values.forEach((keys) => keys.remove(key));
    // Remove empty sets
    _index.removeWhere((value, keys) => keys.isEmpty);
  }
  
  @override
  void update(String key, dynamic oldValue, dynamic newValue) {
    if (oldValue is num) {
      _index[oldValue]?.remove(key);
      if (_index[oldValue]?.isEmpty == true) {
        _index.remove(oldValue);
      }
    }
    if (newValue is num) {
      add(key, newValue);
    }
  }
  
  @override
  List<String> query(IndexQuery query) {
    if (query is EqualityQuery && query.value is num) {
      return _index[query.value]?.toList() ?? [];
    }
    if (query is RangeQuery) {
      final result = <String>{};
      for (final entry in _index.entries) {
        if (entry.key >= query.min && entry.key <= query.max) {
          result.addAll(entry.value);
        }
      }
      return result.toList();
    }
    if (query is ComparisonQuery && query.value is num) {
      final result = <String>{};
      switch (query.operator) {
        case ComparisonOperator.lessThan:
          for (final entry in _index.entries) {
            if (entry.key < query.value) {
              result.addAll(entry.value);
            }
          }
          break;
        case ComparisonOperator.lessThanOrEqual:
          for (final entry in _index.entries) {
            if (entry.key <= query.value) {
              result.addAll(entry.value);
            }
          }
          break;
        case ComparisonOperator.greaterThan:
          for (final entry in _index.entries) {
            if (entry.key > query.value) {
              result.addAll(entry.value);
            }
          }
          break;
        case ComparisonOperator.greaterThanOrEqual:
          for (final entry in _index.entries) {
            if (entry.key >= query.value) {
              result.addAll(entry.value);
            }
          }
          break;
      }
      return result.toList();
    }
    return [];
  }
  
  @override
  void clear() {
    _index.clear();
  }
  
  @override
  IndexStats getStats() {
    return IndexStats(
      name: name,
      type: 'range',
      keyCount: _index.values.fold<int>(0, (sum, keys) => sum + keys.length),
      memoryUsage: _estimateMemoryUsage(),
    );
  }
  
  int _estimateMemoryUsage() {
    return _index.length * 60 + 
           _index.values.fold<int>(0, (sum, keys) => sum + keys.length * 20);
  }
}

/// Text index for substring and pattern matching
class TextIndex implements DataIndex {
  @override
  final String name;
  
  final Map<String, Set<String>> _wordIndex = {};
  final Map<String, Set<String>> _prefixIndex = {};
  
  TextIndex(this.name);
  
  @override
  void add(String key, dynamic value) {
    if (value is String) {
      // Index words
      final words = _extractWords(value);
      for (final word in words) {
        _wordIndex.putIfAbsent(word.toLowerCase(), () => <String>{}).add(key);
      }
      
      // Index prefixes
      for (final word in words) {
        final lowerWord = word.toLowerCase();
        for (int i = 1; i <= lowerWord.length; i++) {
          final prefix = lowerWord.substring(0, i);
          _prefixIndex.putIfAbsent(prefix, () => <String>{}).add(key);
        }
      }
    }
  }
  
  @override
  void remove(String key) {
    _wordIndex.values.forEach((keys) => keys.remove(key));
    _wordIndex.removeWhere((word, keys) => keys.isEmpty);
    
    _prefixIndex.values.forEach((keys) => keys.remove(key));
    _prefixIndex.removeWhere((prefix, keys) => keys.isEmpty);
  }
  
  @override
  void update(String key, dynamic oldValue, dynamic newValue) {
    if (oldValue is String) {
      remove(key); // Remove old indexing
    }
    if (newValue is String) {
      add(key, newValue); // Add new indexing
    }
  }
  
  @override
  List<String> query(IndexQuery query) {
    if (query is TextQuery) {
      switch (query.type) {
        case TextQueryType.exact:
          return _wordIndex[query.text.toLowerCase()]?.toList() ?? [];
        case TextQueryType.prefix:
          return _prefixIndex[query.text.toLowerCase()]?.toList() ?? [];
        case TextQueryType.contains:
          final result = <String>{};
          final searchTerm = query.text.toLowerCase();
          for (final entry in _wordIndex.entries) {
            if (entry.key.contains(searchTerm)) {
              result.addAll(entry.value);
            }
          }
          return result.toList();
        case TextQueryType.wildcard:
          final result = <String>{};
          final pattern = RegExp(query.text.replaceAll('*', '.*').replaceAll('?', '.'));
          for (final entry in _wordIndex.entries) {
            if (pattern.hasMatch(entry.key)) {
              result.addAll(entry.value);
            }
          }
          return result.toList();
      }
    }
    return [];
  }
  
  List<String> _extractWords(String text) {
    return text
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
  }
  
  @override
  void clear() {
    _wordIndex.clear();
    _prefixIndex.clear();
  }
  
  @override
  IndexStats getStats() {
    return IndexStats(
      name: name,
      type: 'text',
      keyCount: _wordIndex.values.fold<int>(0, (sum, keys) => sum + keys.length),
      memoryUsage: _estimateMemoryUsage(),
    );
  }
  
  int _estimateMemoryUsage() {
    return (_wordIndex.length + _prefixIndex.length) * 40 + 
           _wordIndex.values.fold<int>(0, (sum, keys) => sum + keys.length * 20) +
           _prefixIndex.values.fold<int>(0, (sum, keys) => sum + keys.length * 20);
  }
}

/// Index manager for coordinating multiple indexes
class IndexManager {
  final Map<String, DataIndex> _indexes = {};
  final Map<String, StreamController<IndexEvent>> _eventControllers = {};
  
  /// Add an index
  void addIndex(DataIndex index) {
    _indexes[index.name] = index;
    _eventControllers[index.name] = StreamController<IndexEvent>.broadcast();
  }
  
  /// Remove an index
  void removeIndex(String name) {
    _indexes.remove(name);
    _eventControllers[name]?.close();
    _eventControllers.remove(name);
  }
  
  /// Get an index by name
  DataIndex? getIndex(String name) {
    return _indexes[name];
  }
  
  /// Update all indexes when data changes
  void updateIndexes(String key, Map<String, dynamic>? oldData, Map<String, dynamic>? newData) {
    for (final entry in _indexes.entries) {
      final indexName = entry.key;
      final index = entry.value;
      
      // Extract field value for this index
      final oldValue = oldData?[indexName];
      final newValue = newData?[indexName];
      
      if (oldValue != newValue) {
        if (oldValue == null && newValue != null) {
          index.add(key, newValue);
          _emitEvent(indexName, IndexEvent.added(key, newValue));
        } else if (oldValue != null && newValue == null) {
          index.remove(key);
          _emitEvent(indexName, IndexEvent.removed(key, oldValue));
        } else if (oldValue != null && newValue != null) {
          index.update(key, oldValue, newValue);
          _emitEvent(indexName, IndexEvent.updated(key, oldValue, newValue));
        }
      }
    }
  }
  
  /// Query multiple indexes
  List<String> query(Map<String, IndexQuery> queries) {
    if (queries.isEmpty) return [];
    
    Set<String>? result;
    
    for (final entry in queries.entries) {
      final indexName = entry.key;
      final query = entry.value;
      final index = _indexes[indexName];
      
      if (index != null) {
        final queryResult = index.query(query).toSet();
        
        if (result == null) {
          result = queryResult;
        } else {
          result = result.intersection(queryResult);
        }
        
        if (result.isEmpty) break; // Early termination
      }
    }
    
    return result?.toList() ?? [];
  }
  
  /// Get event stream for an index
  Stream<IndexEvent>? getEventStream(String indexName) {
    return _eventControllers[indexName]?.stream;
  }
  
  /// Get all index statistics
  Map<String, IndexStats> getAllStats() {
    return _indexes.map((name, index) => MapEntry(name, index.getStats()));
  }
  
  /// Clear all indexes
  void clear() {
    _indexes.values.forEach((index) => index.clear());
  }
  
  /// Close all resources
  void close() {
    _eventControllers.values.forEach((controller) => controller.close());
    _eventControllers.clear();
    _indexes.clear();
  }
  
  void _emitEvent(String indexName, IndexEvent event) {
    _eventControllers[indexName]?.add(event);
  }
}

/// Query types
abstract class IndexQuery {}

class EqualityQuery implements IndexQuery {
  final dynamic value;
  EqualityQuery(this.value);
}

class RangeQuery implements IndexQuery {
  final num min;
  final num max;
  RangeQuery(this.min, this.max);
}

class ComparisonQuery implements IndexQuery {
  final ComparisonOperator operator;
  final dynamic value;
  ComparisonQuery(this.operator, this.value);
}

class InQuery implements IndexQuery {
  final List<dynamic> values;
  InQuery(this.values);
}

class TextQuery implements IndexQuery {
  final TextQueryType type;
  final String text;
  TextQuery(this.type, this.text);
}

enum ComparisonOperator {
  lessThan,
  lessThanOrEqual,
  greaterThan,
  greaterThanOrEqual,
}

enum TextQueryType {
  exact,
  prefix,
  contains,
  wildcard,
}

/// Index statistics
class IndexStats {
  final String name;
  final String type;
  final int keyCount;
  final int memoryUsage;
  
  const IndexStats({
    required this.name,
    required this.type,
    required this.keyCount,
    required this.memoryUsage,
  });
  
  @override
  String toString() {
    return 'IndexStats(name: $name, type: $type, keys: $keyCount, memory: ${memoryUsage}B)';
  }
}

/// Index events
class IndexEvent {
  final IndexEventType type;
  final String key;
  final dynamic oldValue;
  final dynamic newValue;
  
  const IndexEvent._(this.type, this.key, this.oldValue, this.newValue);
  
  factory IndexEvent.added(String key, dynamic value) {
    return IndexEvent._(IndexEventType.added, key, null, value);
  }
  
  factory IndexEvent.removed(String key, dynamic value) {
    return IndexEvent._(IndexEventType.removed, key, value, null);
  }
  
  factory IndexEvent.updated(String key, dynamic oldValue, dynamic newValue) {
    return IndexEvent._(IndexEventType.updated, key, oldValue, newValue);
  }
}

enum IndexEventType {
  added,
  removed,
  updated,
}
