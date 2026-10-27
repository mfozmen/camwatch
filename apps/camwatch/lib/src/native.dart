import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:camwatch_core/camwatch_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:url_launcher/url_launcher.dart';

import 'camera_store.dart';
import 'consent_store.dart';
import 'credential_store.dart';
import 'installer.dart';
import 'multicast_lock.dart';
import 'player.dart';
import 'version.dart';

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

/// The newest release on GitHub, when it is newer than this build and made for it.
Future<Release?> checkForUpdate() =>
    fetchLatestRelease(latestReleasePage, current: appVersion, abi: Abi.current());

/// A release file into a fresh folder of its own under the user's temp,
/// verified against its digest; the folder goes with a failed download.
Future<File> downloadUpdate(Release release, {void Function(int, int?)? onProgress}) async {
  final folder = await Directory.systemTemp.createTemp('camwatch-update-');
  try {
    return await downloadVerified(release, into: folder, onProgress: onProgress);
  } catch (_) {
    await folder.delete(recursive: true);
    rethrow;
  }
}

/// Runs the downloaded setup silently and quits, so it can replace the
/// files; the setup starts the new version (its /RELAUNCH switch).
class WindowsInstaller implements Installer {
  const WindowsInstaller();

  @override
  Future<void> install(File file) async {
    await Process.start(file.path, const [
      '/VERYSILENT',
      '/NORESTART',
      '/RELAUNCH=1',
    ], mode: ProcessStartMode.detached);
    exit(0);
  }
}

/// The installer for this platform, or none yet.
Installer? get platformInstaller => Platform.isWindows ? const WindowsInstaller() : null;

/// Hands [url] to the system browser, which downloads the release there.
Future<void> openInBrowser(Uri url) => launchUrl(url, mode: LaunchMode.externalApplication);

/// The saved cameras, one JSON text in the same store as the logins: no
/// file of its own on disk, nothing more for a backup to see.
class SecureCameraStore implements CameraStore {
  const SecureCameraStore();

  static const _storage = FlutterSecureStorage();
  static const _key = 'cameras';

  @override
  Future<List<SavedCamera>> read() async => decodeCameras(await _storage.read(key: _key) ?? '');

  @override
  Future<void> write(List<SavedCamera> cameras) =>
      _storage.write(key: _key, value: encodeCameras(cameras));
}

/// An accepted notice, in the same store as the logins.
class SecureConsentStore implements ConsentStore {
  const SecureConsentStore.scan() : _key = 'consent/scan';
  const SecureConsentStore.updates() : _key = 'consent/updates';

  static const _storage = FlutterSecureStorage();
  final String _key;

  @override
  Future<bool> read() async => await _storage.read(key: _key) == 'yes';

  @override
  Future<void> write() => _storage.write(key: _key, value: 'yes');

  @override
  Future<void> clear() => _storage.delete(key: _key);
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
