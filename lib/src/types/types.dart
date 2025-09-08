import '../storage/storage_adapter.dart';
import '../network/peer.dart';

/// Configuration options for Gun instance
class GunOptions {
  /// Storage adapter to use
  final StorageAdapter? storage;
  
  /// List of peers to connect to
  final List<Peer>? peers;
  
  /// Enable local storage
  final bool localStorage;
  
  /// Enable real-time sync
  final bool realtime;
  
  /// Maximum number of peers
  final int maxPeers;
  
  /// Connection timeout in milliseconds
  final int timeout;
  
  const GunOptions({
    this.storage,
    this.peers,
    this.localStorage = true,
    this.realtime = true,
    this.maxPeers = 10,
    this.timeout = 5000,
  });
}

/// Represents a node in the Gun graph
class GunNode {
  /// Unique identifier for this node
  final String id;
  
  /// The actual data stored in this node
  final Map<String, dynamic> data;
  
  /// Metadata about the node
  final Map<String, dynamic> meta;
  
  /// Timestamp when this node was last modified
  final DateTime lastModified;
  
  const GunNode({
    required this.id,
    required this.data,
    this.meta = const {},
    required this.lastModified,
  });
  
  /// Create a copy of this node with updated data
  GunNode copyWith({
    String? id,
    Map<String, dynamic>? data,
    Map<String, dynamic>? meta,
    DateTime? lastModified,
  }) {
    return GunNode(
      id: id ?? this.id,
      data: data ?? Map.from(this.data),
      meta: meta ?? Map.from(this.meta),
      lastModified: lastModified ?? this.lastModified,
    );
  }
  
  /// Convert this node to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'data': data,
      'meta': meta,
      'lastModified': lastModified.toIso8601String(),
    };
  }
  
  /// Create a node from JSON
  factory GunNode.fromJson(Map<String, dynamic> json) {
    return GunNode(
      id: json['id'] as String,
      data: json['data'] as Map<String, dynamic>,
      meta: json['meta'] as Map<String, dynamic>? ?? {},
      lastModified: DateTime.parse(json['lastModified'] as String),
    );
  }
}

/// Callback function type for Gun operations
typedef GunCallback<T> = void Function(T? result, String? error);

/// Function type for Gun event listeners
typedef GunListener<T> = void Function(T data, String key);

/// Represents a link to another node in the Gun graph
class GunLink {
  /// The key/reference to the linked node
  final String reference;
  
  /// Optional metadata about the link
  final Map<String, dynamic> meta;
  
  const GunLink({
    required this.reference,
    this.meta = const {},
  });
  
  /// Convert link to JSON representation
  Map<String, dynamic> toJson() {
    return {
      '#': reference,
      if (meta.isNotEmpty) 'meta': meta,
    };
  }
  
  /// Create a link from JSON
  factory GunLink.fromJson(Map<String, dynamic> json) {
    return GunLink(
      reference: json['#'] as String,
      meta: json['meta'] as Map<String, dynamic>? ?? {},
    );
  }
}

/// State machine states for Gun operations
enum GunState {
  idle,
  loading,
  syncing,
  error,
  disconnected,
  connected,
}

/// Message types for Gun protocol
enum GunMessageType {
  get,
  put,
  hi,
  bye,
  dam,
}

/// Represents a message in the Gun protocol
class GunMessage {
  /// Type of message
  final GunMessageType type;
  
  /// Message payload
  final Map<String, dynamic> data;
  
  /// Message ID for tracking
  final String? id;
  
  /// Timestamp of message
  final DateTime timestamp;
  
  const GunMessage({
    required this.type,
    required this.data,
    this.id,
    required this.timestamp,
  });
  
  /// Convert message to JSON for network transport
  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'data': data,
      if (id != null) 'id': id,
      'timestamp': timestamp.toIso8601String(),
    };
  }
  
  /// Create message from JSON
  factory GunMessage.fromJson(Map<String, dynamic> json) {
    return GunMessage(
      type: GunMessageType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => GunMessageType.get,
      ),
      data: json['data'] as Map<String, dynamic>,
      id: json['id'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}
