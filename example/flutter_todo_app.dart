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
      home: GunProvider(
        gun: Gun(),
        child: TodoHomePage(),
      ),
    );
  }
}

class TodoHomePage extends StatefulWidget {
  @override
  _TodoHomePageState createState() => _TodoHomePageState();
}

class _TodoHomePageState extends State<TodoHomePage> {
  late Gun gun;
  final TextEditingController _todoController = TextEditingController();
  List<TodoItem> todos = [];
  int _nextId = 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    gun = GunProvider.of(context);
    _loadTodos();
    _subscribeToTodos();
  }

  void _loadTodos() async {
    // Load existing todos from Gun
    final todosData = await gun.get('todos').once();
    if (todosData != null && todosData is Map<String, dynamic>) {
      final todosList = <TodoItem>[];
      todosData.forEach((key, value) {
        if (value != null && value is Map<String, dynamic>) {
          todosList.add(TodoItem.fromMap(key, value));
        }
      });
      setState(() {
        todos = todosList;
        todos.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      });
    }
  }
  
  void _subscribeToTodos() {
    // Subscribe to real-time todo updates
    gun.get('todos').on((data, key) {
      if (mounted) {
        _loadTodos();
      }
    });
  }

  Future<void> _addTodo() async {
    if (_todoController.text.trim().isEmpty) return;
    
    final todoId = 'todo_${_nextId++}_${DateTime.now().millisecondsSinceEpoch}';
    final newTodo = {
      'id': todoId,
      'title': _todoController.text.trim(),
      'completed': false,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
    
    await gun.get('todos').get(todoId).put(newTodo);
    _todoController.clear();
    
    // Update local state immediately for better UX
    setState(() {
      todos.add(TodoItem.fromMap(todoId, newTodo));
      todos.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    });
  }

  Future<void> _toggleTodo(TodoItem todo) async {
    final updatedTodo = {
      'id': todo.id,
      'title': todo.title,
      'completed': !todo.completed,
      'createdAt': todo.createdAt,
    };
    
    await gun.get('todos').get(todo.id).put(updatedTodo);
    
    // Update local state immediately
    setState(() {
      final index = todos.indexWhere((t) => t.id == todo.id);
      if (index >= 0) {
        todos[index] = TodoItem.fromMap(todo.id, updatedTodo);
      }
    });
  }

  Future<void> _deleteTodo(TodoItem todo) async {
    await gun.get('todos').get(todo.id).put(null);
    
    // Update local state immediately
    setState(() {
      todos.removeWhere((t) => t.id == todo.id);
    });
  }

  @override
  void dispose() {
    _todoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: Text('Gun Dart Todo'),
        backgroundColor: Colors.blue[100],
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadTodos,
            tooltip: 'Refresh todos',
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

// Simplified Todo item model
class TodoItem {
  final String id;
  final String title;
  final bool completed;
  final int createdAt;

  TodoItem({
    required this.id,
    required this.title,
    required this.completed,
    required this.createdAt,
  });

  factory TodoItem.fromMap(String id, Map<String, dynamic> map) {
    return TodoItem(
      id: id,
      title: map['title'] as String? ?? '',
      completed: map['completed'] as bool? ?? false,
      createdAt: map['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
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
