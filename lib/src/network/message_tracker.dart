import 'dart:async';
import 'dart:collection';

/// Tracks Gun.js wire protocol messages and their acknowledgments
/// 
/// Handles message ID generation, acknowledgment tracking, and timeout handling
/// for reliable message delivery in Gun.js compatible protocol.
class MessageTracker {
  final Map<String, PendingMessage> _pendingMessages = {};
  final Queue<String> _messageHistory = Queue<String>();
  final Duration _ackTimeout;
  final int _maxHistorySize;
  Timer? _cleanupTimer;
  bool _disposed = false;
  
  MessageTracker({
    Duration ackTimeout = const Duration(seconds: 30),
    int maxHistorySize = 1000,
  }) : _ackTimeout = ackTimeout,
       _maxHistorySize = maxHistorySize {
    // Start cleanup timer to remove expired messages
    _cleanupTimer = Timer.periodic(Duration(seconds: 10), _cleanupExpiredMessages);
  }
  
  /// Send a message with tracking
  /// 
  /// Returns the message ID that can be used to track acknowledgments
  Future<String> sendMessage(
    Map<String, dynamic> message,
    Future<void> Function(Map<String, dynamic>) sender, {
    Duration? timeout,
  }) async {
    final messageId = message['@'] as String;
    final completer = Completer<String>();
    final timeoutDuration = timeout ?? _ackTimeout;
    
    // Create pending message entry
    final pendingMessage = PendingMessage(
      messageId: messageId,
      message: message,
      completer: completer,
      sentAt: DateTime.now(),
      timeout: timeoutDuration,
    );
    
    _pendingMessages[messageId] = pendingMessage;
    _addToHistory(messageId);
    
    // Set up timeout
    Timer(timeoutDuration, () {
      if (_pendingMessages.containsKey(messageId)) {
        final pending = _pendingMessages.remove(messageId)!;
        if (!pending.completer.isCompleted) {
          pending.completer.completeError(
            MessageTimeoutException('Message $messageId timed out after ${timeoutDuration.inSeconds}s')
          );
        }
      }
    });
    
    // Send the message
    try {
      await sender(message);
    } catch (e) {
      _pendingMessages.remove(messageId);
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
      rethrow;
    }
    
    return messageId;
  }
  
  /// Handle incoming acknowledgment
  /// 
  /// Returns true if the acknowledgment was handled, false if no pending message was found
  bool handleAck(String messageId, String ackId, {dynamic result}) {
    final pendingMessage = _pendingMessages.remove(messageId);
    if (pendingMessage == null) {
      return false;
    }
    
    if (!pendingMessage.completer.isCompleted) {
      pendingMessage.completer.complete(ackId);
    }
    
    return true;
  }
  
  /// Handle incoming error (DAM) message
  /// 
  /// Returns true if the error was handled, false if no pending message was found  
  bool handleError(String messageId, String errorMessage) {
    final pendingMessage = _pendingMessages.remove(messageId);
    if (pendingMessage == null) {
      return false;
    }
    
    if (!pendingMessage.completer.isCompleted) {
      pendingMessage.completer.completeError(
        MessageErrorException(errorMessage, messageId)
      );
    }
    
    return true;
  }
  
  /// Check if we've seen this message before (for deduplication)
  bool hasSeenMessage(String messageId) {
    return _messageHistory.contains(messageId);
  }
  
  /// Get pending message count
  int get pendingCount => _pendingMessages.length;
  
  /// Get list of pending message IDs
  List<String> get pendingMessageIds => _pendingMessages.keys.toList();
  
  /// Get statistics about message tracking
  MessageTrackerStats get stats {
    final now = DateTime.now();
    var totalPendingTime = Duration.zero;
    var oldestPendingTime = Duration.zero;
    
    if (_pendingMessages.isNotEmpty) {
      for (final pending in _pendingMessages.values) {
        final pendingTime = now.difference(pending.sentAt);
        totalPendingTime += pendingTime;
        
        if (oldestPendingTime < pendingTime) {
          oldestPendingTime = pendingTime;
        }
      }
    }
    
    return MessageTrackerStats(
      pendingMessages: _pendingMessages.length,
      historySize: _messageHistory.length,
      averagePendingTime: _pendingMessages.isNotEmpty 
          ? totalPendingTime ~/ _pendingMessages.length
          : Duration.zero,
      oldestPendingTime: oldestPendingTime,
    );
  }
  
  /// Clean up expired messages and trim history
  void _cleanupExpiredMessages(Timer timer) {
    final now = DateTime.now();
    final expiredIds = <String>[];
    
    // Find expired messages
    for (final entry in _pendingMessages.entries) {
      final pending = entry.value;
      final age = now.difference(pending.sentAt);
      
      if (age > pending.timeout) {
        expiredIds.add(entry.key);
      }
    }
    
    // Remove expired messages
    for (final id in expiredIds) {
      final pending = _pendingMessages.remove(id);
      if (pending != null && !pending.completer.isCompleted) {
        pending.completer.completeError(
          MessageTimeoutException('Message $id expired during cleanup')
        );
      }
    }
    
    // Trim message history
    while (_messageHistory.length > _maxHistorySize) {
      _messageHistory.removeFirst();
    }
  }
  
  /// Add message ID to history for deduplication
  void _addToHistory(String messageId) {
    _messageHistory.add(messageId);
    
    // Keep history size reasonable
    while (_messageHistory.length > _maxHistorySize) {
      _messageHistory.removeFirst();
    }
  }
  
  /// Dispose resources
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    
    _cleanupTimer?.cancel();
    
    // Complete all pending messages with cancellation
    for (final pending in _pendingMessages.values) {
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(
          MessageCancelledException('Message tracker disposed')
        );
      }
    }
    
    _pendingMessages.clear();
    _messageHistory.clear();
  }
  
  /// Check if this tracker has been disposed
  bool get isDisposed => _disposed;
}

/// Represents a pending message awaiting acknowledgment
class PendingMessage {
  final String messageId;
  final Map<String, dynamic> message;
  final Completer<String> completer;
  final DateTime sentAt;
  final Duration timeout;
  
  PendingMessage({
    required this.messageId,
    required this.message,
    required this.completer,
    required this.sentAt,
    required this.timeout,
  });
}

/// Statistics about message tracker performance
class MessageTrackerStats {
  final int pendingMessages;
  final int historySize;
  final Duration averagePendingTime;
  final Duration oldestPendingTime;
  
  const MessageTrackerStats({
    required this.pendingMessages,
    required this.historySize,
    required this.averagePendingTime,
    required this.oldestPendingTime,
  });
  
  @override
  String toString() => 'MessageTrackerStats('
      'pending: $pendingMessages, '
      'history: $historySize, '
      'avgPending: ${averagePendingTime.inSeconds}s, '
      'oldest: ${oldestPendingTime.inSeconds}s)';
}

/// Exception thrown when a message times out
class MessageTimeoutException implements Exception {
  final String message;
  
  const MessageTimeoutException(this.message);
  
  @override
  String toString() => 'MessageTimeoutException: $message';
}

/// Exception thrown when a message receives an error response
class MessageErrorException implements Exception {
  final String errorMessage;
  final String messageId;
  
  const MessageErrorException(this.errorMessage, this.messageId);
  
  @override
  String toString() => 'MessageErrorException: $errorMessage (message: $messageId)';
}

/// Exception thrown when message tracker is cancelled/disposed
class MessageCancelledException implements Exception {
  final String message;
  
  const MessageCancelledException(this.message);
  
  @override
  String toString() => 'MessageCancelledException: $message';
}
