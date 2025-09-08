import 'dart:math' as math;

/// Advanced CRDT (Conflict-free Replicated Data Type) implementations
/// extending beyond basic key-value storage

/// G-Counter (Grow-only Counter) CRDT
/// 
/// A distributed counter that can only increment, ensuring convergence
/// across all replicas without coordination.
class GCounter {
  final String _nodeId;
  final Map<String, int> _counters = {};

  GCounter(this._nodeId);

  /// Create from existing counter state
  GCounter.fromState(this._nodeId, Map<String, int> state) {
    _counters.addAll(state);
  }

  /// Current value of the counter (sum of all node values)
  int get value => _counters.values.fold(0, (sum, count) => sum + count);

  /// Increment counter for this node
  void increment([int amount = 1]) {
    if (amount < 0) throw ArgumentError('G-Counter can only increment');
    _counters[_nodeId] = (_counters[_nodeId] ?? 0) + amount;
  }

  /// Merge with another G-Counter (taking maximum of each node)
  void merge(GCounter other) {
    for (final entry in other._counters.entries) {
      final nodeId = entry.key;
      final count = entry.value;
      _counters[nodeId] = math.max(_counters[nodeId] ?? 0, count);
    }
  }

  /// Get state for serialization
  Map<String, int> getState() => Map.unmodifiable(_counters);

  /// Compare with another counter for partial ordering
  bool isLessEqualThan(GCounter other) {
    final allNodes = {..._counters.keys, ...other._counters.keys};
    for (final nodeId in allNodes) {
      final thisCount = _counters[nodeId] ?? 0;
      final otherCount = other._counters[nodeId] ?? 0;
      if (thisCount > otherCount) return false;
    }
    return true;
  }

  @override
  String toString() => 'GCounter(value: $value, state: $_counters)';
}

/// PN-Counter (Increment/Decrement Counter) CRDT
/// 
/// A distributed counter that supports both increment and decrement operations
/// using two G-Counters internally.
class PNCounter {
  final String _nodeId;
  final GCounter _positive;
  final GCounter _negative;

  PNCounter(this._nodeId)
      : _positive = GCounter(_nodeId),
        _negative = GCounter(_nodeId);

  /// Create from existing state
  PNCounter.fromState(
    this._nodeId,
    Map<String, int> positiveState,
    Map<String, int> negativeState,
  )   : _positive = GCounter.fromState(_nodeId, positiveState),
        _negative = GCounter.fromState(_nodeId, negativeState);

  /// Current value (positive - negative)
  int get value => _positive.value - _negative.value;

  /// Increment the counter
  void increment([int amount = 1]) {
    if (amount < 0) {
      decrement(-amount);
    } else {
      _positive.increment(amount);
    }
  }

  /// Decrement the counter
  void decrement([int amount = 1]) {
    if (amount < 0) {
      increment(-amount);
    } else {
      _negative.increment(amount);
    }
  }

  /// Merge with another PN-Counter
  void merge(PNCounter other) {
    _positive.merge(other._positive);
    _negative.merge(other._negative);
  }

  /// Get state for serialization
  Map<String, dynamic> getState() => {
        'positive': _positive.getState(),
        'negative': _negative.getState(),
      };

  @override
  String toString() => 'PNCounter(value: $value)';
}

/// G-Set (Grow-only Set) CRDT
/// 
/// A distributed set that only supports additions, ensuring all replicas
/// converge to the same state.
class GSet<T> {
  final Set<T> _elements = <T>{};

  GSet();

  /// Create from existing elements
  GSet.fromElements(Iterable<T> elements) {
    _elements.addAll(elements);
  }

  /// Add element to the set
  void add(T element) {
    _elements.add(element);
  }

  /// Add multiple elements
  void addAll(Iterable<T> elements) {
    _elements.addAll(elements);
  }

  /// Check if element exists
  bool contains(T element) => _elements.contains(element);

  /// Get all elements
  Set<T> get elements => Set.unmodifiable(_elements);

  /// Number of elements
  int get length => _elements.length;

  /// Check if set is empty
  bool get isEmpty => _elements.isEmpty;

  /// Merge with another G-Set (union)
  void merge(GSet<T> other) {
    _elements.addAll(other._elements);
  }

