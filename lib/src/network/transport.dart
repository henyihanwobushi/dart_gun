import 'dart:async';

/// Network transport interface for Gun Dart
/// Defines the contract for different transport implementations
abstract class Transport {
  /// Connection URL or identifier
  String get url;
  
  /// Current connection status
  bool get isConnected;
  
  /// Stream of connection state changes
  Stream<bool> get connectionState;
  
  /// Stream of incoming messages
  Stream<Map<String, dynamic>> get messages;
  
  /// Connect to the remote endpoint
  Future<void> connect();
  
  /// Disconnect from the remote endpoint
  Future<void> disconnect();
  
  /// Send a message to the remote endpoint
  Future<void> send(Map<String, dynamic> message);
  
  /// Close the transport and clean up resources
  Future<void> close();
}
