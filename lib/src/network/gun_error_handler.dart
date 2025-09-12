import 'dart:async';
import '../utils/utils.dart';

/// Gun.js error types following DAM (Distributed Ammunition Machine) specification
enum GunErrorType {
  notFound,        // Data not found
  unauthorized,    // Authorization failed
  timeout,         // Request timeout
  validation,      // Data validation error
  conflict,        // CRDT conflict resolution error
  network,         // Network connectivity error
  storage,         // Storage adapter error
  malformed,       // Malformed message
  permission,      // Permission denied
  limit,           // Rate limit exceeded
  unknown,         // Unknown error
}

/// Gun.js compatible error message
class GunError {
  final GunErrorType type;
  final String message;
  final String? code;
  final String? nodeId;
  final String? field;
  final Map<String, dynamic>? context;
  final DateTime timestamp;
  final String errorId;

  GunError({
    required this.type,
    required this.message,
    this.code,
    this.nodeId,
    this.field,
    this.context,
    DateTime? timestamp,
    String? errorId,
  }) : timestamp = timestamp ?? DateTime.now(),
       errorId = errorId ?? Utils.randomString(8);

  /// Create error from Gun.js DAM message
  factory GunError.fromDAM(Map<String, dynamic> damMessage) {
    final damText = damMessage['dam'] as String? ?? 'Unknown error';
    final messageId = damMessage['@'] as String?;
    final ackId = damMessage['#'] as String?;
    final typeString = damMessage['type'] as String?;
    
    // Use explicit type if available, otherwise parse from message
    GunErrorType errorType;
    if (typeString != null) {
      errorType = GunErrorType.values.firstWhere(
        (e) => e.name == typeString,
        orElse: () => _parseErrorType(damText),
      );
    } else {
      errorType = _parseErrorType(damText);
    }
    
    return GunError(
      type: errorType,
      message: damText,
      code: damMessage['code'] as String? ?? _extractErrorCode(damText),
      nodeId: damMessage['node'] as String?,
      field: damMessage['field'] as String?,
      context: {
        if (messageId != null) 'messageId': messageId,
        if (ackId != null) 'ackId': ackId,
        ...?damMessage['context'] as Map<String, dynamic>?,
      },
      errorId: messageId ?? Utils.randomString(8),
    );
  }

  /// Convert to Gun.js DAM message format
  Map<String, dynamic> toDAM({String? originalMessageId}) {
    return {
      'dam': message,
      '@': errorId,
      if (originalMessageId != null) '#': originalMessageId,
      if (nodeId != null) 'node': nodeId,
      if (field != null) 'field': field,
      if (code != null) 'code': code,
      // Include error type for better round-trip conversion
      'type': type.name,
      if (context != null && context!.isNotEmpty) 'context': context,
    };
  }

  /// Create common Gun.js error types
  factory GunError.notFound(String nodeId, {String? field}) {
    return GunError(
      type: GunErrorType.notFound,
      message: field != null 
          ? 'Field "$field" not found in node "$nodeId"'
          : 'Node "$nodeId" not found',
      code: 'NOT_FOUND',
      nodeId: nodeId,
      field: field,
    );
  }

  factory GunError.unauthorized(String message, {String? nodeId}) {
    return GunError(
      type: GunErrorType.unauthorized,
      message: message,
      code: 'UNAUTHORIZED',
      nodeId: nodeId,
    );
  }

  factory GunError.timeout(String operation, {Duration? duration}) {
    return GunError(
      type: GunErrorType.timeout,
      message: 'Operation "$operation" timed out${duration != null ? ' after ${duration.inMilliseconds}ms' : ''}',
      code: 'TIMEOUT',
      context: duration != null ? {'timeoutMs': duration.inMilliseconds} : null,
    );
  }

  factory GunError.validation(String message, {String? nodeId, String? field}) {
    return GunError(
      type: GunErrorType.validation,
      message: 'Validation error: $message',
      code: 'VALIDATION_FAILED',
      nodeId: nodeId,
      field: field,
    );
  }

  factory GunError.conflict(String nodeId, String field, String message) {
    return GunError(
      type: GunErrorType.conflict,
      message: 'Conflict in node "$nodeId", field "$field": $message',
      code: 'CRDT_CONFLICT',
      nodeId: nodeId,
      field: field,
    );
  }

  factory GunError.network(String message, {String? url}) {
    return GunError(
      type: GunErrorType.network,
      message: 'Network error: $message',
      code: 'NETWORK_ERROR',
      context: url != null ? {'url': url} : null,
    );
  }

