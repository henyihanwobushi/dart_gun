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
    console.log(`Gun.js HTTP GET: ${key}`);
    
    let responseHandled = false;
    
    // Set up timeout to prevent hanging requests (longer timeout for better sync)
    const timeout = setTimeout(() => {
      if (!responseHandled) {
        responseHandled = true;
        console.log(`Gun.js HTTP GET timeout for ${key}`);
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
              console.log(`Gun.js HTTP GET result for ${key}:`, data);
              console.log(`Gun.js HTTP GET resolved result for ${key}:`, resolvedData);
              res.writeHead(200, {'Content-Type': 'application/json'});
              res.end(JSON.stringify(resolvedData));
            } catch (e) {
              // Fall back to original data if resolution fails
              clearTimeout(timeout);
              responseHandled = true;
              console.log(`Gun.js HTTP GET result (unresolved) for ${key}:`, data);
              res.writeHead(200, {'Content-Type': 'application/json'});
              res.end(JSON.stringify(data));
            }
          } else if (attemptCount < maxAttempts) {
            // Retry after a short delay
            setTimeout(attemptRead, 500);
          } else {
            clearTimeout(timeout);
            responseHandled = true;
            console.log(`Gun.js HTTP: Data not found for ${key}`);
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
        console.log(`Gun.js HTTP PUT: ${key}`, data);
        
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
        console.log(`Gun.js HTTP PUT error:`, e.message);
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
