# Gun Dart Integration Guide

This guide shows you how to use gun_dart in your own Flutter/Dart applications.

## Installation Options

### Option 1: Local Path Dependency (Recommended for Development)

If you're developing locally and want to use the latest version:

```yaml
# In your app's pubspec.yaml
dependencies:
  flutter:
    sdk: flutter
  gun_dart:
    path: /Users/work/projects/gun_dart  # Update this path to your local gun_dart location
```

### Option 2: Git Dependency (Recommended for Teams)

If you want to use it directly from a git repository:

```yaml
# In your app's pubspec.yaml
dependencies:
  flutter:
    sdk: flutter
  gun_dart:
    git:
      url: https://github.com/yourusername/gun_dart.git
      ref: master  # or specific tag/branch
```

### Option 3: Pub.dev Package (Once Published)

Once published to pub.dev (future):

```yaml
# In your app's pubspec.yaml
dependencies:
  flutter:
    sdk: flutter
  gun_dart: ^0.2.1
```

## Basic Usage

### 1. Import the Package

```dart
import 'package:gun_dart/gun_dart.dart';
```

### 2. Initialize Gun Instance

```dart
class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late Gun gun;

  @override
  void initState() {
    super.initState();
    
    // Initialize Gun with default options (memory storage)
    gun = Gun();
    
    // Or with custom options
    gun = Gun(GunOptions(
      peers: ['ws://localhost:8765/gun'],  // Connect to Gun server
      storage: SqliteStorage(),           // Use SQLite storage
      localStorage: true,                 // Enable local storage
      realtime: true,                     // Enable real-time sync
    ));
  }

  @override
  void dispose() {
    gun.close();
    super.dispose();
  }
}
```

### 3. Basic Data Operations

```dart
class DataService {
  final Gun gun = Gun();

  // Store data
  Future<void> saveUser(String userId, Map<String, dynamic> userData) async {
    await gun.get('users').get(userId).put(userData);
  }

  // Retrieve data
  Future<Map<String, dynamic>?> getUser(String userId) async {
    return await gun.get('users').get(userId).once();
  }

  // Real-time subscriptions
  void subscribeToUser(String userId, Function(Map<String, dynamic>?) callback) {
    gun.get('users').get(userId).on(callback);
  }
}
```

## Advanced Usage Examples

### Real-time Chat Application

```dart
class ChatService {
  final Gun gun = Gun();
  final String chatId;

  ChatService(this.chatId);

  // Send a message
  Future<void> sendMessage(String message, String userId) async {
    final messageId = Utils.randomString(16);
    await gun.get('chats').get(chatId).get('messages').get(messageId).put({
      'text': message,
      'userId': userId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // Listen for new messages
  void onMessages(Function(Map<String, dynamic>) onMessage) {
    gun.get('chats').get(chatId).get('messages').on((data) {
      if (data != null) {
        onMessage(data as Map<String, dynamic>);
      }
    });
  }
}
```

### User Authentication

```dart
class AuthService {
  final Gun gun = Gun();

  Future<UserAccount> signUp(String username, String password) async {
    return await gun.user.create(username, password);
  }

  Future<UserAccount> signIn(String username, String password) async {
    return await gun.user.auth(username, password);
  }

  Future<void> signOut() async {
    await gun.user.leave();
  }

  bool get isAuthenticated => gun.user.isAuthenticated;
  String? get currentUser => gun.user.alias;

  // Store encrypted user data
  Future<void> savePrivateData(Map<String, dynamic> data) async {
    final encrypted = await gun.user.encrypt(data);
    await gun.user.storage.get('private').put({'data': encrypted});
  }
}
```

### Offline-First Todo App

```dart
class TodoService {
  final Gun gun = Gun();
  final String userId;

  TodoService(this.userId);

  Future<void> addTodo(String title) async {
    final todoId = Utils.randomString(16);
    await gun.get('todos').get(userId).get(todoId).put({
      'id': todoId,
      'title': title,
      'completed': false,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> toggleTodo(String todoId) async {
    final todo = await gun.get('todos').get(userId).get(todoId).once();
    if (todo != null) {
      final completed = !(todo['completed'] as bool? ?? false);
      await gun.get('todos').get(userId).get(todoId).put({
        ...todo,
        'completed': completed,
      });
    }
  }

  void onTodos(Function(Map<String, dynamic>) callback) {
    gun.get('todos').get(userId).on((data) {
      if (data != null) {
        callback(data as Map<String, dynamic>);
      }
    });
  }
}
```

