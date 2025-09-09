import 'package:flutter/material.dart';
import 'package:gun_dart/gun_dart.dart';

void main() {
  runApp(MyTodoApp());
}

class MyTodoApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gun Dart Todo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: TodoHomePage(),
    );
  }
}

class TodoHomePage extends StatefulWidget {
  @override
  _TodoHomePageState createState() => _TodoHomePageState();
}

class _TodoHomePageState extends State<TodoHomePage> {
  late Gun gun;
  late TodoService todoService;
  late AuthService authService;
  final TextEditingController _todoController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  List<Todo> todos = [];
  bool isAuthenticated = false;
  String? currentUser;

  @override
  void initState() {
    super.initState();
    
    // Initialize Gun with memory storage (you can change to SqliteStorage for persistence)
    gun = Gun(GunOptions(
      storage: MemoryStorage(),
      localStorage: true,
      realtime: true,
    ));
    
    authService = AuthService(gun);
    todoService = TodoService(gun);
    
    // Listen for authentication changes
    gun.user.events.listen((event) {
      setState(() {
        isAuthenticated = gun.user.isAuthenticated;
        currentUser = gun.user.alias;
      });
      
      if (isAuthenticated) {
        _loadTodos();
      }
    });
  }

  void _loadTodos() {
    if (!isAuthenticated) return;
    
    // Subscribe to real-time todo updates
    todoService.onTodos((todoData) {
      setState(() {
        todos = todoData.entries
            .map((entry) => Todo.fromMap(entry.key, entry.value))
            .toList();
        todos.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      });
    });
  }

  Future<void> _signUp() async {
    try {
      await authService.signUp(_usernameController.text, _passwordController.text);
      _usernameController.clear();
      _passwordController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Account created successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sign up failed: $e')),
      );
    }
  }

  Future<void> _signIn() async {
    try {
      await authService.signIn(_usernameController.text, _passwordController.text);
      _usernameController.clear();
      _passwordController.clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sign in failed: $e')),
      );
    }
  }

  Future<void> _signOut() async {
    await authService.signOut();
    setState(() {
      todos.clear();
    });
  }

  Future<void> _addTodo() async {
    if (_todoController.text.trim().isEmpty) return;
    
    await todoService.addTodo(_todoController.text.trim());
    _todoController.clear();
  }

  Future<void> _toggleTodo(Todo todo) async {
    await todoService.toggleTodo(todo.id);
  }

  Future<void> _deleteTodo(Todo todo) async {
    await todoService.deleteTodo(todo.id);
  }

  @override
  void dispose() {
    gun.close();
    _todoController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isAuthenticated) {
      return Scaffold(
        appBar: AppBar(title: Text('Gun Dart Todo - Sign In')),
        body: Padding(
          padding: EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: _signUp,
                    child: Text('Sign Up'),
                  ),
                  ElevatedButton(
                    onPressed: _signIn,
                    child: Text('Sign In'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Gun Dart Todo'),
        actions: [
          TextButton(
            onPressed: _signOut,
            child: Text(
              'Sign Out ($currentUser)',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _todoController,
                    decoration: InputDecoration(
                      hintText: 'Add a new todo...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addTodo(),
                  ),
                ),
                SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _addTodo,
                  child: Text('Add'),
                ),
              ],
            ),
          ),
          Expanded(
            child: todos.isEmpty
                ? Center(
                    child: Text(
                      'No todos yet. Add one above!',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[600],
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: todos.length,
                    itemBuilder: (context, index) {
                      final todo = todos[index];
                      return Card(
                        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: ListTile(
                          leading: Checkbox(
                            value: todo.completed,
                            onChanged: (_) => _toggleTodo(todo),
                          ),
                          title: Text(
                            todo.title,
                            style: TextStyle(
                              decoration: todo.completed 
                                  ? TextDecoration.lineThrough 
                                  : null,
                              color: todo.completed 
                                  ? Colors.grey[600] 
                                  : null,
                            ),
                          ),
                          subtitle: Text(
                            'Created: ${DateTime.fromMillisecondsSinceEpoch(todo.createdAt).toString().substring(0, 19)}',
                            style: TextStyle(fontSize: 12),
                          ),
                          trailing: IconButton(
                            icon: Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteTodo(todo),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// Service classes
class AuthService {
  final Gun gun;
  
  AuthService(this.gun);

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
}

class TodoService {
  final Gun gun;
  
  TodoService(this.gun);

  Future<void> addTodo(String title) async {
    if (!gun.user.isAuthenticated) {
      throw Exception('User not authenticated');
    }
    
    final todoId = Utils.randomString(16);
    await gun.user.storage.get('todos').get(todoId).put({
      'id': todoId,
      'title': title,
      'completed': false,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> toggleTodo(String todoId) async {
    if (!gun.user.isAuthenticated) return;
    
    final todo = await gun.user.storage.get('todos').get(todoId).once();
    if (todo != null) {
      final completed = !(todo['completed'] as bool? ?? false);
      await gun.user.storage.get('todos').get(todoId).put({
        ...todo,
        'completed': completed,
      });
    }
  }

  Future<void> deleteTodo(String todoId) async {
    if (!gun.user.isAuthenticated) return;
    
    await gun.user.storage.get('todos').get(todoId).put(null);
  }

  void onTodos(Function(Map<String, dynamic>) callback) {
    if (!gun.user.isAuthenticated) return;
    
    gun.user.storage.get('todos').on((data, key) {
      if (data != null && data is Map<String, dynamic>) {
        // Filter out null entries (deleted todos)
        final filteredData = Map<String, dynamic>.from(data);
        filteredData.removeWhere((key, value) => value == null);
        callback(filteredData);
      }
    });
  }
}

// Data model
class Todo {
  final String id;
  final String title;
  final bool completed;
  final int createdAt;

  Todo({
    required this.id,
    required this.title,
    required this.completed,
    required this.createdAt,
  });

  factory Todo.fromMap(String id, Map<String, dynamic> map) {
    return Todo(
      id: id,
      title: map['title'] as String,
      completed: map['completed'] as bool? ?? false,
      createdAt: map['createdAt'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'completed': completed,
      'createdAt': createdAt,
    };
  }
}
