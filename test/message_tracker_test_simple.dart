import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:gun_dart/src/network/message_tracker.dart';

void main() {
  group('Message Tracker Tests', () {
    test('should track pending messages correctly', () async {
      final tracker = MessageTracker(ackTimeout: Duration(seconds: 1));
      
      expect(tracker.pendingCount, equals(0));
      expect(tracker.pendingMessageIds, isEmpty);
      
      tracker.dispose();
    });
    
    test('should handle acknowledgments', () {
      final tracker = MessageTracker();
      
      // Test handling unknown acknowledgment
      final handled = tracker.handleAck('unknown-msg', 'ack');
      expect(handled, isFalse);
      
      tracker.dispose();
    });
    
    test('should handle errors', () {
      final tracker = MessageTracker();
      
      // Test handling unknown error
      final handled = tracker.handleError('unknown-msg', 'error');
      expect(handled, isFalse);
      
      tracker.dispose();
    });
    
    test('should track message history', () {
      final tracker = MessageTracker();
      
      expect(tracker.hasSeenMessage('new-msg'), isFalse);
      expect(tracker.hasSeenMessage('other-msg'), isFalse);
      
      tracker.dispose();
    });
    
    test('should provide statistics', () {
      final tracker = MessageTracker();
      final stats = tracker.stats;
      
      expect(stats.pendingMessages, equals(0));
      expect(stats.historySize, equals(0));
      expect(stats.averagePendingTime, equals(Duration.zero));
      expect(stats.oldestPendingTime, equals(Duration.zero));
      
      tracker.dispose();
    });
    
    test('should provide meaningful string representations', () {
      final tracker = MessageTracker();
      final stats = tracker.stats;
      final statsString = stats.toString();
      
      expect(statsString, contains('pending:'));
      expect(statsString, contains('history:'));
      expect(statsString, contains('avgPending:'));
      expect(statsString, contains('oldest:'));
      
      final timeoutException = MessageTimeoutException('Test timeout');
      expect(timeoutException.toString(), contains('Test timeout'));
      
      final errorException = MessageErrorException('Test error', 'msg-123');
      expect(errorException.toString(), contains('Test error'));
      expect(errorException.toString(), contains('msg-123'));
      
      final cancelException = MessageCancelledException('Test cancel');
      expect(cancelException.toString(), contains('Test cancel'));
      
      tracker.dispose();
    });
    
    test('should handle disposal correctly', () {
      final tracker = MessageTracker();
      
      expect(tracker.isDisposed, isFalse);
      
      tracker.dispose();
      expect(tracker.isDisposed, isTrue);
      
      // Should be safe to call dispose multiple times
      tracker.dispose();
      expect(tracker.isDisposed, isTrue);
    });
  });
}