## Flutter Widget Integration

```dart
class RealtimeDataWidget extends StatefulWidget {
  @override
  _RealtimeDataWidgetState createState() => _RealtimeDataWidgetState();
}

class _RealtimeDataWidgetState extends State<RealtimeDataWidget> {
  final Gun gun = Gun();
  Map<String, dynamic>? data;
  StreamSubscription? subscription;

  @override
  void initState() {
    super.initState();
    
    // Subscribe to real-time updates
    gun.get('myData').on((newData) {
      if (mounted) {
        setState(() {
          data = newData as Map<String, dynamic>?;
        });
      }
    });
  }

  @override
  void dispose() {
    subscription?.cancel();
    gun.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(data?['message'] ?? 'No data'),
        ElevatedButton(
          onPressed: () {
            gun.get('myData').put({
              'message': 'Hello at ${DateTime.now()}',
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            });
          },
          child: Text('Update Data'),
        ),
      ],
    );
  }
}
```

## Configuration Options

### Storage Options

```dart
// Memory storage (default, good for testing)
Gun(GunOptions(storage: MemoryStorage()));

// SQLite storage (recommended for production)
Gun(GunOptions(storage: SqliteStorage()));
```

### Network Configuration

```dart
Gun(GunOptions(
  peers: [
    'ws://localhost:8765/gun',      // Local Gun server
    'wss://gundb.herokuapp.com/gun', // Public Gun server
  ],
  realtime: true,
  localStorage: true,
));
```

### Advanced CRDT Usage

```dart
// Distributed counters
final counter = CRDTFactory.createPNCounter('node1');
counter.increment(5);
counter.decrement(2);
print(counter.value); // 3

// Distributed sets
final set = CRDTFactory.createORSet<String>('node1');
set.add('item1');
set.add('item2');
set.remove('item1');
print(set.elements); // {'item2'}
```

## Best Practices

### 1. Initialize Once
```dart
class AppState {
  static final Gun _gun = Gun(GunOptions(
    localStorage: true,
    realtime: true,
  ));
  
  static Gun get gun => _gun;
}
```

### 2. Handle Errors
```dart
try {
  await gun.get('path').put(data);
} catch (e) {
  print('Error saving data: $e');
  // Handle offline scenario
}
```

### 3. Manage Subscriptions
```dart
class DataManager {
  final List<StreamSubscription> _subscriptions = [];
  
  void addSubscription(StreamSubscription sub) {
    _subscriptions.add(sub);
  }
  
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }
}
```

### 4. Use Proper Data Structures
```dart
// Good: Use consistent data structures
await gun.get('users').get(userId).put({
  'name': 'John',
  'email': 'john@example.com',
  'lastSeen': DateTime.now().millisecondsSinceEpoch,
});

// Avoid: Inconsistent or nested complex objects
```

## Testing Your Integration

```dart
// test/gun_integration_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gun_dart/gun_dart.dart';

void main() {
  group('Gun Integration Tests', () {
    late Gun gun;
    
    setUp(() {
      gun = Gun(GunOptions(storage: MemoryStorage()));
    });
    
    tearDown(() {
      gun.close();
    });
    
    test('should store and retrieve data', () async {
      await gun.get('test').put({'message': 'hello'});
      final result = await gun.get('test').once();
      expect(result?['message'], equals('hello'));
    });
  });
}
```

## Next Steps

1. **Install the dependency** using one of the methods above
2. **Start with basic operations** (put, get, once)
3. **Add real-time features** using on() subscriptions
4. **Implement authentication** if needed
5. **Configure storage** for production use
6. **Add networking** for multi-user scenarios

## Need Help?

- Check the [example folder](/example) for complete working examples
- Read the [API documentation](/lib/gun_dart.dart) for detailed method signatures
- Review the [test files](/test) for usage patterns

Happy coding with gun_dart! 🚀
