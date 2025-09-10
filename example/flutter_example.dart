import 'package:flutter/material.dart';
import 'package:gun_dart/gun_dart.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gun Dart Flutter Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: GunProvider(
        gun: Gun(), // Create Gun instance
        child: MyHomePage(),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;
  late Gun _gun;
  final TextEditingController _messageController = TextEditingController();
  List<Map<String, dynamic>> _messages = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _gun = GunProvider.of(context);
    _initializeData();
    _subscribeToUpdates();
  }

  void _initializeData() async {
    // Seed initial data
    await _gun.get('counter').put({'value': 0});
    await _gun.get('messages').get('msg1').put({
      'text': 'Welcome to Gun Dart Flutter!',
      'author': 'System',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _subscribeToUpdates() {
    // Subscribe to counter updates
    _gun.get('counter').on((data, key) {
      if (mounted && data != null) {
        setState(() {
          _counter = data['value'] ?? 0;
        });
      }
    });

    // Subscribe to message updates (simplified)
    _gun.get('messages').on((data, key) {
      if (mounted && data != null) {
        print('Message update: $data');
        // In a real app, you'd handle message updates here
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(kToolbarHeight),
        child: _buildAppBar(),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCounterCard(),
            SizedBox(height: 16),
            _buildMessagesCard(),
            SizedBox(height: 16),
            _buildDemoInfoCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return AppBar(
      title: Text('Gun Dart Flutter Demo'),
      backgroundColor: Colors.blue[100],
    );
  }

  Widget _buildCounterCard() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Real-time Counter',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Text('Current value: '),
                Text(
                  _counter.toString(),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _incrementCounter,
                  child: Text('Increment'),
                ),
                SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _decrementCounter,
                  child: Text('Decrement'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagesCard() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Real-time Messages',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (text) => _sendMessage(text),
                  ),
                ),
                SizedBox(width: 8),
                IconButton(
                  onPressed: () => _sendMessage(_messageController.text),
                  icon: Icon(Icons.send),
                ),
              ],
            ),
            SizedBox(height: 16),
            Container(
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  return ListTile(
                    title: Text(message['text'] ?? ''),
                    subtitle: Text('by ${message['author'] ?? 'Unknown'}'),
                    dense: true,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDemoInfoCard() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Gun Dart Flutter Demo',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            SizedBox(height: 8),
            Text(
              'This demo shows basic Gun Dart integration with Flutter. '
              'The counter updates in real-time and messages are stored '
              'in the Gun database.',
              style: TextStyle(
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _resetDemo,
              child: Text('Reset Demo'),
            ),
          ],
        ),
      ),
    );
  }

  void _incrementCounter() async {
    final newValue = _counter + 1;
    await _gun.get('counter').put({'value': newValue});
  }

  void _decrementCounter() async {
    final newValue = _counter - 1;
    await _gun.get('counter').put({'value': newValue});
  }

  void _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final messageId = 'msg${DateTime.now().millisecondsSinceEpoch}';
    await _gun.get('messages').get(messageId).put({
      'text': text.trim(),
      'author': 'Flutter User',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    // Add to local messages list for immediate UI update
    setState(() {
      _messages.add({
        'text': text.trim(),
        'author': 'Flutter User',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    });

    _messageController.clear();
  }

  void _resetDemo() async {
    await _gun.get('counter').put({'value': 0});
    setState(() {
      _counter = 0;
      _messages.clear();
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }
}
