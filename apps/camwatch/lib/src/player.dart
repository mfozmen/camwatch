import 'package:flutter/widgets.dart';

/// Plays one stream into a widget. Screens depend on this, never on the
/// media library, so tests drive them with a fake.
abstract interface class StreamPlayer {
  Future<void> open(String url);
  Stream<String> get errors;

  /// Fires once a picture is on screen: the stream is live.
  Stream<void> get firstFrame;

  /// Fires when the camera answered with a redirect: the player has stopped
  /// instead of following it, since the new address could be off the LAN.
  Stream<void> get redirected;
  Widget get view;
  Future<void> dispose();
}
