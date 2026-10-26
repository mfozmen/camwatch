import 'package:camwatch_core/camwatch_core.dart';
import 'package:flutter/material.dart';

import 'src/native.dart';
import 'src/scan_page.dart';
import 'src/update_button.dart';

void main() => runApp(const CamwatchApp());

class CamwatchApp extends StatelessWidget {
  const CamwatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'camwatch',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      darkTheme: ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.dark),
      home: const ScanPage(
        scan: scanLan,
        newPlayer: MediaKitPlayer.new,
        findPaths: probeStreamPaths,
        store: SecureCredentialStore(),
        consent: SecureConsentStore.scan(),
        saved: SecureCameraStore(),
        actions: [
          UpdateButton(
            check: checkForUpdate,
            consent: SecureConsentStore.updates(),
            open: openInBrowser,
          ),
        ],
      ),
    );
  }
}
