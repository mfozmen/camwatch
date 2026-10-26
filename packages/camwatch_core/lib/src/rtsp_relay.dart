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

  static final _length = RegExp(r'^content-length:\s*([+-]?\d+)', caseSensitive: false);
  static final _number = RegExp(r'^[+-]?(\d+)');

  /// The library takes the second word of a status line and reads it as
  /// atoi does: an optional sign, then digits, leading zeros included, and
  /// a run long enough to overflow wraps to whatever it wraps to. So any
  /// code longer than three digits is cut along with the 3xx ones, and a
  /// line that starts with a space is read both ways, in case the first
  /// word is skipped as empty; cutting one reply too many costs nothing.
  static bool _isRedirect(String line) {
    final words = line.trim().split(RegExp(r'\s+'));
    final candidates = [
      if (words.length > 1) words[1],
      if (line.startsWith(RegExp(r'\s'))) words[0],
    ];
    return candidates.any((word) {
      final digits = _number.firstMatch(word)?.group(1)?.replaceFirst(RegExp(r'^0+'), '');
      if (digits == null) return false;
      return digits.length > 3 ||
          (digits.length == 3 && digits.startsWith('3') && !word.startsWith('-'));
    });
  }

  /// Whether [chunk] completes a 3xx status line. Scan before forwarding:
  /// a reply in one chunk must not be passed on at all.
  bool redirects(List<int> chunk) {
    var i = 0;
    while (i < chunk.length) {
      final skipped = _skip(chunk.length - i);
      if (skipped > 0) {
        i += skipped;
        continue;
      }
      if (_endsLineAt(chunk[i++])) return true;
    }
    return false;
  }

  /// How many of the next [available] bytes belong to a frame or a body.
  int _skip(int available) {
    if (_frameLeft > 0) {
      final n = min(_frameLeft, available);
      _frameLeft -= n;
      return n;
    }
    final n = min(_bodyLeft, available);
    _bodyLeft -= n;
    return n;
  }

  bool _endsLineAt(int byte) {
    if (_frameHeader.isNotEmpty || (_line.isEmpty && byte == 0x24)) {
      _frameHeader.add(byte);
      if (_frameHeader.length == 4) {
        _frameLeft = (_frameHeader[2] << 8) | _frameHeader[3];
        _frameHeader.clear();
      }
      return false;
    }
    if (byte == 13) return false;
    if (byte != 10) {
      _line.add(byte);
      return false;
    }
    return _endsLine(latin1.decode(_line));
  }

  bool _endsLine(String line) {
    _line.clear();
    if (_atStatus) {
      if (line.isEmpty) return false;
      if (_isRedirect(line)) return true;
      _atStatus = false;
      _contentLength = 0;
    } else if (line.isEmpty) {
      _bodyLeft = _contentLength;
      _atStatus = true;
    } else if (_length.firstMatch(line) case final match?) {
      // Too long for an int: the library would wait for that body forever, so does the scan.
      _contentLength = max(0, int.tryParse(match.group(1)!) ?? 1 << 62);
    }
    return false;
  }
}

/// [url] with its host and port swapped for the relay's, login, path and
/// query untouched.
String loopbackUrl(String url, int port) =>
    Uri.parse(url).replace(host: '127.0.0.1', port: port).toString();
