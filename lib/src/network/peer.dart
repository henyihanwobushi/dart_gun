import 'dart:async';

/// Abstract peer interface for Gun network layer
abstract class Peer {
  /// Peer URL or identifier
  String get url;
  
  /// Current connection status
  bool get isConnected;
  
  /// Connect to this peer
  Future<void> connect();
  
  /// Disconnect from this peer
  Future<void> disconnect();
  
  /// Send data to this peer
  Future<void> send(Map<String, dynamic> data);
  
  /// Stream of incoming messages from this peer
  Stream<Map<String, dynamic>> get messages;
}
