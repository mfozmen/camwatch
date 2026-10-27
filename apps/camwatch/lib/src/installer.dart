import 'dart:io';

import 'package:camwatch_core/camwatch_core.dart';

/// Fetches a release's file, verified, reporting progress; [downloadVerified]
/// into the temp folder in the app, a fake in tests.
typedef Download = Future<File> Function(
  Release release, {
  void Function(int received, int? total)? onProgress,
});

/// Installs a downloaded release file and brings the new version up: the
/// setup on Windows, the system package installer on Android. Absent on a
/// platform that has none, where the browser gets the link instead.
abstract interface class Installer {
  Future<void> install(File file);
}

/// The OS wants the user's leave before this app may install apps; the
/// page to give it has been opened.
class InstallBlocked implements Exception {}
