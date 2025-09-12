# Gun.js DAM Error Handling System

## Overview

This document describes the Gun Dart implementation of Gun.js compatible error handling using the DAM (Distributed Ammunition Machine) message format. The system provides robust error handling, recovery mechanisms, and full compatibility with Gun.js error messages.

## Features

### ✅ Complete DAM Message Support
- **Parse DAM messages** from Gun.js peers
- **Generate DAM messages** in Gun.js compatible format
- **Round-trip conversion** between Gun errors and DAM messages
- **Message format validation** with proper field handling

### ✅ Comprehensive Error Types
- `GunErrorType.notFound` - Data not found errors
- `GunErrorType.unauthorized` - Authorization failed
- `GunErrorType.timeout` - Request timeout errors
- `GunErrorType.validation` - Data validation errors
- `GunErrorType.conflict` - CRDT conflict resolution errors
- `GunErrorType.network` - Network connectivity errors
- `GunErrorType.storage` - Storage adapter errors
- `GunErrorType.malformed` - Malformed message errors
- `GunErrorType.permission` - Permission denied errors
- `GunErrorType.limit` - Rate limit exceeded errors
- `GunErrorType.unknown` - Unknown/unexpected errors

### ✅ Smart Retry Logic
- **Exponential backoff** for timeout errors (1s, 2s, 4s, 8s, 16s, 32s)
- **Linear backoff** for network errors (0.5s, 1s, 1.5s, 2s, 2.5s, max 5s)
- **Non-retryable** errors for auth, validation, and malformed messages

### ✅ Error Tracking & Analytics
- **Error history** with configurable size limits (default: 1000 entries)
- **Recent errors** tracking (default: last 100 errors)
- **Error statistics** by type
- **Memory management** with automatic cleanup

### ✅ Event System Integration
- **Error streams** for reactive error handling
- **Gun event integration** for backward compatibility
- **Error handler lifecycle** management

## Usage

### Basic Error Handling

```dart
import 'package:dart_gun/dart_gun.dart';

final gun = Gun();

// Subscribe to errors
gun.errors.listen((error) {
  print('Error: ${error.type.name} - ${error.message}');
  
  // Check if retryable
  if (gun.errorHandler.shouldRetry(error.type)) {
    final delay = gun.errorHandler.getRetryDelay(error.type, 1);
    print('Retry in ${delay.inMilliseconds}ms');
  }
});
```

### Creating Specific Error Types

```dart
// Not found error
final notFound = GunError.notFound('users/alice', field: 'profile');
gun.errorHandler.handleError(notFound);

// Unauthorized error
final unauthorized = GunError.unauthorized('Invalid token');
gun.errorHandler.handleError(unauthorized);

// Timeout error with duration
final timeout = GunError.timeout('query', duration: Duration(seconds: 5));
gun.errorHandler.handleError(timeout);

// Network error with URL context
final network = GunError.network('Connection failed', url: 'ws://localhost:8765');
gun.errorHandler.handleError(network);

// CRDT conflict error
final conflict = GunError.conflict('node1', 'field1', 'Version mismatch');
gun.errorHandler.handleError(conflict);
```

### Processing DAM Messages from Gun.js

```dart
// Handle DAM message from Gun.js peer
final damMessage = {
  'dam': 'Node "users/bob" not found',
  '@': 'HyETBKILb',      // Message ID
  '#': 'HyETBKILf',      // Acknowledgment ID
  'node': 'users/bob',   // Node context
};

gun.errorHandler.handleDAM(damMessage);
```

### Sending DAM Messages to Gun.js Peers

```dart
final error = GunError.notFound('test-node');

// Send DAM message to peer
await gun.errorHandler.sendDAM(
  error,
  (damMessage) async {
    // Send damMessage to peer via network transport
    await peer.send(damMessage);
  },
  originalMessageId: 'query-123',
);
```

### Error Statistics and Analytics

```dart
// Get error statistics
final stats = gun.errorHandler.errorStats;
print('Timeout errors: ${stats['timeout'] ?? 0}');
print('Network errors: ${stats['network'] ?? 0}');

// Get recent errors
final recentErrors = gun.errorHandler.recentErrors;
for (final error in recentErrors.take(5)) {
  print('${error.type.name}: ${error.message}');
}

// Check specific error by ID
final error = gun.errorHandler.getError('error-id-123');
if (error != null) {
  print('Found error: ${error.message}');
}
```

### Retry Logic Implementation

```dart
Future<void> operationWithRetry() async {
  int attempts = 0;
  const maxAttempts = 3;
  
  while (attempts < maxAttempts) {
    try {
      await performOperation();
      return; // Success
    } catch (e) {
      attempts++;
      
      // Handle with error handler
      gun.errorHandler.handleException(e, 'operation retry');
      
      if (attempts < maxAttempts) {
        // Determine retry based on error type
        final errorType = _classifyException(e);
        if (gun.errorHandler.shouldRetry(errorType)) {
          final delay = gun.errorHandler.getRetryDelay(errorType, attempts);
          await Future.delayed(delay);
          continue;
        }
      }
      
      rethrow; // Give up
    }
  }
}

GunErrorType _classifyException(dynamic exception) {
  if (exception is TimeoutException) return GunErrorType.timeout;
  if (exception is SocketException) return GunErrorType.network;
  if (exception is FormatException) return GunErrorType.malformed;
  return GunErrorType.unknown;
}
```

