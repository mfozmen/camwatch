import 'package:flutter/widgets.dart';

/// Plays one stream into a widget. Screens depend on this, never on the
/// media library, so tests drive them with a fake.
abstract interface class StreamPlayer {
  Future<void> open(String url);
  Stream<String> get errors;

  /// Fires once a picture is on screen: the stream is live.
  Stream<void> get firstFrame;
  Widget get view;
  Future<void> dispose();
}
