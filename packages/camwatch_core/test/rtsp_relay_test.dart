import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camwatch_core/camwatch_core.dart';
import 'package:test/test.dart';

/// A camera on 127.0.0.1 answering each request with the reply [answer] returns.
Future<ServerSocket> camera(String Function(String request) answer, List<String> seen) async {
  final server = await ServerSocket.bind('127.0.0.1', 0);
  server.listen((socket) {
    socket.listen((data) {
      final request = latin1.decode(data);
      seen.add(request.split('\r\n').first);
      socket.write(answer(request));
    });
  });
  return server;
}

Future<String> exchange(int port, String request) async {
  final socket = await Socket.connect('127.0.0.1', port);
  socket.write(request);
  final reply = latin1.decode(await socket.first);
  socket.destroy();
  return reply;
}

void main() {
  loopbackUrlTests();
  group('RtspRelay', () {
    test('passes requests and replies through unchanged, to the camera only', () async {
      final seen = <String>[];
      final cam = await camera(
        (_) => 'RTSP/1.0 200 OK\r\nCSeq: 7\r\nPublic: OPTIONS\r\n\r\n',
        seen,
      );
      final relay = await RtspRelay.start('127.0.0.1', cam.port);
      expect(relay.port, isNot(cam.port));
      final reply = await exchange(
        relay.port,
        'OPTIONS rtsp://127.0.0.1:${relay.port}/ RTSP/1.0\r\nCSeq: 7\r\n\r\n',
      );
      expect(reply, startsWith('RTSP/1.0 200 OK'));
      expect(seen, ['OPTIONS rtsp://127.0.0.1:${relay.port}/ RTSP/1.0']);
      expect(relay.redirected, isFalse);
      await relay.close();
      await cam.close();
    });

    test('cuts the connection on a 3xx reply before the player sees it', () async {
      final cam = await camera(
        (_) => 'RTSP/1.0 302 Found\r\nCSeq: 1\r\nLocation: rtsp://8.8.8.8/\r\n\r\n',
        [],
      );
      final relay = await RtspRelay.start('127.0.0.1', cam.port);
      final socket = await Socket.connect('127.0.0.1', relay.port);
      socket.write('DESCRIBE rtsp://127.0.0.1:${relay.port}/ RTSP/1.0\r\nCSeq: 1\r\n\r\n');
      final received = await socket.fold<List<int>>([], (acc, chunk) => acc..addAll(chunk));
      expect(received, isEmpty);
      await relay.onRedirect.timeout(const Duration(seconds: 2));
      expect(relay.redirected, isTrue);
      socket.destroy();
      await relay.close();
      await cam.close();
    });

    test('a redirect inside a longer burst is caught at a line start only', () async {
      final cam = await camera((_) => 'RTSP/1.0 200 OK\r\nCSeq: 1\r\nX: RTSP/1.0 301\r\n\r\n', []);
      final relay = await RtspRelay.start('127.0.0.1', cam.port);
      final reply = await exchange(relay.port, 'OPTIONS * RTSP/1.0\r\nCSeq: 1\r\n\r\n');
      expect(reply, contains('X: RTSP/1.0 301'));
      expect(relay.redirected, isFalse);
      await relay.close();
      await cam.close();
    });

    test('serves one connection and refuses the next', () async {
      final cam = await camera((_) => 'RTSP/1.0 200 OK\r\nCSeq: 1\r\n\r\n', []);
      final relay = await RtspRelay.start('127.0.0.1', cam.port);
      final first = await Socket.connect('127.0.0.1', relay.port);
      final second = await Socket.connect('127.0.0.1', relay.port);
      expect(await second.fold<int>(0, (n, chunk) => n + chunk.length), 0);
      first.destroy();
      second.destroy();
      await relay.close();
      await cam.close();
    });

    test('a camera that is down closes the player side', () async {
      final closed = await ServerSocket.bind('127.0.0.1', 0);
      final port = closed.port;
      await closed.close();
      final relay = await RtspRelay.start('127.0.0.1', port);
      final socket = await Socket.connect('127.0.0.1', relay.port);
      expect(await socket.fold<int>(0, (n, chunk) => n + chunk.length), 0);
      expect(relay.redirected, isFalse);
      await relay.close();
    });

    test('never relays to a host off the local network', () async {
      await expectLater(RtspRelay.start('8.8.8.8', 554), throwsArgumentError);
    });

    test('closing stops the listener and ends a live connection', () async {
      final cam = await camera((_) => 'RTSP/1.0 200 OK\r\nCSeq: 1\r\n\r\n', []);
      final relay = await RtspRelay.start('127.0.0.1', cam.port);
      final socket = await Socket.connect('127.0.0.1', relay.port);
      final done = socket.fold<int>(0, (n, chunk) => n + chunk.length);
      await relay.close();
      expect(await done, 0);
      await expectLater(Socket.connect('127.0.0.1', relay.port), throwsA(isA<SocketException>()));
      await cam.close();
    });
  });
}

void loopbackUrlTests() {
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
}