## DAM Message Format

### Standard Gun.js DAM Message
```json
{
  "dam": "Error message text",
  "@": "message-id",
  "#": "ack-id",
  "node": "optional-node-id",
  "code": "optional-error-code",
  "type": "gun-dart-error-type"
}
```

### Field Descriptions
- `dam`: Human-readable error message
- `@`: Unique message identifier
- `#`: Acknowledgment/response message ID
- `node`: Node ID where error occurred (optional)
- `code`: Machine-readable error code (optional)
- `type`: Gun Dart error type for round-trip conversion (optional)

## Integration with Gun Class

The error handling system is automatically integrated into the Gun class:

```dart
class Gun {
  final GunErrorHandler _errorHandler = GunErrorHandler();
  
  // Error stream accessor
  Stream<GunError> get errors => _errorHandler.errors;
  
  // Error handler accessor
  GunErrorHandler get errorHandler => _errorHandler;
  
  // Message handling with error support
  Future<void> handleIncomingMessage(Map<String, dynamic> message) async {
    if (message.containsKey('dam')) {
      _errorHandler.handleDAM(message);
      return;
    }
    // ... handle other message types
  }
}
```

## Error Recovery Patterns

### 1. Automatic Retry with Backoff
```dart
gun.errors.where((error) => gun.errorHandler.shouldRetry(error.type))
    .listen((error) async {
      final delay = gun.errorHandler.getRetryDelay(error.type, 1);
      Timer(delay, () {
        // Retry the failed operation
        retryFailedOperation(error);
      });
    });
```

### 2. Circuit Breaker Pattern
```dart
class CircuitBreaker {
  int _failures = 0;
  bool _isOpen = false;
  
  void handleError(GunError error) {
    if (gun.errorHandler.shouldRetry(error.type)) {
      _failures++;
      if (_failures > 5) {
        _isOpen = true; // Stop trying
        Timer(Duration(minutes: 1), () => _reset());
      }
    }
  }
  
  void _reset() {
    _failures = 0;
    _isOpen = false;
  }
}
```

### 3. Fallback Mechanisms
```dart
gun.errors.listen((error) {
  switch (error.type) {
    case GunErrorType.network:
      // Try alternative peer or storage
      tryFallbackPeer();
      break;
    case GunErrorType.storage:
      // Switch to memory storage temporarily
      switchToMemoryStorage();
      break;
    case GunErrorType.unauthorized:
      // Trigger re-authentication
      triggerReauth();
      break;
  }
});
```

## Configuration Options

```dart
// Custom error handler configuration
final errorHandler = GunErrorHandler(
  maxHistory: 2000,  // Keep 2000 errors in history
  maxRecent: 200,    // Track last 200 recent errors
);

// Or using factory constructor
final errorHandler = GunErrorHandler.configure(
  maxHistory: 500,
  maxRecent: 50,
);
```

## Testing

Comprehensive test coverage includes:

- ✅ DAM message parsing and generation
- ✅ Error type classification and handling
- ✅ Retry logic with proper delays
- ✅ Error statistics and tracking
- ✅ Round-trip DAM conversion
- ✅ Memory management and cleanup
- ✅ Gun.js compatibility scenarios

Run the tests:
```bash
# Test error handling specifically
flutter test test/gun_error_handler_test.dart

# Run all tests
flutter test

# Run example
dart run example/simple_dam_error_example.dart
```

## Performance Considerations

- **Memory Management**: Error history is automatically capped and cleaned up
- **Event Streams**: Use broadcast streams for multiple listeners
- **Error Parsing**: Efficient regex-based error type detection
- **Retry Delays**: Capped exponential/linear backoff prevents excessive delays

## Gun.js Compatibility

The system is designed for full compatibility with Gun.js:

- ✅ **DAM Message Format**: Standard Gun.js DAM format
- ✅ **Error Types**: Mapped to Gun.js error scenarios
- ✅ **Message IDs**: Compatible ID generation and tracking
- ✅ **Network Protocol**: Integrates with Gun wire protocol
- ✅ **Peer Communication**: Seamless error exchange with Gun.js peers

## Migration from Simple Error Handling

If upgrading from basic try/catch error handling:

```dart
// Old way
try {
  await operation();
} catch (e) {
  print('Error: $e');
}

// New way with DAM support
try {
  await gun.withErrorHandling(() => operation());
} catch (e) {
  // Error is automatically tracked and can be retried
  // DAM messages are sent to peers if needed
}
```

This provides a comprehensive, production-ready error handling system that maintains full compatibility with the Gun.js ecosystem while providing enhanced error tracking, retry logic, and recovery mechanisms.
