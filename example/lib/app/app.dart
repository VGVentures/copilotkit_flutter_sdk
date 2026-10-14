import 'package:flutter/material.dart';

class App extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'CopilotKit',
      home: Scaffold(body: Center(child: Text('CopilotKit'))),
    );
  }
}