  /// Get state for serialization
  List<T> getState() => _elements.toList();

  @override
  String toString() => 'GSet(${_elements.join(', ')})';
}

/// 2P-Set (Two-Phase Set) CRDT
/// 
/// A distributed set that supports both additions and removals using
/// two G-Sets internally (added and removed elements).
class TwoPSet<T> {
  final GSet<T> _added = GSet<T>();
  final GSet<T> _removed = GSet<T>();

  TwoPSet();

  /// Create from existing state
  TwoPSet.fromState(List<T> added, List<T> removed) {
    _added.addAll(added);
    _removed.addAll(removed);
  }

  /// Add element to the set
  void add(T element) {
    _added.add(element);
  }

  /// Remove element from the set (mark as removed)
  void remove(T element) {
    if (!_added.contains(element)) {
      throw StateError('Cannot remove element that was never added');
    }
    _removed.add(element);
  }

  /// Check if element is in the set (added but not removed)
  bool contains(T element) {
    return _added.contains(element) && !_removed.contains(element);
  }

  /// Get current elements (added minus removed)
  Set<T> get elements {
    return _added.elements.where((e) => !_removed.contains(e)).toSet();
  }

  /// Number of current elements
  int get length => elements.length;

  /// Check if set is empty
  bool get isEmpty => elements.isEmpty;

  /// Merge with another 2P-Set
  void merge(TwoPSet<T> other) {
    _added.merge(other._added);
    _removed.merge(other._removed);
  }

  /// Get state for serialization
  Map<String, List<T>> getState() => {
        'added': _added.getState(),
        'removed': _removed.getState(),
      };

  @override
  String toString() => 'TwoPSet(${elements.join(', ')})';
}

/// OR-Set (Observed-Remove Set) CRDT
/// 
/// A more advanced set CRDT that allows re-adding previously removed elements
/// by tracking unique tags for each addition.
class ORSet<T> {
  final String _nodeId;
  final Map<T, Set<String>> _elements = {};
  final Map<T, Set<String>> _removed = {};
  int _tagCounter = 0;

  ORSet(this._nodeId);

  /// Create from existing state
  ORSet.fromState(
    this._nodeId,
    Map<T, Set<String>> elements,
    Map<T, Set<String>> removed,
    int tagCounter,
  ) : _tagCounter = tagCounter {
    for (final entry in elements.entries) {
      _elements[entry.key] = Set.from(entry.value);
    }
    for (final entry in removed.entries) {
      _removed[entry.key] = Set.from(entry.value);
    }
  }

  /// Add element with unique tag
  String add(T element) {
    final tag = '${_nodeId}_${_tagCounter++}';
    _elements.putIfAbsent(element, () => <String>{}).add(tag);
    return tag;
  }

  /// Remove element by removing all its current tags
  void remove(T element) {
    final tags = _elements[element];
    if (tags != null && tags.isNotEmpty) {
      _removed.putIfAbsent(element, () => <String>{}).addAll(tags);
    }
  }

  /// Remove element by specific tag
  void removeTag(T element, String tag) {
    _removed.putIfAbsent(element, () => <String>{}).add(tag);
  }

  /// Check if element is present (has tags not removed)
  bool contains(T element) {
    final elementTags = _elements[element] ?? <String>{};
    final removedTags = _removed[element] ?? <String>{};
    return elementTags.difference(removedTags).isNotEmpty;
  }

  /// Get current elements
  Set<T> get elements {
    return _elements.keys.where((element) => contains(element)).toSet();
  }

  /// Number of current elements
  int get length => elements.length;

  /// Check if set is empty
  bool get isEmpty => elements.isEmpty;

  /// Merge with another OR-Set
  void merge(ORSet<T> other) {
    // Merge elements
    for (final entry in other._elements.entries) {
      _elements.putIfAbsent(entry.key, () => <String>{}).addAll(entry.value);
    }

    // Merge removed tags
    for (final entry in other._removed.entries) {
      _removed.putIfAbsent(entry.key, () => <String>{}).addAll(entry.value);
    }

    // Update tag counter to avoid conflicts
    _tagCounter = math.max(_tagCounter, other._tagCounter);
  }

