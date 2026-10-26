import 'dart:async';

import 'package:camwatch_core/camwatch_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'credential_store.dart';
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
      configuration: const PlayerConfiguration(
        protocolWhitelist: ['rtsp', 'rtp', 'udp', 'tcp'],
        // FFmpeg announces an RTSP redirect at its info level, which mpv
        // relays as verbose; nothing less chatty carries it. Never print
        // that stream: it carries the URL, login included.
        logLevel: MPVLogLevel.v,
      ),
    );
    final native = _player.platform as NativePlayer;
    // Second line behind the relay: should a redirect ever reach FFmpeg, it
    // follows it on its own with the login in hand, so stop on the announcement.
    _redirects = _player.stream.log.where((line) => line.text.contains('Redirecting to')).listen((
      _,
    ) {
      unawaited(native.command(['stop']));
      _redirected.add(null);
    });
    // Interleaved TCP keeps the media on the connection to the camera, so an
    // SDP media address off the LAN is never dialled; no copy of the stream on disk.
    native.setProperty('rtsp-transport', 'tcp');
    native.setProperty('cache-on-disk', 'no');
    _native = native;
    _controller = VideoController(_player);
  }

  late final Player _player;
  late final NativePlayer _native;
  late final VideoController _controller;
  late final StreamSubscription<PlayerLog> _redirects;
  final _redirected = StreamController<void>.broadcast();
  RtspRelay? _relay;
  var _disposed = false;

  // Not Player.open: it writes the URL, password included, to a playlist file
  // on disk. The camera is reached through the loopback relay, which drops a
  // redirect before FFmpeg can see it.
  @override
  Future<void> open(String url) async {
    final target = Uri.parse(url);
    final relay = await RtspRelay.start(target.host, target.port);
    if (_disposed) return relay.close();
    // Assign before closing the old one: two opens in flight must not leak a listener.
    final previous = _relay;
    _relay = relay;
    await previous?.close();
    unawaited(
      relay.onRedirect.then((_) {
        if (!identical(relay, _relay)) return;
        unawaited(_native.command(['stop']));
        _redirected.add(null);
      }),
    );
    await _native.command(['loadfile', loopbackUrl(url, relay.port), 'replace']);
    await _player.play();
  }

  @override
  Stream<String> get errors => _player.stream.error;

  @override
  Stream<void> get firstFrame => _player.stream.width.where((width) => (width ?? 0) > 0);

  @override
  Stream<void> get redirected => _redirected.stream;

  @override
  Widget get view => Video(controller: _controller, controls: null);

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _relay?.close();
    await _redirects.cancel();
    await _redirected.close();
    await _player.dispose();
  }
}

/// Logins in the OS secure store: the Android Keystore, DPAPI on Windows.
class SecureCredentialStore implements CredentialStore {
  const SecureCredentialStore();

  // Keys hold '/': the Windows Credential Manager fallback would reject them, keep it off.
  static const _storage = FlutterSecureStorage();

  @override
  Future<Credentials?> read(String address) async {
    final user = await _storage.read(key: '$address/user');
    final password = await _storage.read(key: '$address/password');
    return user == null || password == null ? null : Credentials(user, password);
  }

  @override
  Future<void> write(String address, Credentials credentials) async {
    await _storage.write(key: '$address/user', value: credentials.user);
    await _storage.write(key: '$address/password', value: credentials.password);
  }
}
// coverage:ignore-end