  factory GunError.storage(String message, {String? adapter}) {
    return GunError(
      type: GunErrorType.storage,
      message: 'Storage error: $message',
      code: 'STORAGE_ERROR',
      context: adapter != null ? {'adapter': adapter} : null,
    );
  }

  factory GunError.malformed(String message, {Map<String, dynamic>? messageData}) {
    return GunError(
      type: GunErrorType.malformed,
      message: 'Malformed message: $message',
      code: 'MALFORMED_MESSAGE',
      context: messageData,
    );
  }

  factory GunError.permission(String message, {String? nodeId, String? action}) {
    return GunError(
      type: GunErrorType.permission,
      message: 'Permission denied: $message',
      code: 'PERMISSION_DENIED',
      nodeId: nodeId,
      context: action != null ? {'action': action} : null,
    );
  }

  factory GunError.limit(String message, {int? limit, int? current}) {
    return GunError(
      type: GunErrorType.limit,
      message: 'Rate limit exceeded: $message',
      code: 'RATE_LIMIT_EXCEEDED',
      context: {
        if (limit != null) 'limit': limit,
        if (current != null) 'current': current,
      },
    );
  }

  /// Parse error type from DAM message text
  static GunErrorType _parseErrorType(String damText) {
    final text = damText.toLowerCase();
    
    if (text.contains('not found') || text.contains('404')) {
      return GunErrorType.notFound;
    } else if (text.contains('unauthorized') || text.contains('authentication') || text.contains('401') || text.contains('403')) {
      return GunErrorType.unauthorized;
    } else if (text.contains('timeout') || text.contains('408')) {
      return GunErrorType.timeout;
    } else if (text.contains('validation') || text.contains('invalid') || text.contains('400')) {
      return GunErrorType.validation;
    } else if (text.contains('conflict') || text.contains('409')) {
      return GunErrorType.conflict;
    } else if (text.contains('network') || text.contains('connection') || text.contains('502') || text.contains('503')) {
      return GunErrorType.network;
    } else if (text.contains('storage') || text.contains('database') || text.contains('500')) {
      return GunErrorType.storage;
    } else if (text.contains('malformed') || text.contains('parse')) {
      return GunErrorType.malformed;
    } else if (text.contains('permission') || text.contains('denied')) {
      return GunErrorType.permission;
    } else if (text.contains('limit') || text.contains('429')) {
      return GunErrorType.limit;
    } else {
      return GunErrorType.unknown;
    }
  }

  /// Extract error code from DAM message text
  static String? _extractErrorCode(String damText) {
    final codeRegex = RegExp(r'\b([A-Z_]+_ERROR|[A-Z_]+_FAILED|\d{3})\b');
    final match = codeRegex.firstMatch(damText);
    return match?.group(1);
  }

  @override
  String toString() {
    return 'GunError(${type.name}: $message${nodeId != null ? ' [node: $nodeId]' : ''}${field != null ? ' [field: $field]' : ''})';
  }

  /// Convert to JSON for serialization
  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'message': message,
      'code': code,
      'nodeId': nodeId,
      'field': field,
      'context': context,
      'timestamp': timestamp.toIso8601String(),
      'errorId': errorId,
    };
  }

  /// Create from JSON
  factory GunError.fromJson(Map<String, dynamic> json) {
    return GunError(
      type: GunErrorType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => GunErrorType.unknown,
      ),
      message: json['message'] as String,
      code: json['code'] as String?,
      nodeId: json['nodeId'] as String?,
      field: json['field'] as String?,
      context: json['context'] as Map<String, dynamic>?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      errorId: json['errorId'] as String,
    );
  }
}

/// Gun.js compatible error handler with DAM message support
class GunErrorHandler {
  final StreamController<GunError> _errorController = StreamController.broadcast();
  final Map<String, GunError> _errorHistory = {};
  final List<GunError> _recentErrors = [];
  final int _maxErrorHistory;
  final int _maxRecentErrors;
  
  GunErrorHandler({
    int maxHistory = 1000,
    int maxRecent = 100,
  }) : _maxErrorHistory = maxHistory,
       _maxRecentErrors = maxRecent;

  /// Stream of Gun errors
  Stream<GunError> get errors => _errorController.stream;

  /// Get recent errors (last 100)
  List<GunError> get recentErrors => List.unmodifiable(_recentErrors);

