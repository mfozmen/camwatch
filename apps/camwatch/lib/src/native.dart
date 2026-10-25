import 'package:camwatch_core/camwatch_core.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'multicast_lock.dart';
import 'player.dart';

// The glue `flutter test` cannot run: a platform channel and libmpv. Kept
// thin; everything around it is tested with fakes.
// coverage:ignore-start
/// The one scan the app runs: discovery under the Android multicast lock.
Future<List<Device>?> scanLan() => discoverDevices(lock: withMulticastLock);

/// libmpv through media_kit: the one player for Android and Windows.
class MediaKitPlayer implements StreamPlayer {
  MediaKitPlayer() {
    MediaKit.ensureInitialized();
    _player = Player();
    _controller = VideoController(_player);
  }

  late final Player _player;
  late final VideoController _controller;

  @override
  Future<void> open(String url) => _player.open(Media(url));

  @override
  Stream<String> get errors => _player.stream.error;

  @override
  Stream<bool> get buffering => _player.stream.buffering;

  @override
  Widget get view => Video(controller: _controller, controls: null);

  @override
  Future<void> dispose() => _player.dispose();
}
// coverage:ignore-end
