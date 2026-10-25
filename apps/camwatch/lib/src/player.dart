import 'package:flutter/widgets.dart';

/// Plays one stream into a widget. Screens depend on this, never on the
/// media library, so tests drive them with a fake.
abstract interface class StreamPlayer {
  Future<void> open(String url);
  Stream<String> get errors;

  /// True while the stream is still being fetched; false on the first frames.
  Stream<bool> get buffering;
  Widget get view;
  Future<void> dispose();
}
