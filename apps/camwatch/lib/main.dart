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
      home: ScanPage(
        scan: scanLan,
        newPlayer: MediaKitPlayer.new,
        findPaths: probeStreamPaths,
        store: const SecureCredentialStore(),
        consent: const SecureConsentStore.scan(),
        saved: const SecureCameraStore(),
        actions: [
          UpdateButton(
            check: checkForUpdate,
            consent: const SecureConsentStore.updates(),
            open: openInBrowser,
            download: downloadUpdate,
            installer: platformInstaller,
          ),
        ],
      ),
    );
  }
}