  /// Get state for serialization
  Map<String, dynamic> getState() => {
        'elements': _elements.map(
          (k, v) => MapEntry(k.toString(), v.toList()),
        ),
        'removed': _removed.map(
          (k, v) => MapEntry(k.toString(), v.toList()),
        ),
        'tagCounter': _tagCounter,
      };

  @override
  String toString() => 'ORSet(${elements.join(', ')})';
}

/// LWW-Register (Last-Write-Wins Register) CRDT
/// 
/// A register that resolves conflicts by keeping the value with the
/// latest timestamp (or using node ID as tiebreaker).
class LWWRegister<T> {
  T? _value;
  int _timestamp;
  String _nodeId;

  LWWRegister(this._nodeId) : _timestamp = 0;

  /// Create with initial value
  LWWRegister.withValue(this._nodeId, T value)
      : _value = value,
        _timestamp = DateTime.now().millisecondsSinceEpoch;

  /// Create from existing state
  LWWRegister.fromState(this._nodeId, T? value, int timestamp)
      : _value = value,
        _timestamp = timestamp;

  /// Current value
  T? get value => _value;

  /// Current timestamp
  int get timestamp => _timestamp;

  /// Node ID that last updated this register
  String get nodeId => _nodeId;

  /// Set new value with current timestamp
  void set(T value) {
    _value = value;
    _timestamp = DateTime.now().millisecondsSinceEpoch;
  }

  /// Set value with specific timestamp
  void setWithTimestamp(T value, int timestamp, String nodeId) {
    if (timestamp > _timestamp || 
        (timestamp == _timestamp && nodeId.compareTo(_nodeId) > 0)) {
      _value = value;
      _timestamp = timestamp;
      _nodeId = nodeId;
    }
  }

  /// Merge with another LWW-Register
  void merge(LWWRegister<T> other) {
    if (other._timestamp > _timestamp ||
        (other._timestamp == _timestamp && 
         other._nodeId.compareTo(_nodeId) > 0)) {
      _value = other._value;
      _timestamp = other._timestamp;
      _nodeId = other._nodeId;
    }
  }

  /// Get state for serialization
  Map<String, dynamic> getState() => {
        'value': _value,
        'timestamp': _timestamp,
        'nodeId': _nodeId,
      };

  @override
  String toString() => 'LWWRegister(value: $_value, timestamp: $_timestamp, node: $_nodeId)';
}

/// CRDT Factory for creating and managing different CRDT types
class CRDTFactory {
  /// Create G-Counter
  static GCounter createGCounter(String nodeId) => GCounter(nodeId);

  /// Create PN-Counter
  static PNCounter createPNCounter(String nodeId) => PNCounter(nodeId);

  /// Create G-Set
  static GSet<T> createGSet<T>() => GSet<T>();

  /// Create 2P-Set
  static TwoPSet<T> createTwoPSet<T>() => TwoPSet<T>();

  /// Create OR-Set
  static ORSet<T> createORSet<T>(String nodeId) => ORSet<T>(nodeId);

  /// Create LWW-Register
  static LWWRegister<T> createLWWRegister<T>(String nodeId) => LWWRegister<T>(nodeId);

  /// Create CRDT from serialized state
  static dynamic fromState(String type, String nodeId, Map<String, dynamic> state) {
    switch (type) {
      case 'GCounter':
        return GCounter.fromState(nodeId, Map<String, int>.from(state));
      case 'PNCounter':
        return PNCounter.fromState(
          nodeId,
          Map<String, int>.from(state['positive']),
          Map<String, int>.from(state['negative']),
        );
      case 'GSet':
        return GSet.fromElements(List.from(state['elements']));
      case 'TwoPSet':
        return TwoPSet.fromState(
          List.from(state['added']),
          List.from(state['removed']),
        );
      case 'ORSet':
        final elements = (state['elements'] as Map).map(
          (k, v) => MapEntry(k, Set<String>.from(v)),
        );
        final removed = (state['removed'] as Map).map(
          (k, v) => MapEntry(k, Set<String>.from(v)),
        );
        return ORSet.fromState(nodeId, elements, removed, state['tagCounter']);
      case 'LWWRegister':
        return LWWRegister.fromState(nodeId, state['value'], state['timestamp']);
      default:
        throw ArgumentError('Unknown CRDT type: $type');
    }
  }
}
