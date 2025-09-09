import 'dart:io';
import '../lib/src/network/gun_error_handler.dart';
import '../lib/src/utils/utils.dart';

Future<void> main() async {
  print('=== Gun Dart DAM Error Handling Example ===');
  
  // Create error handler
  final errorHandler = GunErrorHandler();
  
  // Subscribe to error events
  errorHandler.errors.listen((error) {
    print('\n🚨 Gun Error Detected:');
    print('  Type: ${error.type.name}');
    print('  Message: ${error.message}');
    print('  Code: ${error.code}');
    if (error.nodeId != null) print('  Node: ${error.nodeId}');
    if (error.field != null) print('  Field: ${error.field}');
    print('  Timestamp: ${error.timestamp}');
    print('  Error ID: ${error.errorId}');
    
    // Check if error should be retried
    if (errorHandler.shouldRetry(error.type)) {
      final delay = errorHandler.getRetryDelay(error.type, 1);
      print('  🔄 Retry recommended after ${delay.inMilliseconds}ms');
    } else {
      print('  ❌ Error is not retryable');
    }
    print('');
  });
  
  print('\n1. Creating and handling different error types...\n');
  
  // Not found error
  final notFound = GunError.notFound('users/alice', field: 'profile');
  errorHandler.handleError(notFound);
  
  await Future.delayed(const Duration(milliseconds: 100));
  
  // Unauthorized error
  final unauthorized = GunError.unauthorized('Invalid API key');
  errorHandler.handleError(unauthorized);
  
  await Future.delayed(const Duration(milliseconds: 100));
  
  // Timeout error
  final timeout = GunError.timeout('database query', duration: const Duration(seconds: 5));
  errorHandler.handleError(timeout);
  
  await Future.delayed(const Duration(milliseconds: 100));
  
  // Network error
  final network = GunError.network('Connection refused', url: 'ws://localhost:8765');
  errorHandler.handleError(network);
  
  await Future.delayed(const Duration(milliseconds: 100));
  
  // CRDT conflict error
  final conflict = GunError.conflict('posts/123', 'content', 'Concurrent edit detected');
  errorHandler.handleError(conflict);
  
  await Future.delayed(const Duration(milliseconds: 100));
  
  print('\n2. Processing DAM messages from Gun.js peers...\n');
  
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
    errorHandler.handleDAM(damMessage);
    await Future.delayed(const Duration(milliseconds: 200));
  }
  
  print('\n3. Error Statistics...\n');
  
  final stats = errorHandler.errorStats;
  final recentErrors = errorHandler.recentErrors;
  
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
  
  print('\n4. Testing retry logic for different error types...\n');
  
  final errorTypes = [
    GunErrorType.timeout,
    GunErrorType.network,
    GunErrorType.unauthorized,
    GunErrorType.validation,
    GunErrorType.notFound,
  ];
  
  for (final errorType in errorTypes) {
    final shouldRetry = errorHandler.shouldRetry(errorType);
    print('  ${errorType.name}:');
    print('    Should retry: $shouldRetry');
    
    if (shouldRetry) {
      print('    Retry delays:');
      for (int attempt = 1; attempt <= 5; attempt++) {
        final delay = errorHandler.getRetryDelay(errorType, attempt);
        print('      Attempt $attempt: ${delay.inMilliseconds}ms');
      }
    }
    print('');
  }
  
  print('5. Testing DAM message conversion...\n');
  
  // Test bidirectional DAM conversion
  final originalError = GunError(
    type: GunErrorType.unauthorized,
    message: 'Authentication required',
    code: 'AUTH_REQUIRED',
    nodeId: 'users/alice',
    errorId: 'HyETBKILb',
  );
  
  final damMessage = originalError.toDAM(originalMessageId: 'HyETBKILf');
  print('Original error converted to DAM:');
  print('  ${damMessage}');
  
  final recreatedError = GunError.fromDAM(damMessage);
  print('DAM message converted back to error:');
  print('  Type: ${recreatedError.type.name}');
  print('  Message: ${recreatedError.message}');
  print('  Code: ${recreatedError.code}');
  print('  Node ID: ${recreatedError.nodeId}');
  print('  Error ID: ${recreatedError.errorId}');
  
  // Verify round-trip integrity
  final isRoundTripValid = originalError.type == recreatedError.type &&
                           originalError.message == recreatedError.message &&
                           originalError.code == recreatedError.code &&
                           originalError.nodeId == recreatedError.nodeId &&
                           originalError.errorId == recreatedError.errorId;
  
  print('  Round-trip conversion: ${isRoundTripValid ? '✅ Success' : '❌ Failed'}');
  
  print('\n6. Testing error sending simulation...\n');
  
  final sentMessages = <Map<String, dynamic>>[];
  
  Future<void> mockSender(Map<String, dynamic> message) async {
    sentMessages.add(message);
    print('  📤 Sent DAM message: ${message['dam']}');
  }
  
  final sendError = GunError.notFound('test/node');
  await errorHandler.sendDAM(sendError, mockSender, originalMessageId: 'test123');
  
  print('  Total messages sent: ${sentMessages.length}');
  print('  Message format valid: ${sentMessages.first.containsKey('dam') && sentMessages.first.containsKey('@') && sentMessages.first.containsKey('#')}');
  
  // Clean up
  await errorHandler.close();
  
  print('\n=== Example completed successfully! ===');
}
