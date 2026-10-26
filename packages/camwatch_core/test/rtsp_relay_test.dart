import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camwatch_core/camwatch_core.dart';
import 'package:test/test.dart';

const crlf = '\r\n';
const ok = 'RTSP/1.0 200 OK${crlf}CSeq: 1$crlf$crlf';
const found = 'RTSP/1.0 302 Found${crlf}CSeq: 1${crlf}Location: rtsp://8.8.8.8/$crlf$crlf';

/// A camera on 127.0.0.1 answering each request with the writes [answer] returns.
Future<ServerSocket> camera(
  List<List<int>> Function(String request) answer, [
  List<String>? seen,
]) async {
  final server = await ServerSocket.bind('127.0.0.1', 0);
  server.listen((socket) {
    socket.listen((data) async {
      final request = latin1.decode(data);
      seen?.add(request.split(crlf).first);
      for (final write in answer(request)) {
        socket.add(write);
        await socket.flush();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
  });
  return server;
}

List<List<int>> Function(String) says(String reply) =>
    (_) => [latin1.encode(reply)];

/// Sends one request through the relay and returns everything that came back.
Future<String> exchange(int port, String request) async {
  final socket = await Socket.connect('127.0.0.1', port);
  socket.write(request);
  final reply = await socket
      .timeout(const Duration(milliseconds: 300), onTimeout: (sink) => sink.close())
      .fold<List<int>>([], (acc, chunk) => acc..addAll(chunk));
  socket.destroy();
  return latin1.decode(reply);
}

void main() {
  test('loopbackUrl keeps the login, path and query, swapping only the authority', () {
    expect(
      loopbackUrl(
        'rtsp://ad%3Amin:p%40ss%2F@192.168.1.10:554/cam/realmonitor?channel=1&subtype=0',
        5000,
      ),
      'rtsp://ad%3Amin:p%40ss%2F@127.0.0.1:5000/cam/realmonitor?channel=1&subtype=0',
    );
    expect(loopbackUrl('rtsp://192.168.1.10:8554/', 5001), 'rtsp://127.0.0.1:5001/');
  });

  group('RtspRelay', () {
    late ServerSocket cam;
    late RtspRelay relay;

    Future<void> up(List<List<int>> Function(String) answer, [List<String>? seen]) async {
      cam = await camera(answer, seen);
      relay = await RtspRelay.start('127.0.0.1', cam.port);
    }

    tearDown(() async {
      await relay.close();
      await cam.close();
    });

    test('passes requests and replies through unchanged, to the camera only', () async {
      final seen = <String>[];
      await up(says('RTSP/1.0 200 OK${crlf}CSeq: 7${crlf}Public: OPTIONS$crlf$crlf'), seen);
      expect(relay.port, isNot(cam.port));
      final request = 'OPTIONS rtsp://127.0.0.1:${relay.port}/ RTSP/1.0${crlf}CSeq: 7$crlf$crlf';
      expect(await exchange(relay.port, request), startsWith('RTSP/1.0 200 OK'));
      expect(seen, ['OPTIONS rtsp://127.0.0.1:${relay.port}/ RTSP/1.0']);
      expect(relay.redirected, isFalse);
    });

    group('cuts the connection before a redirect is whole', () {
      final evasions = <String, List<String>>{
        'a plain 302': [found],
        'a 302 split across writes': [
          'RTSP/1.0 30',
          '2 Found${crlf}Location: rtsp://8.8.8.8/$crlf$crlf',
        ],
        'another protocol token': ['RTSP/2.0 302 Found${crlf}Location: rtsp://8.8.8.8/$crlf$crlf'],
        'no reason phrase': ['RTSP/1.0 301${crlf}Location: rtsp://8.8.8.8/$crlf$crlf'],
        'a 3xx pipelined after a body with no trailing newline': [
          'RTSP/1.0 200 OK${crlf}CSeq: 1${crlf}Content-Length: 5$crlf${crlf}v=0\r\n$found',
        ],
        'a 3xx after a header that only mentions one': [
          'RTSP/1.0 200 OK${crlf}X: RTSP/1.0 301$crlf$crlf$found',
        ],
        'leading zeros, read as atoi does': [
          'RTSP/1.0 0301 Moved${crlf}Location: rtsp://8.8.8.8/$crlf$crlf',
        ],
        'a plus sign': ['RTSP/1.0 +302${crlf}Location: rtsp://8.8.8.8/$crlf$crlf'],
        'a leading space, whichever token the library takes': [
          ' 302 Found${crlf}Location: rtsp://8.8.8.8/$crlf$crlf',
        ],
        'a tab between the tokens': [
          'RTSP/1.0	302 Found${crlf}Location: rtsp://8.8.8.8/$crlf$crlf',
        ],
        'a code that wraps to 300 in a 32-bit int': [
          'RTSP/1.0 4294967596 x${crlf}Location: rtsp://8.8.8.8/$crlf$crlf',
        ],
        'a code that wraps in a 64-bit long, split': [
          'RTSP/1.0 184467440737',
          '09551916 x${crlf}Location: rtsp://8.8.8.8/$crlf$crlf',
        ],
        'a negative code that wraps to 300': [
          'RTSP/1.0 -4294966996 x${crlf}Location: rtsp://8.8.8.8/$crlf$crlf',
        ],
      };
      for (final MapEntry(key: name, value: writes) in evasions.entries) {
        test(name, () async {
          await up((_) => [for (final w in writes) latin1.encode(w)]);
          final reply = await exchange(relay.port, 'DESCRIBE * RTSP/1.0${crlf}CSeq: 1$crlf$crlf');
          expect(reply, isNot(contains('Location')));
          await relay.onRedirect.timeout(const Duration(seconds: 2));
          expect(relay.redirected, isTrue);
        });
      }

      test('a 302 split at any byte', () async {
        for (var at = 1; at < found.length; at += 7) {
          await up(
            (_) => [latin1.encode(found.substring(0, at)), latin1.encode(found.substring(at))],
          );
          final reply = await exchange(relay.port, 'DESCRIBE * RTSP/1.0${crlf}CSeq: 1$crlf$crlf');
          expect(reply, isNot(contains('Location')), reason: 'split at $at');
          await relay.onRedirect.timeout(const Duration(seconds: 2));
          await relay.close();
          await cam.close();
        }
        await up(says(ok));
      });
    });

    test(
      'a Content-Length too long for an int swallows the rest, like the library would',
      () async {
        await up(
          says(
            'RTSP/1.0 200 OK${crlf}Content-Length: 99999999999999999999999$crlf$crlf'
            'RTSP/1.0 302 Found${crlf}Location: rtsp://8.8.8.8/$crlf$crlf',
          ),
        );
        final reply = await exchange(relay.port, 'DESCRIBE * RTSP/1.0${crlf}CSeq: 1$crlf$crlf');
        expect(reply, contains('Content-Length'));
        expect(relay.redirected, isFalse);
      },
    );

    test('a 3xx with a code the library would not read as one is passed on', () async {
      await up(says('RTSP/1.0 -301 Odd${crlf}CSeq: 1$crlf$crlf'));
      final reply = await exchange(relay.port, 'DESCRIBE * RTSP/1.0${crlf}CSeq: 1$crlf$crlf');
      expect(reply, contains('-301'));
      expect(relay.redirected, isFalse);
    });

    test('a 3xx inside a header line or interleaved media is not a redirect', () async {
      final frame = latin1.encode('RTSP/1.0 302 x');
      await up(
        (_) => [
          latin1.encode('RTSP/1.0 200 OK${crlf}X: RTSP/1.0 301$crlf$crlf'),
          [0x24, 0, frame.length >> 8, frame.length & 0xff, ...frame],
          latin1.encode(ok),
        ],
      );
      final reply = await exchange(relay.port, 'PLAY * RTSP/1.0${crlf}CSeq: 1$crlf$crlf');
      expect(reply, contains('X: RTSP/1.0 301'));
      expect(reply, contains('RTSP/1.0 302 x'));
      expect(reply, endsWith(ok));
      expect(relay.redirected, isFalse);
    });

    test('serves one connection and refuses the next', () async {
      await up(says(ok));
      final first = await Socket.connect('127.0.0.1', relay.port);
      final second = await Socket.connect('127.0.0.1', relay.port);
      expect(await second.fold<int>(0, (n, chunk) => n + chunk.length), 0);
      first.destroy();
      second.destroy();
    });

    test('a camera that is down closes the player side', () async {
      await up(says(ok));
      final gone = await ServerSocket.bind('127.0.0.1', 0);
      final port = gone.port;
      await gone.close();
      final lonely = await RtspRelay.start('127.0.0.1', port);
      final socket = await Socket.connect('127.0.0.1', lonely.port);
      expect(await socket.fold<int>(0, (n, chunk) => n + chunk.length), 0);
      expect(lonely.redirected, isFalse);
      await lonely.close();
    });

    test('never relays to a host off the local network', () async {
      await up(says(ok));
      await expectLater(RtspRelay.start('8.8.8.8', 554), throwsArgumentError);
    });

    test('closing stops the listener and ends a live connection', () async {
      await up(says(ok));
      final socket = await Socket.connect('127.0.0.1', relay.port);
      final done = socket.fold<int>(0, (n, chunk) => n + chunk.length);
      await relay.close();
      expect(await done, 0);
      await expectLater(Socket.connect('127.0.0.1', relay.port), throwsA(isA<SocketException>()));
    });
  });
}