  /// Get error statistics
  Map<String, int> get errorStats {
    final stats = <String, int>{};
    for (final error in _recentErrors) {
      stats[error.type.name] = (stats[error.type.name] ?? 0) + 1;
    }
    return stats;
  }

  /// Handle a Gun error
  void handleError(GunError error) {
    // Add to history
    _errorHistory[error.errorId] = error;
    if (_errorHistory.length > _maxErrorHistory) {
      // Remove oldest entries
      final oldestKeys = _errorHistory.keys.take(_errorHistory.length - _maxErrorHistory);
      for (final key in oldestKeys) {
        _errorHistory.remove(key);
      }
    }

    // Add to recent errors
    _recentErrors.add(error);
    if (_recentErrors.length > _maxRecentErrors) {
      _recentErrors.removeAt(0);
    }

    // Emit error event
    _errorController.add(error);
  }

  /// Handle DAM message from Gun.js
  void handleDAM(Map<String, dynamic> damMessage) {
    final error = GunError.fromDAM(damMessage);
    handleError(error);
  }

  /// Create and handle error from exception
  void handleException(dynamic exception, String context, {String? nodeId, String? field}) {
    GunError error;

    if (exception is StateError) {
      error = GunError.validation(exception.message, nodeId: nodeId, field: field);
    } else if (exception is TimeoutException) {
      error = GunError.timeout(context, duration: exception.duration);
    } else if (exception is FormatException) {
      error = GunError.malformed(exception.message);
    } else if (exception is UnimplementedError) {
      error = GunError(
        type: GunErrorType.unknown,
        message: 'Feature not implemented: ${exception.message}',
        code: 'NOT_IMPLEMENTED',
        context: {'operation': context},
      );
    } else {
      error = GunError(
        type: GunErrorType.unknown,
        message: 'Unexpected error in $context: ${exception.toString()}',
        code: 'UNEXPECTED_ERROR',
        nodeId: nodeId,
        field: field,
        context: {'exception': exception.runtimeType.toString()},
      );
    }

    handleError(error);
  }

  /// Send DAM message for error
  Future<void> sendDAM(GunError error, Function(Map<String, dynamic>) sendMessage, {String? originalMessageId}) async {
    final damMessage = error.toDAM(originalMessageId: originalMessageId);
    await sendMessage(damMessage);
  }

  /// Get error by ID
  GunError? getError(String errorId) {
    return _errorHistory[errorId];
  }

  /// Check if error type should be retried
  bool shouldRetry(GunErrorType errorType) {
    switch (errorType) {
      case GunErrorType.timeout:
      case GunErrorType.network:
        return true;
      case GunErrorType.unauthorized:
      case GunErrorType.validation:
      case GunErrorType.malformed:
      case GunErrorType.permission:
        return false;
      case GunErrorType.notFound:
      case GunErrorType.conflict:
      case GunErrorType.storage:
      case GunErrorType.limit:
      case GunErrorType.unknown:
        return false; // Could be configurable
    }
  }

  /// Get retry delay for error type
  Duration getRetryDelay(GunErrorType errorType, int attemptNumber) {
    if (!shouldRetry(errorType)) {
      return Duration.zero;
    }

    switch (errorType) {
      case GunErrorType.timeout:
        // Exponential backoff for timeouts
        return Duration(milliseconds: 1000 * (1 << (attemptNumber - 1).clamp(0, 5)));
      case GunErrorType.network:
        // Linear backoff for network errors
        return Duration(milliseconds: 500 * attemptNumber.clamp(1, 10));
      default:
        return Duration(seconds: 1);
    }
  }

  /// Clear error history
  void clear() {
    _errorHistory.clear();
    _recentErrors.clear();
  }

  /// Close the error handler
  Future<void> close() async {
    await _errorController.close();
    clear();
  }

  /// Create error handler with custom configuration
  factory GunErrorHandler.configure({
    int maxHistory = 1000,
    int maxRecent = 100,
  }) {
    return GunErrorHandler(
      maxHistory: maxHistory,
      maxRecent: maxRecent,
    );
  }
}

/// Extension methods for Gun classes to handle errors
extension GunErrorHandling on Object {
  /// Execute operation with error handling
  Future<T> withErrorHandling<T>(
    Future<T> Function() operation,
    GunErrorHandler errorHandler, {
    String? context,
    String? nodeId,
    String? field,
  }) async {
    try {
      return await operation();
    } catch (e) {
      errorHandler.handleException(
        e,
        context ?? 'operation',
        nodeId: nodeId,
        field: field,
      );
      rethrow;
    }
  }
}
