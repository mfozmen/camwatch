import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'lan.dart';

/// One RTSP connection relayed from 127.0.0.1 to a camera on the LAN. A
/// 3xx reply is cut before it is whole, so the player library, which would
/// follow a redirect on its own with the login in hand, never sees one.
/// The player is pointed at [port] instead of the camera. The first local
/// connection is served, any other refused: mpv connects right after
/// `loadfile`, and a stranger who wins that race only gets a pipe to a
/// camera it could reach itself.
class RtspRelay {
  RtspRelay._(this._server, this._host, this._port);

  final ServerSocket _server;
  final String _host;
  final int _port;
  Socket? _client;
  Future<Socket>? _camera;
  final _redirect = Completer<void>();

  static Future<RtspRelay> start(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!isLocalIpv4(host)) throw ArgumentError.value(host, 'host', 'not on the local network');
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final relay = RtspRelay._(server, host, port);
    server.listen((client) => relay._accept(client, timeout));
    return relay;
  }

  /// Where the player connects.
  int get port => _server.port;

  /// Whether the camera answered with a redirect; [onRedirect] completes then.
  bool get redirected => _redirect.isCompleted;
  Future<void> get onRedirect => _redirect.future;

  Future<void> _accept(Socket client, Duration timeout) async {
    if (_client != null) return client.destroy();
    _client = client;
    final connecting = Socket.connect(_host, _port, timeout: timeout);
    _camera = connecting;
    Socket camera;
    try {
      camera = await connecting;
    } catch (_) {
      return client.destroy();
    }
    // One tear-off serves done and error alike: either way the other end closes.
    void cut([Object? _, StackTrace? _]) {
      camera.destroy();
      client.destroy();
    }

    final replies = _ReplyScanner();
    client.listen(camera.add, onDone: cut, onError: cut);
    camera.listen(
      (chunk) {
        if (replies.redirects(chunk)) {
          if (!_redirect.isCompleted) _redirect.complete();
          return cut();
        }
        client.add(chunk);
      },
      onDone: cut,
      onError: cut,
    );
  }

  /// Ends the listener and any live connection, including one still being
  /// made to the camera.
  Future<void> close() async {
    _client?.destroy();
    unawaited(_camera?.then((camera) => camera.destroy(), onError: (_) {}));
    await _server.close();
  }
}

/// Reads the camera's replies the way FFmpeg does, across chunk boundaries:
/// the first token of a status line is not checked and the second is read
/// as a number, a body is skipped by Content-Length, and a `$` at a line
/// start opens an interleaved media frame. Anything looser than this lets a
/// hostile camera shape a redirect the library accepts and the relay misses.
class _ReplyScanner {
  final _line = <int>[];
  final _frameHeader = <int>[];
  var _atStatus = true;
  var _contentLength = 0;
  var _bodyLeft = 0;
  var _frameLeft = 0;

  static final _redirect = RegExp(r'^\S+\s+\+?3\d\d');
  static final _length = RegExp(r'^content-length:\s*([+-]?\d+)', caseSensitive: false);

  /// Whether [chunk] completes a 3xx status line. Scan before forwarding:
  /// a reply in one chunk must not be passed on at all.
  bool redirects(List<int> chunk) {
    var i = 0;
    while (i < chunk.length) {
      if (_frameLeft > 0 || _bodyLeft > 0) {
        final skipped = min(_frameLeft > 0 ? _frameLeft : _bodyLeft, chunk.length - i);
        if (_frameLeft > 0) {
          _frameLeft -= skipped;
        } else {
          _bodyLeft -= skipped;
        }
        i += skipped;
        continue;
      }
      final byte = chunk[i++];
      if (_frameHeader.isNotEmpty || (_line.isEmpty && byte == 0x24)) {
        _frameHeader.add(byte);
        if (_frameHeader.length == 4) {
          _frameLeft = (_frameHeader[2] << 8) | _frameHeader[3];
          _frameHeader.clear();
        }
        continue;
      }
      if (byte == 13) continue;
      if (byte != 10) {
        _line.add(byte);
        continue;
      }
      if (_endsLine(latin1.decode(_line))) return true;
    }
    return false;
  }

  bool _endsLine(String line) {
    _line.clear();
    if (_atStatus) {
      if (line.isEmpty) return false;
      if (_redirect.hasMatch(line)) return true;
      _atStatus = false;
      _contentLength = 0;
    } else if (line.isEmpty) {
      _bodyLeft = _contentLength;
      _atStatus = true;
    } else if (_length.firstMatch(line) case final match?) {
      _contentLength = max(0, int.parse(match.group(1)!));
    }
    return false;
  }
}

/// [url] with its host and port swapped for the relay's, login, path and
/// query untouched.
String loopbackUrl(String url, int port) =>
    Uri.parse(url).replace(host: '127.0.0.1', port: port).toString();
