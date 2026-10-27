import 'package:camwatch/src/camera_store.dart';
import 'package:camwatch_core/camwatch_core.dart';

class FakeCameraStore implements CameraStore {
  FakeCameraStore([List<SavedCamera> cameras = const []]) : cameras = [...cameras];

  List<SavedCamera> cameras;

  /// When set, every call throws it, like a broken store would.
  Object? error;

  @override
  Future<List<SavedCamera>> read() async {
    if (error case final error?) throw error;
    return [...cameras];
  }

  @override
  Future<void> write(List<SavedCamera> cameras) async {
    if (error case final error?) throw error;
    this.cameras = [...cameras];
  }
}
