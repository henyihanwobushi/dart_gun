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

// Storage exports
export 'src/storage/storage_adapter.dart';
export 'src/storage/memory_storage.dart';
// Note: SQLite storage is available but requires Flutter environment
// export 'src/storage/sqlite_storage.dart';

// Network exports
export 'src/network/peer.dart';
export 'src/network/transport.dart';
export 'src/network/websocket_transport.dart';

// Auth exports
export 'src/auth/user.dart';
export 'src/auth/sea.dart';

// Utils exports
export 'src/utils/utils.dart';
export 'src/utils/encoder.dart';
export 'src/utils/validator.dart';

// Types and interfaces
export 'src/types/types.dart';
export 'src/types/events.dart';
