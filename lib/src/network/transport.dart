import 'dart:async';
import 'gun_wire_protocol.dart';
import 'message_tracker.dart';

/// Network transport interface for Gun Dart with Gun.js wire protocol support
/// Defines the contract for different transport implementations
abstract class Transport {
  /// Connection URL or identifier
  String get url;
  
  /// Current connection status
  bool get isConnected;
  
  /// Stream of connection state changes
  Stream<bool> get connectionState;
  
  /// Stream of incoming raw messages
  Stream<Map<String, dynamic>> get messages;
  
  /// Stream of parsed Gun.js wire messages
  Stream<GunWireMessage> get wireMessages;
  
  /// Message tracker for acknowledgments
  MessageTracker get messageTracker;
  
  /// Connect to the remote endpoint
  Future<void> connect();
  
  /// Disconnect from the remote endpoint
  Future<void> disconnect();
  
  /// Send a raw message to the remote endpoint
  Future<void> send(Map<String, dynamic> message);
  
  /// Send a Gun.js wire protocol message with acknowledgment tracking
  Future<String> sendWireMessage(Map<String, dynamic> wireMessage, {
    Duration? timeout,
    bool requiresAck = false,
  });
  
  /// Send a 'get' query message
  Future<String> sendGet(String key, {String? messageId});
  
  /// Send a 'put' data message
  Future<String> sendPut(String key, Map<String, dynamic> data, {
    String? messageId,
    Map<String, num>? hamState,
  });
  
  /// Send a 'hi' handshake message
  Future<String> sendHi({
    String? messageId,
    String? version,
    String? peerId,
  });
  
  /// Send a 'bye' disconnect message
  Future<String> sendBye({
    String? messageId,
    String? peerId,
  });
  
  /// Send an acknowledgment message
  Future<void> sendAck(String originalMessageId, {dynamic result});
  
  /// Send an error (DAM) message
  Future<void> sendError(String errorMessage, {
    String? replyToMessageId,
  });
  
  /// Close the transport and clean up resources
  Future<void> close();
}

/// Base implementation providing Gun.js wire protocol functionality
abstract class BaseTransport implements Transport {
  late final MessageTracker _messageTracker;
  late final StreamController<GunWireMessage> _wireMessageController;
  late final StreamSubscription _messageSubscription;
  
  BaseTransport() {
    _messageTracker = MessageTracker();
    _wireMessageController = StreamController<GunWireMessage>.broadcast();
    
    // Parse incoming messages and handle acknowledgments
    _messageSubscription = messages.listen(_handleIncomingMessage);
  }
  
  @override
  Stream<GunWireMessage> get wireMessages => _wireMessageController.stream;
  
  @override
  MessageTracker get messageTracker => _messageTracker;
  
  @override
  Future<String> sendWireMessage(Map<String, dynamic> wireMessage, {
    Duration? timeout,
    bool requiresAck = false,
  }) async {
    final messageId = wireMessage['@'] as String;
    
    if (requiresAck) {
      return await _messageTracker.sendMessage(wireMessage, send, timeout: timeout);
    } else {
      await send(wireMessage);
      return messageId;
    }
  }
  
  @override
  Future<String> sendGet(String key, {String? messageId}) async {
    final message = GunWireProtocol.createGetMessage(key, messageId: messageId);
    return await sendWireMessage(message, requiresAck: true);
  }
  
  @override
  Future<String> sendPut(String key, Map<String, dynamic> data, {
    String? messageId,
    Map<String, num>? hamState,
  }) async {
    final message = GunWireProtocol.createPutMessage(
      key, 
      data, 
      messageId: messageId,
      hamState: hamState,
    );
    return await sendWireMessage(message, requiresAck: true);
  }
  
  @override
  Future<String> sendHi({
    String? messageId,
    String? version,
    String? peerId,
  }) async {
    final message = GunWireProtocol.createHiMessage(
      messageId: messageId,
      version: version ?? 'dart-0.2.1',
      peerId: peerId,
    );
    return await sendWireMessage(message, requiresAck: false);
  }
  
  @override
  Future<String> sendBye({
    String? messageId,
    String? peerId,
  }) async {
    final message = GunWireProtocol.createByeMessage(
      messageId: messageId,
      peerId: peerId,
    );
    return await sendWireMessage(message, requiresAck: false);
  }
  
  @override
  Future<void> sendAck(String originalMessageId, {dynamic result}) async {
    final message = GunWireProtocol.createAckMessage(
      originalMessageId,
      result: result,
    );
    await send(message);
  }
  
  @override
  Future<void> sendError(String errorMessage, {
    String? replyToMessageId,
  }) async {
    final message = GunWireProtocol.createDamMessage(
      errorMessage,
      replyToMessageId: replyToMessageId,
    );
    await send(message);
  }
  
  /// Handle incoming raw message
  void _handleIncomingMessage(Map<String, dynamic> rawMessage) {
    try {
      final wireMessage = GunWireProtocol.parseMessage(rawMessage);
      
      // Handle acknowledgments and errors
      if (wireMessage.isAck && wireMessage.ackId != null) {
        _messageTracker.handleAck(
          wireMessage.ackId!, 
          wireMessage.messageId!,
          result: wireMessage.ok,
        );
      } else if (wireMessage.isError && wireMessage.ackId != null) {
        _messageTracker.handleError(
          wireMessage.ackId!,
          wireMessage.dam!,
        );
      }
      
      // Send to wire message stream
      _wireMessageController.add(wireMessage);
      
      // Send acknowledgment for messages that require it
      if (wireMessage.requiresAck && !wireMessage.isAck) {
        sendAck(wireMessage.messageId!);
      }
      
    } catch (e) {
      // Invalid wire message format - ignore or log
      print('Invalid wire message format: $e');
    }
  }
  
  @override
  Future<void> close() async {
    await _messageSubscription.cancel();
    await _wireMessageController.close();
    _messageTracker.dispose();
  }
}
