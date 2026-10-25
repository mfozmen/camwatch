import 'dart:io';

import 'lan.dart';

/// Opens a TCP connection to [host]:[port] and closes it; throws when the
/// port is closed or [timeout] passes.
typedef Connector = Future<void> Function(String host, int port, Duration timeout);

/// The ports cameras usually answer on: RTSP (554, 8554), HTTP (80, 8080)
/// and the Hikvision/Dahua SDK port (8000).
const cameraPorts = [80, 554, 8000, 8080, 8554];

/// The open [ports] of each of [hosts], sorted; hosts with no open port are
/// left out. At most [concurrency] connections are in flight at once and
/// each waits at most [timeout]. Hosts outside the local network are never
/// contacted.
Future<Map<String, List<int>>> probePorts(
  Iterable<String> hosts, {
  Iterable<int> ports = cameraPorts,
  Connector connect = _tcpConnect,
  Duration timeout = const Duration(milliseconds: 500),
  int concurrency = 128,
}) async {
  final targets = [
    for (final host in hosts)
      if (isLocalIpv4(host))
        for (final port in ports) (host, port),
  ];
  final open = <String, List<int>>{};
  var next = 0;
  Future<void> worker() async {
    while (next < targets.length) {
      final (host, port) = targets[next++];
      try {
        await connect(host, port, timeout);
        open.putIfAbsent(host, () => []).add(port);
      } catch (_) {}
    }
  }

  await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
  for (final ports in open.values) {
    ports.sort();
  }
  return open;
}

Future<void> _tcpConnect(String host, int port, Duration timeout) async {
  final socket = await Socket.connect(host, port, timeout: timeout);
  socket.destroy();
}
