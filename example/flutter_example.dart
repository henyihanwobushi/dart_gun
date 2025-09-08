import 'package:flutter/material.dart';
import '../lib/src/gun.dart';
import '../lib/src/flutter/gun_provider.dart';
import '../lib/src/flutter/gun_builder.dart';

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
      home: GunApp(
        onGunCreated: (gun) {
          print('Gun instance created and ready!');
          _seedData(gun);
        },
        child: MyHomePage(),
      ),
    );
  }

  /// Seed some initial data for the example
  void _seedData(Gun gun) async {
    await gun.get('messages').get('msg1').put({
      'text': 'Hello from Gun Dart!',
      'author': 'Flutter User',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    
    await gun.get('messages').get('msg2').put({
      'text': 'Real-time updates work great!',
      'author': 'Another User',
      'timestamp': DateTime.now().millisecondsSinceEpoch + 1000,
    });
    
    await gun.get('counter').put({'value': 0});
  }
}

class MyHomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Gun Dart Flutter Demo'),
        backgroundColor: Colors.blue[100],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Real-time counter example
            Card(
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
                        GunBuilder<int>(
                          chain: context.gun.get('counter'),
                          transform: (data) => (data as Map?)?['value'] ?? 0,
                          builder: (context, value, isLoading) {
                            if (isLoading) {
                              return CircularProgressIndicator(
                                strokeWidth: 2,
                              );
                            }
                            return Text(
                              value.toString(),
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: () => _incrementCounter(context),
                          child: Text('Increment'),
                        ),
                        SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => _decrementCounter(context),
                          child: Text('Decrement'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),
            
            // Messages list example
            Card(
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
                    
                    // Message input
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: 'Type a message...',
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (text) => _sendMessage(context, text),
                          ),
                        ),
                        SizedBox(width: 8),
                        IconButton(
                          onPressed: () {
                            // In a real app, you'd get the text from the controller
                            _sendMessage(context, 'New message from Flutter!');
                          },
                          icon: Icon(Icons.send),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    
                    // Messages display using GunText
                    Container(
                      height: 200,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MessageWidget(messageKey: 'msg1'),
                            MessageWidget(messageKey: 'msg2'),
                            MessageWidget(messageKey: 'msg3'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),
            
            // User status example
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'User Status',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    SizedBox(height: 8),
                    GunText(
                      chain: context.gun.get('user').get('status'),
                      loadingText: 'Loading status...',
                      emptyText: 'No status set',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: Colors.grey[600],
                      ),
                    ),
                    SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => _updateStatus(context),
                      child: Text('Update Status'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _incrementCounter(BuildContext context) async {
    final current = await context.gun.get('counter').once() as Map?;
    final value = (current?['value'] ?? 0) as int;
    await context.gun.get('counter').put({'value': value + 1});
  }

  void _decrementCounter(BuildContext context) async {
    final current = await context.gun.get('counter').once() as Map?;
    final value = (current?['value'] ?? 0) as int;
    await context.gun.get('counter').put({'value': value - 1});
  }

  void _sendMessage(BuildContext context, String text) async {
    if (text.trim().isEmpty) return;
    
    final messageId = 'msg${DateTime.now().millisecondsSinceEpoch}';
    await context.gun.get('messages').get(messageId).put({
      'text': text.trim(),
      'author': 'Flutter User',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _updateStatus(BuildContext context) async {
    final statuses = [
      'Available',
      'Busy',
      'In a meeting',
      'Working from home',
      'On vacation',
    ];
    final status = statuses[DateTime.now().millisecond % statuses.length];
    await context.gun.get('user').get('status').put(status);
  }
}

class MessageWidget extends StatelessWidget {
  final String messageKey;

  const MessageWidget({Key? key, required this.messageKey}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GunBuilder<Map<String, dynamic>>(
      chain: context.gun.get('messages').get(messageKey),
      builder: (context, message, isLoading) {
        if (isLoading) {
          return Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('Loading message...', style: TextStyle(color: Colors.grey)),
          );
        }
        
        if (message == null) {
          return SizedBox.shrink();
        }
        
        final text = message['text'] ?? '';
        final author = message['author'] ?? 'Unknown';
        final timestamp = message['timestamp'] ?? 0;
        final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
        
        return Container(
          margin: EdgeInsets.symmetric(vertical: 4),
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 4),
              Text(
                '$author • ${_formatTime(date)}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:'
           '${date.minute.toString().padLeft(2, '0')}';
  }
}
