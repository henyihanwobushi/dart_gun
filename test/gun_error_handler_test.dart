import 'package:flutter_test/flutter_test.dart';
import '../lib/src/network/gun_error_handler.dart';
import '../lib/src/utils/utils.dart';

void main() {
  group('GunError', () {
    test('should create error from DAM message', () {
      final damMessage = {
        'dam': 'Node "test-node" not found',
        '@': 'msg123',
        '#': 'ack456',
        'node': 'test-node',
      };
      
      final error = GunError.fromDAM(damMessage);
      
      expect(error.type, equals(GunErrorType.notFound));
      expect(error.message, equals('Node "test-node" not found'));
      expect(error.nodeId, equals('test-node'));
      expect(error.context?['messageId'], equals('msg123'));
      expect(error.context?['ackId'], equals('ack456'));
    });
    
    test('should convert to DAM message format', () {
      final error = GunError.notFound('test-node', field: 'name');
      final damMessage = error.toDAM(originalMessageId: 'orig123');
      
      expect(damMessage['dam'], contains('test-node'));
      expect(damMessage['dam'], contains('name'));
      expect(damMessage['@'], isNotNull);
      expect(damMessage['#'], equals('orig123'));
      expect(damMessage['node'], equals('test-node'));
      expect(damMessage['field'], equals('name'));
    });
    
    test('should parse error types correctly', () {
      final testCases = [
        ('Node not found', GunErrorType.notFound),
        ('Unauthorized access', GunErrorType.unauthorized),
        ('Request timeout after 5000ms', GunErrorType.timeout),
        ('Validation failed: invalid data', GunErrorType.validation),
        ('CRDT conflict detected', GunErrorType.conflict),
        ('Network connection failed', GunErrorType.network),
        ('Storage database error', GunErrorType.storage),
        ('Malformed JSON message', GunErrorType.malformed),
        ('Permission denied for user', GunErrorType.permission),
        ('Rate limit exceeded: 100 req/min', GunErrorType.limit),
        ('Unknown error occurred', GunErrorType.unknown),
      ];
      
      for (final testCase in testCases) {
        final damMessage = {'dam': testCase.$1};
        final error = GunError.fromDAM(damMessage);
        expect(error.type, equals(testCase.$2), 
          reason: 'Failed for message: "${testCase.$1}"');
      }
    });
    
    test('should create specific error types', () {
      final notFound = GunError.notFound('node1', field: 'name');
      expect(notFound.type, equals(GunErrorType.notFound));
      expect(notFound.code, equals('NOT_FOUND'));
      expect(notFound.nodeId, equals('node1'));
      expect(notFound.field, equals('name'));
      
      final unauthorized = GunError.unauthorized('Invalid token');
      expect(unauthorized.type, equals(GunErrorType.unauthorized));
      expect(unauthorized.code, equals('UNAUTHORIZED'));
      
      final timeout = GunError.timeout('get operation', 
        duration: const Duration(seconds: 5));
      expect(timeout.type, equals(GunErrorType.timeout));
      expect(timeout.code, equals('TIMEOUT'));
      expect(timeout.context?['timeoutMs'], equals(5000));
    });
    
    test('should serialize to/from JSON', () {
      final originalError = GunError.conflict('node1', 'field1', 'Version mismatch');
      final json = originalError.toJson();
      final deserializedError = GunError.fromJson(json);
      
      expect(deserializedError.type, equals(originalError.type));
      expect(deserializedError.message, equals(originalError.message));
      expect(deserializedError.code, equals(originalError.code));
      expect(deserializedError.nodeId, equals(originalError.nodeId));
      expect(deserializedError.field, equals(originalError.field));
    });
  });
  
  group('GunErrorHandler', () {
    late GunErrorHandler errorHandler;
    
    setUp(() {
      errorHandler = GunErrorHandler();
    });
    
    tearDown(() async {
      await errorHandler.close();
    });
    
    test('should handle and track errors', () async {
      final error = GunError.notFound('test-node');
      
      // Listen for error events
      final errorEvents = <GunError>[];
      final subscription = errorHandler.errors.listen((e) => errorEvents.add(e));
      
      errorHandler.handleError(error);
      
      await Future.delayed(const Duration(milliseconds: 10));
      
      expect(errorEvents.length, equals(1));
      expect(errorEvents.first.errorId, equals(error.errorId));
      expect(errorHandler.recentErrors.length, equals(1));
      expect(errorHandler.getError(error.errorId), equals(error));
      
      await subscription.cancel();
    });
    
    test('should handle DAM messages', () async {
      final damMessage = {
        'dam': 'Network timeout occurred',
        '@': 'msg789',
        '#': 'ack321',
      };
      
      final errorEvents = <GunError>[];
      final subscription = errorHandler.errors.listen((e) => errorEvents.add(e));
      
      errorHandler.handleDAM(damMessage);
      
      await Future.delayed(const Duration(milliseconds: 10));
      
      expect(errorEvents.length, equals(1));
      expect(errorEvents.first.type, equals(GunErrorType.timeout));
      expect(errorEvents.first.message, equals('Network timeout occurred'));
      
      await subscription.cancel();
    });
    
    test('should handle exceptions', () async {
      final errorEvents = <GunError>[];
      final subscription = errorHandler.errors.listen((e) => errorEvents.add(e));
      
      errorHandler.handleException(
        StateError('Invalid state'),
        'test operation',
        nodeId: 'test-node',
      );
      
      await Future.delayed(const Duration(milliseconds: 10));
      
      expect(errorEvents.length, equals(1));
      expect(errorEvents.first.type, equals(GunErrorType.validation));
      expect(errorEvents.first.nodeId, equals('test-node'));
      
      await subscription.cancel();
    });
    
    test('should determine retry eligibility', () {
      expect(errorHandler.shouldRetry(GunErrorType.timeout), isTrue);
      expect(errorHandler.shouldRetry(GunErrorType.network), isTrue);
      expect(errorHandler.shouldRetry(GunErrorType.unauthorized), isFalse);
      expect(errorHandler.shouldRetry(GunErrorType.validation), isFalse);
      expect(errorHandler.shouldRetry(GunErrorType.malformed), isFalse);
    });
    
    test('should calculate retry delays', () {
      final timeoutDelay = errorHandler.getRetryDelay(GunErrorType.timeout, 3);
      expect(timeoutDelay.inMilliseconds, equals(4000)); // 1000 * 2^2
      
      final networkDelay = errorHandler.getRetryDelay(GunErrorType.network, 2);
      expect(networkDelay.inMilliseconds, equals(1000)); // 500 * 2
      
      final noRetryDelay = errorHandler.getRetryDelay(GunErrorType.validation, 1);
      expect(noRetryDelay, equals(Duration.zero));
    });
    
    test('should provide error statistics', () async {
      // Add different types of errors
      errorHandler.handleError(GunError.notFound('node1'));
      errorHandler.handleError(GunError.notFound('node2'));
      errorHandler.handleError(GunError.timeout('op1'));
      errorHandler.handleError(GunError.network('connection failed'));
      
      await Future.delayed(const Duration(milliseconds: 10));
      
      final stats = errorHandler.errorStats;
      expect(stats['notFound'], equals(2));
      expect(stats['timeout'], equals(1));
      expect(stats['network'], equals(1));
      expect(stats.keys.length, equals(3));
    });
    
    test('should send DAM messages', () async {
      final sentMessages = <Map<String, dynamic>>[];
      
      Future<void> mockSender(Map<String, dynamic> message) async {
        sentMessages.add(message);
      }
      
      final error = GunError.notFound('test-node');
      await errorHandler.sendDAM(error, mockSender, originalMessageId: 'orig123');
      
      expect(sentMessages.length, equals(1));
      expect(sentMessages.first['dam'], contains('test-node'));
      expect(sentMessages.first['#'], equals('orig123'));
      expect(sentMessages.first['@'], isNotNull);
    });
    
    test('should limit error history size', () async {
      final handler = GunErrorHandler.configure(maxHistory: 5, maxRecent: 3);
      
      // Add more errors than the limit
      for (int i = 0; i < 10; i++) {
        handler.handleError(GunError.notFound('node$i'));
      }
      
      await Future.delayed(const Duration(milliseconds: 10));
      
      expect(handler.recentErrors.length, equals(3));
      
      await handler.close();
    });
    
    test('should clear error history', () async {
      errorHandler.handleError(GunError.notFound('node1'));
      errorHandler.handleError(GunError.timeout('op1'));
      
      await Future.delayed(const Duration(milliseconds: 10));
      
      expect(errorHandler.recentErrors.length, equals(2));
      
      errorHandler.clear();
      
      expect(errorHandler.recentErrors.length, equals(0));
      expect(errorHandler.errorStats.isEmpty, isTrue);
    });
  });
  
  group('GunErrorHandling extension', () {
    late GunErrorHandler errorHandler;
    
    setUp(() {
      errorHandler = GunErrorHandler();
    });
    
    tearDown(() async {
      await errorHandler.close();
    });
    
    test('should wrap operation with error handling', () async {
      final errorEvents = <GunError>[];
      final subscription = errorHandler.errors.listen((e) => errorEvents.add(e));
      
      try {
        await Object().withErrorHandling(
          () async {
            await Future.delayed(const Duration(milliseconds: 10));
            throw StateError('Test error');
          },
          errorHandler,
          context: 'test operation',
          nodeId: 'test-node',
        );
      } catch (e) {
        expect(e, isA<StateError>());
      }
      
      await Future.delayed(const Duration(milliseconds: 10));
      
      expect(errorEvents.length, equals(1));
      expect(errorEvents.first.type, equals(GunErrorType.validation));
      expect(errorEvents.first.nodeId, equals('test-node'));
      
      await subscription.cancel();
    });
    
    test('should handle successful operations', () async {
      final result = await Object().withErrorHandling(
        () async {
          await Future.delayed(const Duration(milliseconds: 10));
          return 'success';
        },
        errorHandler,
        context: 'test operation',
      );
      
      expect(result, equals('success'));
    });
  });
  
  group('DAM Message Compatibility', () {
    test('should handle Gun.js compatible DAM messages', () {
      final gunJsDAM = {
        'dam': '"~12345" at "users" not found',
        '@': 'HyETBKILb',
        '#': 'HyETBKILf',
        'err': 404,
      };
      
      final error = GunError.fromDAM(gunJsDAM);
      
      expect(error.type, equals(GunErrorType.notFound));
      expect(error.message, equals('"~12345" at "users" not found'));
      expect(error.errorId, equals('HyETBKILb'));
      expect(error.context?['ackId'], equals('HyETBKILf'));
    });
    
    test('should generate Gun.js compatible DAM format', () {
      final error = GunError(
        type: GunErrorType.unauthorized,
        message: 'Authentication required',
        code: 'AUTH_REQUIRED',
        nodeId: 'users/alice',
        errorId: 'HyETBKILb',
      );
      
      final damMessage = error.toDAM(originalMessageId: 'HyETBKILf');
      
      expect(damMessage['dam'], equals('Authentication required'));
      expect(damMessage['@'], equals('HyETBKILb'));
      expect(damMessage['#'], equals('HyETBKILf'));
      expect(damMessage['node'], equals('users/alice'));
      expect(damMessage['code'], equals('AUTH_REQUIRED'));
    });
    
    test('should handle various DAM message formats', () {
      final testMessages = [
        {'dam': 'Error'},
        {'dam': 'Error', '@': 'msg1'},
        {'dam': 'Error', '@': 'msg2', '#': 'ack1'},
        {'dam': 'Error', '@': 'msg3', '#': 'ack2', 'node': 'test'},
        {'dam': 'Timeout after 5000ms', 'code': 'TIMEOUT'},
      ];
      
      for (final message in testMessages) {
        final error = GunError.fromDAM(message);
        expect(error.type, isNotNull);
        expect(error.message, equals(message['dam']));
        
        final recreatedDAM = error.toDAM();
        expect(recreatedDAM['dam'], equals(message['dam']));
        expect(recreatedDAM['@'], isNotNull);
      }
    });
  });
  
  group('Error Recovery and Retry Logic', () {
    late GunErrorHandler errorHandler;
    
    setUp(() {
      errorHandler = GunErrorHandler();
    });
    
    tearDown(() async {
      await errorHandler.close();
    });
    
    test('should implement exponential backoff for timeouts', () {
      final delays = [1, 2, 3, 4, 5, 6].map(
        (attempt) => errorHandler.getRetryDelay(GunErrorType.timeout, attempt),
      ).toList();
      
      expect(delays[0].inMilliseconds, equals(1000));
      expect(delays[1].inMilliseconds, equals(2000));
      expect(delays[2].inMilliseconds, equals(4000));
      expect(delays[3].inMilliseconds, equals(8000));
      expect(delays[4].inMilliseconds, equals(16000));
      expect(delays[5].inMilliseconds, equals(32000)); // Max at 2^5
    });
    
    test('should implement linear backoff for network errors', () {
      final delays = [1, 2, 3, 4, 5, 10, 15].map(
        (attempt) => errorHandler.getRetryDelay(GunErrorType.network, attempt),
      ).toList();
      
      expect(delays[0].inMilliseconds, equals(500));
      expect(delays[1].inMilliseconds, equals(1000));
      expect(delays[2].inMilliseconds, equals(1500));
      expect(delays[3].inMilliseconds, equals(2000));
      expect(delays[4].inMilliseconds, equals(2500));
      expect(delays[5].inMilliseconds, equals(5000)); // Max at 10 * 500
      expect(delays[6].inMilliseconds, equals(5000)); // Capped at max
    });
    
    test('should not retry non-retryable errors', () {
      final nonRetryableTypes = [
        GunErrorType.unauthorized,
        GunErrorType.validation,
        GunErrorType.malformed,
        GunErrorType.permission,
      ];
      
      for (final errorType in nonRetryableTypes) {
        expect(errorHandler.shouldRetry(errorType), isFalse);
        expect(errorHandler.getRetryDelay(errorType, 1), equals(Duration.zero));
      }
    });
  });
  
  group('Performance and Memory Management', () {
    test('should limit memory usage with large error volumes', () async {
      final handler = GunErrorHandler();
      
      // Generate many errors to test memory limits
      for (int i = 0; i < 2000; i++) {
        handler.handleError(GunError.notFound('node$i'));
      }
      
      await Future.delayed(const Duration(milliseconds: 50));
      
      // Should not exceed the configured limits
      expect(handler.recentErrors.length, lessThanOrEqualTo(100));
      
      await handler.close();
    });
    
    test('should clean up properly on close', () async {
      final handler = GunErrorHandler();
      
      handler.handleError(GunError.notFound('node1'));
      handler.handleError(GunError.timeout('op1'));
      
      await handler.close();
      
      // After closing, should be clean
      expect(handler.recentErrors.length, equals(0));
      expect(handler.errorStats.isEmpty, isTrue);
    });
  });
}
