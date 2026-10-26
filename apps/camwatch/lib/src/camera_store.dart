import 'package:camwatch_core/camwatch_core.dart';

/// Where the saved cameras live: the OS secure store in the app, a list in
/// tests. [write] replaces the whole list.
abstract interface class CameraStore {
  Future<List<SavedCamera>> read();
  Future<void> write(List<SavedCamera> cameras);
}
