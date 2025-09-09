import '../lib/gun_dart.dart';

Future<void> main() async {
  print('=== Gun Dart DAM Error Handling Example ===');
  
  // Create Gun instance with error handling
  final gun = Gun();
  
  // Subscribe to error events
  gun.errors.listen((error) {
    print('\n🚨 Gun Error Detected:');
    print('  Type: ${error.type.name}');
    print('  Message: ${error.message}');
    print('  Code: ${error.code}');
    if (error.nodeId != null) print('  Node: ${error.nodeId}');
    if (error.field != null) print('  Field: ${error.field}');
    print('  Timestamp: ${error.timestamp}');
    print('  Error ID: ${error.errorId}');
    
    // Check if error should be retried
    if (gun.errorHandler.shouldRetry(error.type)) {
      final delay = gun.errorHandler.getRetryDelay(error.type, 1);
      print('  🔄 Retry recommended after ${delay.inMilliseconds}ms');
    } else {
      print('  ❌ Error is not retryable');
    }
    print('');
  });
  
  print('\n1. Demonstrating different error types...\n');
  
  // Simulate various error scenarios
  await demonstrateErrorTypes(gun);
  
  print('\n2. Demonstrating DAM message handling...\n');
  
  // Simulate receiving DAM messages from Gun.js peers
  await demonstrateDamMessages(gun);
  
  print('\n3. Demonstrating error statistics...\n');
  
  // Show error statistics after generating various errors
  await demonstrateErrorStats(gun);
  
  print('\n4. Demonstrating retry logic...\n');
  
  // Demonstrate retry logic for different error types
  await demonstrateRetryLogic(gun);
  
  // Clean up
  await gun.close();
  
  print('\n=== Example completed ===');
}

Future<void> demonstrateErrorTypes(Gun gun) async {
  print('Creating various Gun error types:');
  
  // Not found error
  final notFound = GunError.notFound('users/alice', field: 'profile');
  gun.errorHandler.handleError(notFound);
  
  await Future.delayed(const Duration(milliseconds: 100));
  
  // Unauthorized error
  final unauthorized = GunError.unauthorized('Invalid API key');
  gun.errorHandler.handleError(unauthorized);
  
  await Future.delayed(const Duration(milliseconds: 100));
  
  // Timeout error
  final timeout = GunError.timeout('database query', duration: const Duration(seconds: 5));
  gun.errorHandler.handleError(timeout);
  
  await Future.delayed(const Duration(milliseconds: 100));
  
  // Network error
  final network = GunError.network('Connection refused', url: 'ws://localhost:8765');
  gun.errorHandler.handleError(network);
  
  await Future.delayed(const Duration(milliseconds: 100));
  
  // CRDT conflict error
  final conflict = GunError.conflict('posts/123', 'content', 'Concurrent edit detected');
  gun.errorHandler.handleError(conflict);
  
  await Future.delayed(const Duration(milliseconds: 100));
}

Future<void> demonstrateDamMessages(Gun gun) async {
  print('Processing DAM messages from Gun.js peers:');
  
  // Simulate various DAM message formats from Gun.js
  final damMessages = [
    {
      'dam': 'Node "users/bob" not found',
      '@': 'HyETBKILb',
      '#': 'HyETBKILf',
      'node': 'users/bob',
    },
    {
      'dam': 'Request timeout after 10000ms',
      '@': 'SyBTCYILZ',
      '#': 'BySTAKULZ',
      'code': 'TIMEOUT',
    },
    {
      'dam': 'Unauthorized access to private data',
      '@': 'ryBTDt8Ub',
      '#': 'HkxpwYUIZ',
      'err': 401,
    },
    {
      'dam': 'Rate limit exceeded: 100 requests per minute',
      '@': 'SkWTut8Uf',
      '#': 'B1MpDKL8-',
      'limit': 100,
      'current': 150,
    },
  ];
  
  for (final damMessage in damMessages) {
    print('  Processing DAM: ${damMessage['dam']}');
    gun.errorHandler.handleDAM(damMessage);
    await Future.delayed(const Duration(milliseconds: 200));
  }
}

