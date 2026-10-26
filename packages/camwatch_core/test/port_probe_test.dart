import 'dart:async';
import 'dart:io';

import 'package:camwatch_core/camwatch_core.dart';
import 'package:test/test.dart';

/// A connector that succeeds for the (host, port) pairs in [open].
Connector fake(Set<(String, int)> open) => (host, port, timeout) async {
  if (!open.contains((host, port))) throw const SocketException('refused');
};

void main() {
  group('probePorts', () {
    test('reports the open ports per host, sorted, and drops silent hosts', () async {
      final result = await probePorts(
        ['192.168.1.10', '192.168.1.11', '192.168.1.12'],
        [8554, 80, 554],
        connect: fake({('192.168.1.10', 554), ('192.168.1.10', 80), ('192.168.1.12', 8554)}),
      );
      expect(result, {
        '192.168.1.10': [80, 554],
        '192.168.1.12': [8554],
      });
    });

    test('never connects outside the local network', () async {
      final tried = <String>[];
      await probePorts(
        ['8.8.8.8', '192.168.1.10'],
        [554],
        connect: (host, port, timeout) async => tried.add(host),
      );
      expect(tried, ['192.168.1.10']);
    });

    test('keeps at most `concurrency` connections in flight', () async {
      var inFlight = 0, peak = 0;
      await probePorts(
        [for (var i = 1; i < 50; i++) '10.0.0.$i'],
        [80, 554],
        concurrency: 8,
        connect: (host, port, timeout) async {
          inFlight++;
          peak = peak > inFlight ? peak : inFlight;
          await Future<void>.delayed(const Duration(milliseconds: 1));
          inFlight--;
        },
      );
      expect(peak, 8);
    });

    test('the default connector opens a TCP connection and closes it', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final closed = Completer<void>();
      server.listen((socket) => socket.listen(null, onDone: closed.complete));
      final result = await probePorts(['127.0.0.1'], [server.port, 1]);
      await closed.future.timeout(const Duration(seconds: 5));
      await server.close();
      expect(result, {
        '127.0.0.1': [server.port],
      });
    });
  });
}
