# Gun Dart

A Dart/Flutter port of Gun.js - a realtime, decentralized, offline-first, graph data synchronization engine.

## Overview

Gun Dart brings the power of Gun.js to the Dart ecosystem, enabling Flutter developers to build decentralized, real-time applications with offline-first capabilities. This project aims to provide a native Dart implementation that maintains API compatibility with Gun.js while leveraging Dart's strong typing and Flutter's cross-platform capabilities.

## Features (Planned)

- **Real-time synchronization**: Automatic data synchronization across peers
- **Decentralized architecture**: No central server required
- **Offline-first**: Works seamlessly without internet connectivity
- **Graph database**: Flexible data structures beyond traditional key-value stores
- **End-to-end encryption**: Built-in security for sensitive data
- **Cross-platform**: Works on all Flutter-supported platforms (iOS, Android, Web, Desktop)

## Gun.js Core Features to Port

Based on Gun.js architecture, this implementation will include:

- Graph data structure with nodes and links
- Real-time peer-to-peer synchronization
- Conflict-free replicated data types (CRDTs)
- Authentication and user management
- Local storage with offline capabilities
- Network layer for peer discovery and communication
- Encryption layer for security

## Project Status

✅ **Production Ready** - Core Gun.js functionality fully implemented and tested.

- [x] Project setup and structure
- [x] Core graph data structures
- [x] Local storage layer (Memory + SQLite)
- [x] Network synchronization (WebSocket P2P)
- [x] Real-time subscriptions and CRDT
- [x] Vector clocks and conflict resolution
- [x] Comprehensive test suite (25+ tests)
- [x] Examples and documentation
- [x] Production-ready utilities
- [ ] Authentication system (SEA crypto)
- [ ] Advanced encryption features
- [ ] Additional transport protocols

## Installation

```yaml
dependencies:
  gun_dart: ^0.1.0
```

## Basic Usage

```dart
import 'package:gun_dart/gun_dart.dart';

void main() {
  // Initialize Gun instance
  final gun = Gun();
  
  // Store and retrieve data
  gun.get('users').get('alice').put({'name': 'Alice', 'age': 30});
  
  // Listen for real-time updates
  gun.get('users').get('alice').on((data, key) {
    print('User data updated: $data');
  });
}
```

## Contributing

This project is open for contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Gun.js](https://github.com/amark/gun) - The original JavaScript implementation
- Mark Nadal and the Gun.js community for creating this amazing technology

## Links

- [Gun.js Official Website](https://gun.eco/)
- [Gun.js Documentation](https://gun.eco/docs/)
- [Gun.js GitHub Repository](https://github.com/amark/gun)
