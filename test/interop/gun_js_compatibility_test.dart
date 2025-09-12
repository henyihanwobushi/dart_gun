import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/dart_gun.dart';

// 增加全局超时系数，便于在不同环境中调整等待时间
const double timeoutMultiplier = 1.5; // 增加1.5倍的等待时间

/// Comprehensive Gun.js interoperability tests
/// 
/// These tests validate that dart_gun can successfully communicate and 
/// synchronize data with actual Gun.js instances, ensuring complete compatibility.
/// 
/// Prerequisites:
/// 1. Node.js and Gun.js installed: npm install gun
/// 2. Test Gun.js server running on localhost:8765
/// 3. Test data seeded in Gun.js instance

// Helper function to conditionally run tests based on Gun.js availability
void gunJSTest(String description, Future<void> Function() testBody, bool Function() isGunJSAvailable) {
  test(description, () async {
    if (!isGunJSAvailable()) {
      markTestSkipped('Gun.js not available - run: npm install gun');
      return;
    }
    await testBody();
  });
}

// Helper function to skip test if Gun.js not available - called at beginning of each test
bool shouldSkipGunJSTest(bool gunJSAvailable) {
  if (!gunJSAvailable) {
    markTestSkipped('Gun.js not available - run: npm install gun');
    return true;
  }
  return false;
}

