import 'package:flutter/material.dart';

void main() => runApp(const CamwatchApp());

class CamwatchApp extends StatelessWidget {
  const CamwatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'camwatch',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const Scaffold(body: Center(child: Text('Cameras on your network will show up here.'))),
    );
  }
}
