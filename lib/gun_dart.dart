/// Gun Dart - A Dart/Flutter port of Gun.js
///
/// A realtime, decentralized, offline-first, graph data synchronization engine
/// for Flutter and Dart applications.
///
/// Gun Dart provides:
/// - Real-time data synchronization
/// - Decentralized architecture
/// - Offline-first capabilities
/// - Graph database functionality
/// - End-to-end encryption
/// - Cross-platform support
library gun_dart;

// Core exports
export 'src/gun.dart';
export 'src/gun_node.dart';
export 'src/gun_chain.dart';

// Data structure exports
export 'src/data/graph.dart';
export 'src/data/node.dart';
export 'src/data/crdt.dart';
export 'src/data/crdt_types.dart';
export 'src/data/metadata_manager.dart';

// Storage exports
export 'src/storage/storage_adapter.dart';
export 'src/storage/memory_storage.dart';
export 'src/storage/index.dart';
// Note: SQLite storage is available but requires Flutter environment
// export 'src/storage/sqlite_storage.dart';

// Network
export 'src/network/peer.dart';
export 'src/network/transport.dart';
export 'src/network/websocket_transport.dart';
export 'src/network/http_transport.dart';
export 'src/network/webrtc_transport.dart';
export 'src/network/gun_wire_protocol.dart';
export 'src/network/message_tracker.dart';
export 'src/network/gun_query.dart';
export 'src/network/peer_handshake.dart';
export 'src/network/mesh_discovery.dart';
export 'src/network/gun_relay_client.dart';
export 'src/network/relay_pool_manager.dart';

// Auth
export 'src/auth/user.dart';
export 'src/auth/sea.dart';

// Utils exports
export 'src/utils/utils.dart';
export 'src/utils/encoder.dart';
export 'src/utils/validator.dart';

// Types and interfaces
export 'src/types/types.dart';
export 'src/types/events.dart';

// Flutter widgets (only available when using Flutter)
export 'src/flutter/gun_builder.dart';
export 'src/flutter/gun_provider.dart';
