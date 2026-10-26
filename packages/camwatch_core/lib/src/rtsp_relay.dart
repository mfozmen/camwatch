import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'lan.dart';

/// One RTSP connection relayed from 127.0.0.1 to a camera on the LAN. A
/// 3xx reply is swallowed and both ends are closed, so the player library,
/// which would follow a redirect on its own with the login in hand, never
/// sees one. The player is pointed at [port] instead of the camera.
class RtspRelay {
  RtspRelay._(this._server, this._host, this._port);

  final ServerSocket _server;
  final String _host;
  final int _port;
  Socket? _client;
  Socket? _camera;
  final _redirect = Completer<void>();

  static Future<RtspRelay> start(String host, int port) async {
    if (!isLocalIpv4(host)) throw ArgumentError.value(host, 'host', 'not on the local network');
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final relay = RtspRelay._(server, host, port);
    server.listen(relay._accept);
    return relay;
  }

  /// Where the player connects.
  int get port => _server.port;

  /// Whether the camera answered with a redirect; [onRedirect] completes then.
  bool get redirected => _redirect.isCompleted;
  Future<void> get onRedirect => _redirect.future;

  static final _status3xx = RegExp(r'(^|\r\n\r\n|\n)RTSP/1\.0 3\d\d ');

  Future<void> _accept(Socket client) async {
    if (_client != null) return client.destroy();
    _client = client;
    try {
      _camera = await Socket.connect(_host, _port);
    } catch (_) {
      return client.destroy();
    }
    final camera = _camera!;
    // One tear-off serves done and error alike: either way the other end closes.
    void cut([Object? _, StackTrace? _]) {
      camera.destroy();
      client.destroy();
    }

    client.listen(camera.add, onDone: cut, onError: cut);
    camera.listen(
      (chunk) {
        // Interleaved media follows PLAY, so a status line is only looked for at a line start.
        if (_status3xx.hasMatch(latin1.decode(chunk))) {
          if (!_redirect.isCompleted) _redirect.complete();
          return cut();
        }
        client.add(chunk);
      },
      onDone: cut,
      onError: cut,
    );
  }

  Future<void> close() async {
    _client?.destroy();
    _camera?.destroy();
    await _server.close();
  }
}

/// [url] with its host and port swapped for the relay's, login, path and
/// query untouched.
String loopbackUrl(String url, int port) =>
    Uri.parse(url).replace(host: '127.0.0.1', port: port).toString();
