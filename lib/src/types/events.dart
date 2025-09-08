/// Event types for Gun Dart operations
enum GunEventType {
  get,
  put,
  on,
  off,
  once,
  map,
  set,
  back,
  auth,
  create,
  leave,
}

/// Represents an event in Gun Dart
class GunEvent {
  /// Type of the event
  final GunEventType type;
  
  /// Key associated with the event
  final String key;
  
  /// Data associated with the event
  final dynamic data;
  
  /// Additional metadata
  final Map<String, dynamic> meta;
  
  /// Timestamp when the event occurred
  final DateTime timestamp;
  
  const GunEvent({
    required this.type,
    required this.key,
    this.data,
    this.meta = const {},
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
  
  @override
  String toString() {
    return 'GunEvent(type: $type, key: $key, data: $data, timestamp: $timestamp)';
  }
}
