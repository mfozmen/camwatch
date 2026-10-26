import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camwatch_core/camwatch_core.dart';
import 'package:test/test.dart';

/// An exchange answering from [replies] by path, "404" for the rest.
RtspExchange fake(Map<String, String> replies) => (host, port, request, timeout) async {
  final path = RegExp(r'DESCRIBE rtsp://[^/]+(/\S*) RTSP/1\.0').firstMatch(request)!.group(1)!;
  return 'RTSP/1.0 ${replies[path] ?? '404 Not Found'}\r\nCSeq: 1\r\n\r\n';
};

void main() {
  group('probeStreamPaths', () {
    test(
      'tells open, password-protected and missing paths apart, stopping at the open one',
      () async {
        final result = await probeStreamPaths(
          '192.168.1.10',
          554,
          paths: ['/', '/h264', '/live', '/stream1'],
          exchange: fake({'/': '401 Unauthorized', '/live': '200 OK'}),
        );
        expect(result, {
          '/': PathStatus.needsAuth,
          '/h264': PathStatus.missing,
          '/live': PathStatus.open,
        });
        expect(firstPath(result, PathStatus.open), '/live');
      },
    );

    test('asks each path with a DESCRIBE for SDP, in order', () async {
      final requests = <String>[];
      await probeStreamPaths(
        '10.0.0.5',
        8554,
        paths: ['/a', '/b'],
        exchange: (host, port, request, timeout) async {
          requests.add('$host:$port ${request.split('\r\n').first}');
          expect(request, contains('Accept: application/sdp'));
          return 'RTSP/1.0 ${request.contains('/b ') ? '200 OK' : '404 Not Found'}\r\n\r\n';
        },
      );
      expect(requests, [
        '10.0.0.5:8554 DESCRIBE rtsp://10.0.0.5:8554/a RTSP/1.0',
        '10.0.0.5:8554 DESCRIBE rtsp://10.0.0.5:8554/b RTSP/1.0',
      ]);
    });

    test('a failed or garbled exchange is an error, and nothing is open', () async {
      final result = await probeStreamPaths(
        '192.168.1.10',
        554,
        paths: ['/', '/live'],
        exchange: (host, port, request, timeout) async => request.contains('/live')
            ? 'HTTP/1.1 200 OK\r\n\r\n'
            : throw const SocketException('reset'),
      );
      expect(result, {'/': PathStatus.error, '/live': PathStatus.error});
      expect(firstPath(result, PathStatus.open), isNull);
    });

    test('never probes outside the local network', () async {
      var asked = false;
      final result = await probeStreamPaths(
        '8.8.8.8',
        554,
        exchange: (host, port, request, timeout) async {
          asked = true;
          return '';
        },
      );
      expect(result, isEmpty);
      expect(asked, isFalse);
    });

    test('the default paths start with the root and are all absolute', () {
      expect(streamPaths.first, '/');
      expect(streamPaths, everyElement(startsWith('/')));
    });
  });

  group('the default exchange', () {
    Future<ServerSocket> camera(void Function(Socket) handle) async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen(handle);
      return server;
    }

    test('reads the reply head over TCP and closes', () async {
      final server = await camera((socket) async {
        final request = utf8.decode(await socket.first);
        expect(request, startsWith('DESCRIBE rtsp://127.0.0.1:'));
        socket.write('RTSP/1.0 200 OK\r\nCSeq: 1\r\nContent-Length: 2\r\n\r\nv=');
        await socket.flush();
      });
      final result = await probeStreamPaths('127.0.0.1', server.port, paths: ['/live']);
      await server.close();
      expect(result, {'/live': PathStatus.open});
    });

    test('gives up on a reply that never ends, never comes or drips slowly', () async {
      const timeout = Duration(milliseconds: 400);
      final server = await camera((socket) {
        socket.listen((request) async {
          final path = utf8.decode(request).split(' ')[1];
          if (path.endsWith('/mute')) return;
          if (path.endsWith('/x')) {
            socket.add(List.filled(65536, 0x61));
          } else {
            for (var i = 0; i < 6; i++) {
              socket.add([0x61]);
              await Future<void>.delayed(timeout ~/ 2);
            }
          }
        }, onDone: socket.destroy);
      });
      final started = DateTime.now();
      final result = await probeStreamPaths(
        '127.0.0.1',
        server.port,
        paths: ['/x', '/slow', '/mute'],
        timeout: timeout,
      );
      await server.close();
      expect(result, {
        '/x': PathStatus.error,
        '/slow': PathStatus.error,
        '/mute': PathStatus.error,
      });
      expect(DateTime.now().difference(started), lessThan(timeout * 4));
    });
  });
}
