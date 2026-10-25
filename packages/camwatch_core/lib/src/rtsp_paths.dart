import 'dart:convert';
import 'dart:io';

import 'lan.dart';

/// Sends one RTSP [request] to [host]:[port] and returns the reply head;
/// throws when the camera does not answer within [timeout].
typedef RtspExchange = Future<String> Function(
  String host,
  int port,
  String request,
  Duration timeout,
);

/// What a DESCRIBE of one path came back with.
enum PathStatus { open, needsAuth, missing, error }

/// Stream paths cameras commonly serve, most common first.
const streamPaths = [
  '/',
  '/live',
  '/stream1',
  '/h264',
  '/ch0_0.h264',
  '/11',
  '/live/ch00_0',
  '/Streaming/Channels/101',
  '/cam/realmonitor?channel=1&subtype=0',
  '/onvif1',
];

/// A reply head longer than this is not a camera talking RTSP.
const maxRtspReplyBytes = 8 * 1024;

/// Asks [host]:[port] for each of [paths] with a DESCRIBE, one after the
/// other, and tells open (200), password-protected (401) and missing paths
/// apart. A host off the local network is never asked.
Future<Map<String, PathStatus>> probeStreamPaths(
  String host,
  int port, {
  Iterable<String> paths = streamPaths,
  RtspExchange exchange = _tcpExchange,
  Duration timeout = const Duration(seconds: 2),
}) async {
  if (!isLocalIpv4(host)) return const {};
  final result = <String, PathStatus>{};
  for (final path in paths) {
    final request =
        'DESCRIBE rtsp://$host:$port$path RTSP/1.0\r\n'
        'CSeq: 1\r\nUser-Agent: camwatch\r\nAccept: application/sdp\r\n\r\n';
    try {
      result[path] = _status(await exchange(host, port, request, timeout));
    } catch (_) {
      result[path] = PathStatus.error;
    }
  }
  return result;
}

/// The first path in [result] that streams without a password, or null.
String? firstOpenPath(Map<String, PathStatus> result) =>
    result.entries.where((e) => e.value == PathStatus.open).map((e) => e.key).firstOrNull;

PathStatus _status(String reply) =>
    switch (RegExp(r'^RTSP/1\.0 (\d{3})').firstMatch(reply)?.group(1)) {
      '200' => PathStatus.open,
      '401' => PathStatus.needsAuth,
      null => PathStatus.error,
      _ => PathStatus.missing,
    };

Future<String> _tcpExchange(String host, int port, String request, Duration timeout) async {
  final socket = await Socket.connect(host, port, timeout: timeout);
  try {
    socket.write(request);
    final head = StringBuffer();
    await for (final chunk in socket.timeout(timeout)) {
      head.write(latin1.decode(chunk));
      if (head.toString().contains('\r\n\r\n')) break;
      if (head.length > maxRtspReplyBytes) throw const FormatException('reply head too long');
    }
    return head.toString();
  } finally {
    socket.destroy();
  }
}
