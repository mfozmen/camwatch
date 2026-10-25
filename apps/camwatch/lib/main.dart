import 'package:camwatch_core/camwatch_core.dart';
import 'package:flutter/material.dart';

import 'src/multicast_lock.dart';
import 'src/scan_page.dart';

void main() => runApp(const CamwatchApp());

class CamwatchApp extends StatelessWidget {
  const CamwatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'camwatch',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      darkTheme: ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.dark),
      home: ScanPage(scan: () => discoverDevices(lock: withMulticastLock)),
    );
  }
}