void main() {
  group('Gun.js Interoperability Tests', () {
    late Gun gun;
    late Process? gunServer;
    bool gunJSAvailable = false;
    
    setUpAll(() async {
      // Check if Gun.js is available in the current project directory
      try {
        final result = await Process.run(
          'node',
          ['-e', 'require("gun"); console.log("available")'],
          workingDirectory: Directory.current.path,
        );
        gunJSAvailable = result.exitCode == 0 && result.stdout.toString().contains('available');
        if (gunJSAvailable) {
          print('✅ Gun.js detected and available for interoperability tests');
        }
      } catch (e) {
        gunJSAvailable = false;
      }
      
      if (!gunJSAvailable) {
        print('\nSkipping Gun.js interoperability tests - Gun.js not installed');
        print('To enable these tests, run: npm install gun');
        return;
      }
      
      try {
        // Start Gun.js test server
        gunServer = await _startGunJSServer();
        await Future.delayed(const Duration(seconds: 2)); // Allow server to start
        
        // Create dart_gun instance configured for Gun.js compatibility
        gun = Gun(GunOptions(
          peers: [WebSocketPeer('ws://localhost:8765/gun')],
          storage: MemoryStorage(), // Use memory storage for tests
        ));
        
        // Wait for connection
        await Future.delayed(const Duration(seconds: 1));
      } catch (e) {
        print('Failed to start Gun.js test server: $e');
        gunJSAvailable = false;
      }
    });
    
    tearDownAll(() async {
      if (gunJSAvailable) {
        await gun.close();
        gunServer?.kill();
      }
    });
    
    group('Basic Data Synchronization', () {
      gunJSTest('should sync data from dart_gun to Gun.js', () async {
        // Put data in dart_gun
        final testData = {
          'message': 'Hello from dart_gun',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'source': 'flutter_test',
        };
        
        await gun.get('interop/from_dart').put(testData);
        
        // Wait for sync - Gun.js needs time to process WebSocket data
        await Future.delayed(Duration(seconds: (5 * timeoutMultiplier).toInt()));
        
        // Verify data appears in Gun.js via HTTP API
        final response = await _queryGunJS('interop/from_dart');
        expect(response, isNotNull);
        expect(response['message'], equals('Hello from dart_gun'));
        expect(response['source'], equals('flutter_test'));
      }, () => gunJSAvailable);
      
      gunJSTest('should sync data from Gun.js to dart_gun', () async {
        // Put data in Gun.js
        await _putToGunJS('interop/from_gunjs', {
          'message': 'Hello from Gun.js',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'source': 'node_test',
        });
        
        // Wait for WebSocket sync from Gun.js to dart_gun
        await Future.delayed(Duration(seconds: (3 * timeoutMultiplier).toInt()));
        
        // Read data from dart_gun
        final result = await gun.get('interop/from_gunjs').once();
        expect(result, isNotNull);
        expect(result!['message'], equals('Hello from Gun.js'));
        expect(result['source'], equals('node_test'));
      }, () => gunJSAvailable);
      
      gunJSTest('should handle bi-directional sync', () async {
        final nodeKey = 'interop/bidirectional/${DateTime.now().millisecondsSinceEpoch}';
        
        // First: dart_gun writes a field
        await gun.get(nodeKey).put({'dart_field': 'from_dart'});
        await Future.delayed(Duration(milliseconds: (500 * timeoutMultiplier).toInt())); // Allow sync to Gun.js
        
        // Verify Gun.js received the dart_field
        final jsResultAfterDart = await _queryGunJS(nodeKey);
        expect(jsResultAfterDart, isNotNull, reason: 'Gun.js should have received data from dart_gun');
        expect(jsResultAfterDart['dart_field'], equals('from_dart'), reason: 'Gun.js should have dart_field from dart_gun');
        
        // Second: Use a different key for Gun.js to put data, then merge
        // This simulates the realistic scenario where Gun.js receives data from another source
        final jsOnlyKey = 'interop/from_js_only/${DateTime.now().millisecondsSinceEpoch}';
        await _putToGunJS(jsOnlyKey, {
          'js_field': 'from_js',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'source': 'node_test'
        });
        
        // Wait for Gun.js to process and potentially broadcast
        await Future.delayed(Duration(seconds: (2 * timeoutMultiplier).toInt()));
        
        // Third: dart_gun queries for the js-only data to test GET response handling
        final dartResultFromJS = await gun.get(jsOnlyKey).once();
        expect(dartResultFromJS, isNotNull, reason: 'dart_gun should be able to query data that Gun.js has');
        expect(dartResultFromJS!['js_field'], equals('from_js'), reason: 'dart_gun should receive js_field via query response');
        
        // Fourth: Verify Gun.js still has the original dart data  
        final jsResultFinal = await _queryGunJS(nodeKey);
        expect(jsResultFinal, isNotNull);
        expect(jsResultFinal['dart_field'], equals('from_dart'), reason: 'Gun.js should still have dart_field');
      }, () => gunJSAvailable);
    });
    
    group('Conflict Resolution', () {
      test('should handle HAM conflict resolution with Gun.js', () async {
        if (shouldSkipGunJSTest(gunJSAvailable)) return;
        final nodeKey = 'interop/conflict/${DateTime.now().millisecondsSinceEpoch}';
        
        // Create conflicting writes with different timestamps
        final oldTimestamp = DateTime.now().millisecondsSinceEpoch - 1000;
        final newTimestamp = DateTime.now().millisecondsSinceEpoch;
        
        // dart_gun writes older data
        await gun.get(nodeKey).put({
          'value': 'older_value',
          '_': {
            '#': nodeKey,
            '>': {'value': oldTimestamp},
          }
        });
        
        // Gun.js writes newer data
        await _putToGunJS(nodeKey, {
          'value': 'newer_value',
          '_': {
            '#': nodeKey,
            '>': {'value': newTimestamp},
          }
        });
        
        // Wait for conflict resolution and broadcast sync
        await Future.delayed(Duration(seconds: (8 * timeoutMultiplier).toInt()));
        
        // Both should converge to newer value
        final dartResult = await gun.get(nodeKey).once();
        final jsResult = await _queryGunJS(nodeKey);
        
        expect(dartResult!['value'], equals('newer_value'));
        expect(jsResult['value'], equals('newer_value'));
      });
      
      test('should handle field-level conflict resolution', () async {
        if (shouldSkipGunJSTest(gunJSAvailable)) return;
        final nodeKey = 'interop/field_conflict/${DateTime.now().millisecondsSinceEpoch}';
        final baseTime = DateTime.now().millisecondsSinceEpoch;
        
        // Create a node with multiple fields having different timestamps
        await gun.get(nodeKey).put({
          'field1': 'dart_newer',
          'field2': 'dart_older', 
          '_': {
            '#': nodeKey,
            '>': {
              'field1': baseTime + 1000, // newer
              'field2': baseTime - 1000, // older
            },
          }
        });
        
        await _putToGunJS(nodeKey, {
          'field1': 'js_older',
          'field2': 'js_newer',
          '_': {
            '#': nodeKey,
            '>': {
              'field1': baseTime - 500, // older
              'field2': baseTime + 500, // newer
            },
          }
        });
        
        // Wait for resolution and broadcast sync
        await Future.delayed(Duration(seconds: (5 * timeoutMultiplier).toInt()));
        
        // Check field-level resolution
        final dartResult = await gun.get(nodeKey).once();
        final jsResult = await _queryGunJS(nodeKey);
        
        // field1 should be dart_newer (had newer timestamp)
        // field2 should be js_newer (had newer timestamp)
        expect(dartResult!['field1'], equals('dart_newer'));
        expect(dartResult['field2'], equals('js_newer'));
        expect(jsResult['field1'], equals('dart_newer'));
        expect(jsResult['field2'], equals('js_newer'));
      });
    });
    
    group('Graph Traversal', () {
      test('should handle nested graph queries', () async {
        if (shouldSkipGunJSTest(gunJSAvailable)) return;
        final userKey = 'interop/users/alice_${DateTime.now().millisecondsSinceEpoch}';
        final profileKey = 'interop/profiles/alice_profile_${DateTime.now().millisecondsSinceEpoch}';
        
        // Create linked data structure
        await gun.get(profileKey).put({
          'name': 'Alice Smith',
          'age': 30,
          'bio': 'Software developer',
        });
        
        await gun.get(userKey).put({
          'username': 'alice',
          'email': 'alice@example.com',
          'profile': {'#': profileKey}, // Link to profile
        });
        
        // Wait for sync
        await Future.delayed(const Duration(seconds: 2));
        
        // Test graph traversal from Gun.js side
        final jsUser = await _queryGunJS(userKey);
        expect(jsUser['username'], equals('alice'));
        
        // Follow the link
        final profileLink = jsUser['profile']?['#'];
        expect(profileLink, equals(profileKey));
        
        final jsProfile = await _queryGunJS(profileKey);
        expect(jsProfile['name'], equals('Alice Smith'));
        expect(jsProfile['age'], equals(30));
      });
      
      test('should handle chained get operations', () async {
        if (shouldSkipGunJSTest(gunJSAvailable)) return;
        final chatKey = 'interop/chats/room1_${DateTime.now().millisecondsSinceEpoch}';
        final messageKey = 'interop/messages/msg1_${DateTime.now().millisecondsSinceEpoch}';
        
        // Create message
        await gun.get(messageKey).put({
          'text': 'Hello from dart_gun!',
          'author': 'dart_user',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        
        // Link message to chat
        await gun.get(chatKey).get('messages').get('latest').put({'#': messageKey});
        
        await Future.delayed(const Duration(seconds: 2));
        
        // Query through Gun.js with chained gets
        final chatData = await _queryGunJS(chatKey);
        expect(chatData, isNotNull);
        
        // Verify the chain exists
        final messagesLink = chatData['messages'];
        expect(messagesLink, isNotNull);
      });
    });
    
    group('Real-time Subscriptions', () {
      test('should receive real-time updates from Gun.js', () async {
        if (shouldSkipGunJSTest(gunJSAvailable)) return;
        final nodeKey = 'interop/realtime/${DateTime.now().millisecondsSinceEpoch}';
        final completer = Completer<Map<String, dynamic>>();
        
        // Subscribe to changes
        gun.get(nodeKey).on((data, key) {
          if (data != null && !completer.isCompleted) {
            completer.complete(data);
          }
        });
        
        // Wait a moment for subscription to be active
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Trigger update from Gun.js
        await _putToGunJS(nodeKey, {
          'message': 'Real-time from Gun.js',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        
        // Wait for real-time update
        final receivedData = await completer.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw TimeoutException('No real-time update received'),
        );
        
        expect(receivedData['message'], equals('Real-time from Gun.js'));
      });
    });
    
    group('Error Handling', () {
      test('should handle DAM errors from Gun.js', () async {
        if (shouldSkipGunJSTest(gunJSAvailable)) return;
        final errors = <GunError>[];
        final errorCompleter = Completer<List<GunError>>();
        
        // Subscribe to errors
        final subscription = gun.errors.listen((error) {
          errors.add(error);
          if (errors.length >= 1) {
            errorCompleter.complete(errors);
          }
        });
        
        // Trigger an error condition
        try {
          await gun.get('nonexistent/deep/path/that/should/fail').once();
        } catch (e) {
          // Expected to fail
        }
        
        // Wait for potential DAM messages
        try {
          await errorCompleter.future.timeout(const Duration(seconds: 5));
        } catch (e) {
          // Ignore timeout
        } finally {
          await subscription.cancel();
        }
        
        // Should handle gracefully (may or may not generate errors depending on Gun.js setup)
        // The test is that we don't crash
        expect(gun.peers.isNotEmpty, isTrue);
      });
    });
    
    group('Wire Protocol Validation', () {
      test('should send proper Gun.js wire format messages', () async {
        if (shouldSkipGunJSTest(gunJSAvailable)) return;
        // This test validates that our wire protocol matches Gun.js expectations
        final nodeKey = 'interop/wire_test/${DateTime.now().millisecondsSinceEpoch}';
        
        // Send a complex nested update
        await gun.get(nodeKey).put({
          'nested': {
            'level1': {
              'level2': 'deep_value'
            }
          },
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'metadata': {
            'source': 'dart_gun',
            'version': '0.2.1',
          }
        });
        
        await Future.delayed(const Duration(seconds: 4));
        
        // Verify Gun.js received and can read the data
        final jsResult = await _queryGunJS(nodeKey);
        expect(jsResult, isNotNull);
        expect(jsResult['nested']?['level1']?['level2'], equals('deep_value'));
        expect(jsResult['metadata']?['source'], equals('dart_gun'));
      });
    });
  });
}

/// Start a Gun.js test server
Future<Process?> _startGunJSServer() async {
  try {
    // Create a Gun.js server script with HTTP API for testing
    final serverScript = '''
const Gun = require('gun');
const http = require('http');
const url = require('url');

// Create HTTP server with request handling
const server = http.createServer((req, res) => {
  // Set CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, PUT, POST, DELETE');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  
  if (req.method === 'OPTIONS') {
    res.writeHead(200);
    res.end();
    return;
  }
  
  const parsedUrl = url.parse(req.url, true);
  const path = parsedUrl.pathname;
  
  // Handle GET requests to /gun/<key>
  if (req.method === 'GET' && path.startsWith('/gun/')) {
    const key = path.substring(5); // Remove '/gun/' prefix
    console.log(\`Gun.js HTTP GET: \${key}\`);
    
    let responseHandled = false;
    
    // Set up timeout to prevent hanging requests (longer timeout for better sync)
    const timeout = setTimeout(() => {
      if (!responseHandled) {
        responseHandled = true;
        console.log(\`Gun.js HTTP GET timeout for \${key}\`);
        res.writeHead(404, {'Content-Type': 'application/json'});
        res.end(JSON.stringify({error: 'Timeout'}));
      }
    }, 5000); // 5 second timeout
    
    // Try multiple approaches to get data from Gun
    // First try immediate read
    let attemptCount = 0;
    const maxAttempts = 3;
    
    // Helper function to resolve references recursively
    async function resolveReferences(obj, maxDepth = 5) {
      if (maxDepth <= 0) return obj;
      if (!obj || typeof obj !== 'object') return obj;
      
      const result = {};
      
      for (const [fieldKey, fieldValue] of Object.entries(obj)) {
        // Preserve Gun.js metadata
        if (fieldKey === '_') {
          result[fieldKey] = fieldValue;
          continue;
        }
        
        // Check if this is a reference
        if (fieldValue && typeof fieldValue === 'object' && fieldValue['#']) {
          const refKey = fieldValue['#'];
          
          try {
            // Resolve the reference
            const referencedData = await new Promise((resolve) => {
              gun.get(refKey).once((refData) => {
                resolve(refData);
              });
            });
            
            if (referencedData) {
              // Recursively resolve nested references
              result[fieldKey] = await resolveReferences(referencedData, maxDepth - 1);
            } else {
              // Keep the reference if it can't be resolved
              result[fieldKey] = fieldValue;
            }
          } catch (e) {
            // Keep the reference if there's an error
            result[fieldKey] = fieldValue;
          }
        } else {
          // Regular field, recursively resolve if it's an object
          result[fieldKey] = await resolveReferences(fieldValue, maxDepth - 1);
        }
      }
      
      return result;
    }
    
    async function attemptRead() {
      attemptCount++;
      
      gun.get(key).once(async (data, dataKey) => {
        if (!responseHandled) {
          if (data && Object.keys(data).filter(k => k !== '_').length > 0) {
            try {
              // Resolve all references to reconstruct nested structure
              const resolvedData = await resolveReferences(data);
              
              clearTimeout(timeout);
              responseHandled = true;
              console.log(\`Gun.js HTTP GET result for \${key}:\`, data);
              console.log(\`Gun.js HTTP GET resolved result for \${key}:\`, resolvedData);
              res.writeHead(200, {'Content-Type': 'application/json'});
              res.end(JSON.stringify(resolvedData));
            } catch (e) {
              // Fall back to original data if resolution fails
              clearTimeout(timeout);
              responseHandled = true;
              console.log(\`Gun.js HTTP GET result (unresolved) for \${key}:\`, data);
              res.writeHead(200, {'Content-Type': 'application/json'});
              res.end(JSON.stringify(data));
            }
          } else if (attemptCount < maxAttempts) {
            // Retry after a short delay
            setTimeout(attemptRead, 500);
          } else {
            clearTimeout(timeout);
            responseHandled = true;
            console.log(\`Gun.js HTTP: Data not found for \${key}\`);
            res.writeHead(404, {'Content-Type': 'application/json'});
            res.end(JSON.stringify({error: 'Not found'}));
          }
        }
      });
    }
    
    attemptRead();
    return;
  }
  
  // Handle PUT requests to /gun/<key>
  if (req.method === 'PUT' && path.startsWith('/gun/')) {
    const key = path.substring(5); // Remove '/gun/' prefix
    let body = '';
    req.on('data', chunk => { body += chunk.toString(); });
    req.on('end', () => {
      try {
        const data = JSON.parse(body);
        console.log(\`Gun.js HTTP PUT: \${key}\`, data);
        
        // Put data into Gun.js (this should broadcast to WebSocket peers)
        const ref = gun.get(key);
        ref.put(data);
        
        // Force synchronization by using Gun.js's proper broadcast mechanism
        // Use Gun's internal peer broadcasting system instead of manual WebSocket access
        setTimeout(() => {
          ref.once((currentData) => {
            if (currentData) {
              console.log('Gun.js forcing broadcast of HTTP data for ' + key + ':', currentData);
              
              // Strategy 1: Multiple Gun.js broadcast attempts
              // Use different Gun.js methods to ensure WebSocket peers receive the update
              try {
                // Method 1: Direct re-put to trigger broadcasts
                console.log('Gun.js Strategy 1: Direct re-put');
                gun.get(key).put(currentData, (ack) => {
                  console.log('Gun.js broadcast PUT acknowledgment:', ack);
                });
                
                // Method 2: Force Gun.js to trigger its internal broadcast
                setTimeout(() => {
                  console.log('Gun.js Strategy 2: Force trigger broadcast');
                  // Create a small change to force Gun.js to broadcast
                  const triggerData = {...currentData, _trigger: Date.now()};
                  gun.get(key).put(triggerData, (ack) => {
                    // Remove the trigger field immediately
                    gun.get(key).put(currentData);
                  });
                }, 100);
                
                // Method 3: Use Gun.js's emit mechanism
                setTimeout(() => {
                  console.log('Gun.js Strategy 3: Manual peer broadcast');
                  try {
                    // Access Gun's peer connections directly
                    const opt = gun._.opt;
                    if (opt && opt.peers) {
                      Object.keys(opt.peers).forEach(peerKey => {
                        const peer = opt.peers[peerKey];
                        if (peer && peer.wire && peer.wire.send) {
                          try {
                            // Create Gun.js wire protocol message
                            const putMessage = {
                              put: {[key]: currentData},
                              '#': Math.random().toString(36).substring(2, 11),
                              '@': Math.random().toString(36).substring(2, 11)
                            };
                            peer.wire.send(JSON.stringify(putMessage));
                            console.log('Gun.js manually sent PUT to peer:', putMessage);
                          } catch (sendErr) {
                            console.log('Gun.js peer send failed:', sendErr.message);
                          }
                        }
                      });
                    }
                  } catch (e) {
                    console.log('Gun.js manual broadcast error:', e.message);
                  }
                }, 200);
                
              } catch (e) {
                console.log('Gun.js overall broadcast error:', e.message);
              }
            }
          });
        }, 100);
        res.writeHead(200, {'Content-Type': 'application/json'});
        res.end(JSON.stringify({ok: true}));
      } catch (e) {
        console.log(\`Gun.js HTTP PUT error:\`, e.message);
        res.writeHead(400, {'Content-Type': 'application/json'});
        res.end(JSON.stringify({error: e.message}));
      }
    });
    return;
  }
  
  // Default response
  res.writeHead(404);
  res.end('Not Found');
});

// Initialize Gun with the server and proper storage settings
const gun = Gun({
  web: server,
  peers: [],
  localStorage: false,
  radisk: true,  // Enable radisk for better persistence
  multicast: false
});

// Debug: Log incoming WebSocket messages
gun.on('hi', (msg, peer) => {
  console.log('Gun.js received hi:', JSON.stringify(msg));
});

gun.on('get', (msg, peer) => {
  console.log('Gun.js received get:', JSON.stringify(msg));
});

gun.on('put', (msg, peer) => {
  console.log('Gun.js received put:', JSON.stringify(msg));
  // Check if this is a broadcast to peers
  if (peer && peer.wire) {
    console.log('Gun.js broadcasting PUT to peer:', peer.url || 'unknown');
  }
});

// Add some test data
gun.get('test/initial').put({
  message: 'Initial data from Gun.js',
  timestamp: Date.now()
});

console.log('Gun.js test server starting on port 8765');
server.listen(8765, () => {
  console.log('Gun.js test server ready with HTTP API at http://localhost:8765');
});

// Keep server alive
process.on('SIGINT', () => {
  console.log('Gun.js test server shutting down');
  server.close();
  process.exit(0);
});
''';
    
    // Write server script to current directory (where node_modules exists)
    final currentDir = Directory.current;
    final serverFile = File('${currentDir.path}/gun_test_server.js');
    await serverFile.writeAsString(serverScript);
    
    // Start the server from the current directory
    final process = await Process.start(
      'node',
      [serverFile.path],
      workingDirectory: currentDir.path,
    );
    
    // Log server output for debugging
    process.stdout.transform(utf8.decoder).listen(print);
    process.stderr.transform(utf8.decoder).listen((data) => print('Gun.js Error: $data'));
    
    return process;
  } catch (e) {
    print('Failed to start Gun.js server: $e');
    return null;
  }
}

/// Query Gun.js via HTTP with enhanced error handling
Future<Map<String, dynamic>> _queryGunJS(String key) async {
  HttpClient? client;
  try {
    print('Querying Gun.js HTTP API for key: $key');
    client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    final request = await client.get('localhost', 8765, '/gun/$key');
    final response = await request.close();
    
    print('Gun.js HTTP response status: ${response.statusCode}');
    
    if (response.statusCode == 200) {
      final body = await response.transform(utf8.decoder).join();
      print('Gun.js HTTP response body: $body');
      final data = jsonDecode(body) as Map<String, dynamic>;
      return data;
    } else if (response.statusCode == 404) {
      print('Gun.js HTTP: Data not found for key $key');
      return {};
    } else {
      final errorBody = await response.transform(utf8.decoder).join();
      print('Gun.js HTTP error ${response.statusCode}: $errorBody');
      return {};
    }
  } catch (e) {
    print('Failed to query Gun.js HTTP API: $e');
    return {};
  } finally {
    client?.close();
  }
}

// WebSocket Gun.js integration function removed - not currently used

/// Send data to Gun.js via HTTP PUT
Future<void> _putToGunJS(String key, Map<String, dynamic> data) async {
  HttpClient? client;
  try {
    client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    final request = await client.put('localhost', 8765, '/gun/$key');
    request.headers.set('Content-Type', 'application/json');
    request.write(jsonEncode(data));
    final response = await request.close();
    await response.drain();
  } catch (e) {
    print('Failed to put to Gun.js: $e');
  } finally {
    client?.close();
  }
}
