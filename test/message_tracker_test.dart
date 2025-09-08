import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:gun_dart/src/network/message_tracker.dart';

void main() {
  group('Message Tracker Tests', () {
    
    test('should track pending messages', () async {
      final tracker = MessageTracker(ackTimeout: Duration(seconds: 1));
      final message = {'@': 'test-123', 'data': 'test'};
      final completer = Completer<void>();
      
      final future = tracker.sendMessage(
        message,
        (msg) async {
          expect(msg, equals(message));
          completer.complete();
        },
      );
      
      expect(tracker.pendingCount, equals(1));
      expect(tracker.pendingMessageIds, contains('test-123'));
      
      await completer.future;
      tracker.dispose();
    });
    
    test('should handle acknowledgments', () async {
      final tracker = MessageTracker(ackTimeout: Duration(seconds: 1));
      final message = {'@': 'ack-test', 'data': 'test'};
      
      final future = tracker.sendMessage(
        message,
        (msg) async {
          // Simulate receiving acknowledgment
          Timer.run(() {
            tracker.handleAck('ack-test', 'ack-response');
          });
        },
      );
      
      final messageId = await future;
      expect(messageId, equals('ack-test'));
      
      // Wait a bit for async processing
      await Future.delayed(Duration(milliseconds: 10));
      
      expect(tracker.pendingCount, equals(0));
      tracker.dispose();
    });
    
    test('should handle errors', () async {
      final message = {'@': 'error-test', 'data': 'test'};
      
      try {
        await tracker.sendMessage(
          message,
          (msg) async {
            // Simulate receiving error
            Timer.run(() {
              tracker.handleError('error-test', 'Something went wrong');
            });
          },
        );
        fail('Expected MessageErrorException');
      } catch (e) {
        expect(e, isA<MessageErrorException>());
      }
    });
    
    test('should timeout messages', () async {
      final message = {'@': 'timeout-test', 'data': 'test'};
      
      try {
        await tracker.sendMessage(
          message,
          (msg) async {
            // Don't send acknowledgment - let it timeout
          },
          timeout: Duration(milliseconds: 100),
        );
        fail('Expected MessageTimeoutException');
      } catch (e) {
        expect(e, isA<MessageTimeoutException>());
      }
    });
    
    test('should track message history', () async {
      expect(tracker.hasSeenMessage('new-msg'), isFalse);
      
      final message = {'@': 'history-test', 'data': 'test'};
      await tracker.sendMessage(
        message,
        (msg) async {
          Timer.run(() {
            tracker.handleAck('history-test', 'ack');
          });
        },
      );
      
      await Future.delayed(Duration(milliseconds: 10));
      
      expect(tracker.hasSeenMessage('history-test'), isTrue);
      expect(tracker.hasSeenMessage('other-msg'), isFalse);
    });
    
    test('should provide statistics', () async {
      final stats = tracker.stats;
      
      expect(stats.pendingMessages, equals(0));
      expect(stats.historySize, equals(0));
      expect(stats.averagePendingTime, equals(Duration.zero));
      expect(stats.oldestPendingTime, equals(Duration.zero));
    });
    
    test('should handle message history limit', () async {
      // Send more messages than the history limit
      for (int i = 0; i < 15; i++) {
        final message = {'@': 'msg-$i', 'data': 'test'};
        await tracker.sendMessage(
          message,
          (msg) async {
            Timer.run(() {
              tracker.handleAck('msg-$i', 'ack-$i');
            });
          },
        );
        await Future.delayed(Duration(milliseconds: 5));
      }
      
      // History should be limited
      final stats = tracker.stats;
      expect(stats.historySize, lessThanOrEqualTo(10));
      
      // Recent messages should be in history
      expect(tracker.hasSeenMessage('msg-14'), isTrue);
      // Very old messages should be removed
      expect(tracker.hasSeenMessage('msg-0'), isFalse);
    });
    
    test('should handle disposal correctly', () async {
      final message = {'@': 'dispose-test', 'data': 'test'};
      
      try {
        final future = tracker.sendMessage(
          message,
          (msg) async {
            // Don't complete - let disposal cancel it
          },
        );
        
        // Dispose immediately
        tracker.dispose();
        
        await future;
        fail('Expected MessageCancelledException');
      } catch (e) {
        expect(e, isA<MessageCancelledException>());
      }
    });
    
    test('should not handle acknowledgment for unknown message', () {
      final handled = tracker.handleAck('unknown-msg', 'ack');
      expect(handled, isFalse);
    });
    
    test('should not handle error for unknown message', () {
      final handled = tracker.handleError('unknown-msg', 'error');
      expect(handled, isFalse);
    });
    
    test('should handle sender exceptions', () async {
      final message = {'@': 'sender-error', 'data': 'test'};
      
      try {
        await tracker.sendMessage(
          message,
          (msg) async {
            throw Exception('Sender failed');
          },
        );
        fail('Expected Exception');
      } catch (e) {
        expect(e, isA<Exception>());
      }
      
      // Wait a bit for cleanup
      await Future.delayed(Duration(milliseconds: 10));
      
      // Message should be removed from pending
      expect(tracker.pendingCount, equals(0));
    });
    
    test('should provide meaningful string representations', () {
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
    });
    
    test('should handle multiple pending messages', () async {
      final completers = <Completer<void>>[];
      
      // Send multiple messages
      for (int i = 0; i < 5; i++) {
        final completer = Completer<void>();
        completers.add(completer);
        
        final message = {'@': 'multi-$i', 'data': 'test'};
        tracker.sendMessage(
          message,
          (msg) async {
            completer.complete();
          },
        );
      }
      
      expect(tracker.pendingCount, equals(5));
      
      // Complete all messages
      await Future.wait(completers.map((c) => c.future));
      
      // Acknowledge all messages
      for (int i = 0; i < 5; i++) {
        tracker.handleAck('multi-$i', 'ack-$i');
      }
      
      await Future.delayed(Duration(milliseconds: 10));
      expect(tracker.pendingCount, equals(0));
    });
  });
}
