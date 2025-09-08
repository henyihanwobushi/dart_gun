# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

Project: gun_dart — a Dart/Flutter port of Gun.js (real-time, decentralized, offline-first graph data sync engine).

Commands
- Prereqs
  - Requires Dart SDK >= 3.0.0 and Flutter SDK >= 3.0.0 (see pubspec.yaml)
- Install dependencies
  - flutter pub get
- Analyze / Lint
  - flutter analyze
- Format
  - dart format .
- Run tests (Flutter test runner is required because tests import flutter_test)
  - All tests: flutter test
  - Single file: flutter test test/gun_dart_test.dart
  - Filter by test name: flutter test --plain-name "should create Gun instance"
  - Run with logs: flutter test -r expanded
- Run example
  - dart run example/basic_example.dart
- Package checks
  - Dry-run publish validation: dart pub publish --dry-run

High-level architecture
- Public API surface (library exports)
  - lib/gun_dart.dart aggregates the public API and re-exports core, data, storage, network, auth, utils, and types modules. Consumers import package:gun_dart/gun_dart.dart
- Core
  - Gun (lib/src/gun.dart)
    - Entry point and façade over storage and networking
    - Constructor accepts GunOptions; defaults to in-memory storage
    - Methods: get(key) -> GunChain, put(data) at root, on(event stream), addPeer(peer), close()
    - Manages peers and a broadcast StreamController<GunEvent>
  - GunChain (lib/src/gun_chain.dart)
    - Chainable API (similar to Gun.js) to traverse keys/paths
    - get(key) builds path segments; put(data) persists via StorageAdapter
    - once() reads current value via StorageAdapter
    - on(listener) placeholder (TODO: real-time subscriptions not yet wired)
- Data model
  - types/types.dart
    - GunOptions: configuration (storage, peers, local/realtime flags, limits)
    - GunNode: immutable node representation with id/data/meta/lastModified
    - GunLink: lightweight link (# reference) modeling graph edges
    - GunMessage/GunMessageType: protocol message envelope for network layer
    - GunState enum: coarse state machine flags
  - data/{graph.dart,node.dart,crdt.dart}
    - Planned facilities for graph structure and CRDT conflict resolution
- Storage layer
  - storage/storage_adapter.dart (abstract)
    - initialize, put/get/delete, exists, keys, clear, close
  - storage/memory_storage.dart
    - In-memory implementation used by default for tests/examples
  - storage/sqlite_storage.dart
    - SQLite-backed implementation (via sqflite) for persistence in Flutter contexts
  - Design intent: swap adapters via GunOptions; all path-based via joined keys (e.g., users/testuser)
- Network layer
  - network/peer.dart (abstract Peer)
    - url, isConnected, connect/disconnect, send, messages stream
  - network/transport.dart, websocket_transport.dart
    - Transport abstractions and WebSocket implementation for real-time sync between peers
  - Gun maintains a list of peers and connects on initialization/addPeer
  - Protocol data flows via GunMessage envelopes (types: get/put/hi/bye/dam)
- Auth layer
  - auth/{user.dart, sea.dart}
    - Planned support for user and SEA-style crypto compatible with Gun.js
- Utilities and Types
  - utils/{utils.dart, encoder.dart, validator.dart}
    - Shared helpers for encoding/validation and general utilities
  - types/events.dart
    - Event types emitted through Gun’s broadcast stream (e.g., put)

Repository highlights
- README.md captures project goals, WIP status, and basic usage mirroring Gun.js semantics
- example/basic_example.dart shows minimal end-to-end usage with put/once and a placeholder on() subscription
- test/gun_dart_test.dart exercises basic flows: instance creation, put/once on simple and nested paths, null for missing keys

Development notes specific to this repo
- Tests currently rely on the default MemoryStorage adapter; on() in GunChain is a no-op placeholder, so real-time tests are not yet implemented
- SQLite adapter requires Flutter/sqflite; prefer MemoryStorage for unit tests and CI unless platform storage is explicitly required
- Network peers are connect()ed at Gun initialization; WebSocket transport exists but end-to-end sync/topology tests are not present yet

How to run a focused workflow
- Implement or debug a storage method
  1) Edit the relevant storage adapter under lib/src/storage/
  2) Run analyzer: flutter analyze
  3) Run only storage-related tests by file: flutter test test/gun_dart_test.dart
- Implement real-time subscription
  1) Wire GunChain.on(...) to the event stream in Gun and/or storage change notifications
  2) Add integration tests under test/ that validate on-callbacks
  3) Run: flutter test --plain-name "on("

Key files
- Public entry: lib/gun_dart.dart
- Core engine: lib/src/gun.dart, lib/src/gun_chain.dart
- Storage SPI + impls: lib/src/storage/
- Network SPI + impls: lib/src/network/
- Types and protocol: lib/src/types/
- Example: example/basic_example.dart
- Tests: test/gun_dart_test.dart