Future<void> demonstrateErrorStats(Gun gun) async {
  final stats = gun.errorHandler.errorStats;
  final recentErrors = gun.errorHandler.recentErrors;
  
  print('Error Statistics:');
  stats.forEach((type, count) {
    print('  $type: $count errors');
  });
  
  print('\nRecent Errors (last ${recentErrors.length}):');
  for (int i = 0; i < recentErrors.length && i < 5; i++) {
    final error = recentErrors[recentErrors.length - 1 - i];
    print('  ${i + 1}. ${error.type.name}: ${error.message}');
  }
  
  if (recentErrors.length > 5) {
    print('  ... and ${recentErrors.length - 5} more');
  }
}

Future<void> demonstrateRetryLogic(Gun gun) async {
  print('Testing retry logic for different error types:');
  
  final errorTypes = [
    GunErrorType.timeout,
    GunErrorType.network,
    GunErrorType.unauthorized,
    GunErrorType.validation,
    GunErrorType.notFound,
  ];
  
  for (final errorType in errorTypes) {
    final shouldRetry = gun.errorHandler.shouldRetry(errorType);
    print('\n  ${errorType.name}:');
    print('    Should retry: $shouldRetry');
    
    if (shouldRetry) {
      print('    Retry delays:');
      for (int attempt = 1; attempt <= 5; attempt++) {
        final delay = gun.errorHandler.getRetryDelay(errorType, attempt);
        print('      Attempt $attempt: ${delay.inMilliseconds}ms');
      }
    }
  }
}

/// Additional demonstration of error handling in real Gun operations
Future<void> demonstrateRealOperationErrors(Gun gun) async {
  print('\n5. Demonstrating error handling in real operations...\n');
  
  try {
    // This will likely cause a storage error if the node doesn't exist
    final chain = gun.get('nonexistent/deep/path');
    final result = await chain.once();
    print('Got result: $result');
  } catch (e) {
    print('Caught exception in get operation: $e');
  }
  
  try {
    // This might cause validation errors with malformed data
    await gun.put({
      'invalid_key_with_null': null,
      'nested': {
        'very': {
          'deep': {
            'structure': 'that might cause issues'
          }
        }
      }
    });
  } catch (e) {
    print('Caught exception in put operation: $e');
  }
  
  // Show any errors that were captured by the error handler
  await Future.delayed(const Duration(milliseconds: 100));
  final finalStats = gun.errorHandler.errorStats;
  print('\nFinal error statistics after real operations:');
  finalStats.forEach((type, count) {
    print('  $type: $count errors');
  });
}

/// Demonstrate error recovery patterns
Future<void> demonstrateErrorRecovery() async {
  print('\n6. Demonstrating error recovery patterns...\n');
  
  final gun = Gun();
  
  // Subscribe to errors and implement recovery logic
  gun.errors.listen((error) async {
    print('🔧 Attempting recovery for ${error.type.name} error...');
    
    switch (error.type) {
      case GunErrorType.network:
        print('  → Network error: Will retry connection in 5 seconds');
        // In a real app, you might try to reconnect to peers here
        break;
        
      case GunErrorType.timeout:
        print('  → Timeout error: Will retry with longer timeout');
        // In a real app, you might increase timeout values
        break;
        
      case GunErrorType.unauthorized:
        print('  → Auth error: Will attempt to refresh credentials');
        // In a real app, you might trigger auth flow
        break;
        
      case GunErrorType.storage:
        print('  → Storage error: Will try alternative storage');
        // In a real app, you might switch storage adapters
        break;
        
      default:
        print('  → No automatic recovery available');
    }
  });
  
  // Simulate some recoverable errors
  gun.errorHandler.handleError(GunError.network('Connection lost'));
  await Future.delayed(const Duration(milliseconds: 100));
  
  gun.errorHandler.handleError(GunError.timeout('Query timed out'));
  await Future.delayed(const Duration(milliseconds: 100));
  
  await gun.close();
}
