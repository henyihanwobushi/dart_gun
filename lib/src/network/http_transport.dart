import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'transport.dart';

/// HTTP transport implementation for Gun Dart
/// Provides communication over HTTP/HTTPS protocols
/// Useful for server-to-server communication or mobile apps communicating
/// with Gun HTTP endpoints.
class HttpTransport extends BaseTransport {
  final String _baseUrl;
  final Duration _timeout;
  final Map<String, String> _headers;
  final http.Client _client;
  
  bool _isConnected = false;
  final StreamController<Map<String, dynamic>> _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<bool> _connectionStateController = StreamController<bool>.broadcast();

  HttpTransport({
    required String baseUrl,
    Duration timeout = const Duration(seconds: 30),
    Map<String, String>? headers,
    http.Client? client,
  })  : _baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
        _timeout = timeout,
        _headers = {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          ...?headers,
        },
        _client = client ?? http.Client(),
        super();

  @override
  String get url => _baseUrl;

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<bool> get connectionState => _connectionStateController.stream;

  @override
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  @override
  Future<void> connect() async {
    if (_isConnected) return;

    try {
      // Test connectivity with a simple hi message
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/gun'),
            headers: _headers,
            body: jsonEncode({
              'hi': {'gun': '0.1.0', 'peer': 'dart'},
            }),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        _isConnected = true;
        _connectionStateController.add(true);
        print('HTTP transport connected to $_baseUrl');
        
        // Parse response as Gun message if available
        if (response.body.isNotEmpty) {
          try {
            final data = jsonDecode(response.body);
            if (data is Map<String, dynamic>) {
              _messageController.add(data);
            }
          } catch (e) {
            print('Failed to parse HTTP response as Gun message: $e');
          }
        }
      } else {
        throw Exception('HTTP connection failed: ${response.statusCode} ${response.reasonPhrase}');
      }
    } catch (e) {
      _isConnected = false;
      print('HTTP transport connection failed: $e');
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    if (!_isConnected) return;

    try {
      // Send bye message
      await send({
        'bye': {'peer': 'dart'},
      });
    } catch (e) {
      print('Failed to send bye message: $e');
    }

    _isConnected = false;
    _connectionStateController.add(false);
    print('HTTP transport disconnected from $_baseUrl');
  }

  @override
  Future<void> send(Map<String, dynamic> message) async {
    if (!_isConnected) {
      throw StateError('HTTP transport is not connected');
    }

    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/gun'),
            headers: _headers,
            body: jsonEncode(message),
          )
          .timeout(_timeout);

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        try {
          final data = jsonDecode(response.body);
          if (data is Map<String, dynamic>) {
            _messageController.add(data);
          }
        } catch (e) {
          print('Failed to parse HTTP response: $e');
        }
      } else if (response.statusCode != 200) {
        throw Exception('HTTP request failed: ${response.statusCode} ${response.reasonPhrase}');
      }
    } catch (e) {
      print('Failed to send HTTP message: $e');
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    await disconnect();
    await _messageController.close();
    await _connectionStateController.close();
    _client.close();
  }

  /// Send a GET request for data retrieval
  Future<Map<String, dynamic>?> get(String path) async {
    if (!_isConnected) {
      throw StateError('HTTP transport is not connected');
    }

    try {
      final response = await _client
          .get(
            Uri.parse('$_baseUrl/gun/$path'),
            headers: _headers,
          )
          .timeout(_timeout);

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        return jsonDecode(response.body) as Map<String, dynamic>?;
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw Exception('HTTP GET failed: ${response.statusCode} ${response.reasonPhrase}');
      }
    } catch (e) {
      print('Failed to GET from HTTP endpoint: $e');
      rethrow;
    }
  }

  /// Send a PUT request for data storage
  Future<void> put(String path, Map<String, dynamic> data) async {
    if (!_isConnected) {
      throw StateError('HTTP transport is not connected');
    }

    try {
      final response = await _client
          .put(
            Uri.parse('$_baseUrl/gun/$path'),
            headers: _headers,
            body: jsonEncode(data),
          )
          .timeout(_timeout);

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('HTTP PUT failed: ${response.statusCode} ${response.reasonPhrase}');
      }
    } catch (e) {
      print('Failed to PUT to HTTP endpoint: $e');
      rethrow;
    }
  }
}
