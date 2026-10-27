import 'dart:io';

import 'package:flutter/services.dart';

import 'installer.dart';

/// The Android activity answers this channel: it hands an APK to the system
/// installer, or opens the settings page when the app may not install yet.
const installChannel = MethodChannel('io.github.mfozmen.camwatch/install');

/// The system package installer on a downloaded APK. Android asks the user
/// to confirm the install and offers to open the app afterwards.
class AndroidInstaller implements Installer {
  const AndroidInstaller();

  @override
  Future<void> install(File file) async {
    final answer = await installChannel.invokeMethod<String>('install', file.path);
    switch (answer) {
      case 'started':
        return;
      case 'blocked':
        throw InstallBlocked();
      default:
        throw StateError('install answered $answer');
    }
  }
}
