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
    // FFmpeg may only nest the protocols RTSP itself needs: a camera's SDP
    // cannot make it fetch http, file or data URLs.
    _player = Player(
      configuration: const PlayerConfiguration(protocolWhitelist: ['rtsp', 'rtp', 'udp', 'tcp']),
    );
    final native = _player.platform as NativePlayer;
    // Interleaved TCP keeps the media on the connection to the camera, so an
    // SDP media address off the LAN is never dialled; no copy of the stream on disk.
    native.setProperty('rtsp-transport', 'tcp');
    native.setProperty('cache-on-disk', 'no');
    _controller = VideoController(_player);
  }

  late final Player _player;
  late final VideoController _controller;

  @override
  Future<void> open(String url) => _player.open(Media(url));

  @override
  Stream<String> get errors => _player.stream.error;

  @override
  Stream<void> get firstFrame => _player.stream.width.where((width) => (width ?? 0) > 0);

  @override
  Widget get view => Video(controller: _controller, controls: null);

  @override
  Future<void> dispose() => _player.dispose();
}
// coverage:ignore-end
