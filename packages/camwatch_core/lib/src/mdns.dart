import 'dart:io';

import 'lan.dart';
import 'ws_discovery.dart';

/// The mDNS group and port (RFC 6762).
final mdnsGroup = InternetAddress('224.0.0.251');
const mdnsPort = 5353;

/// RFC 6762 caps a message at 9000 bytes; anything longer is not mDNS.
const maxMdnsBytes = 9000;

/// Ports kept per responder: a camera announces one or two services; a
/// reply listing more is padding, and every kept port costs a connect later.
const maxMdnsPortsPerHost = 8;

/// The services a camera announces. Not `_http._tcp`: every printer and
/// NAS does, and it says nothing about cameras.
const mdnsServices = ['_rtsp._tcp.local', '_onvif._tcp.local'];

const _ptr = 12;
const _srv = 33;

/// One standard query asking for every instance of [mdnsServices].
List<int> mdnsQuery() => [
  0,
  0,
  0,
  0,
  0,
  mdnsServices.length,
  0,
  0,
  0,
  0,
  0,
  0,
  for (final service in mdnsServices) ...[..._name(service), 0, _ptr, 0, 1],
];

List<int> _name(String name) => [
  for (final label in name.split('.')) ...[label.length, ...label.codeUnits],
  0,
];

/// The SRV ports of the RTSP and ONVIF instances in one DNS [message], in
/// order. Garbage, a truncated record or a pointer loop ends the read with
/// what was found before it.
List<int> mdnsPorts(List<int> message) {
  final ports = <int>[];
  try {
    final reader = _Reader(message);
    reader.skip(4);
    final questions = reader.u16();
    final records = reader.u16() + reader.u16() + reader.u16();
    for (var i = 0; i < questions; i++) {
      reader.name();
      reader.skip(4);
    }
    for (var i = 0; i < records; i++) {
      final owner = reader.name();
      final type = reader.u16();
      reader.skip(6);
      final length = reader.u16();
      final next = reader.at + length;
      if (next > message.length) break;
      if (type == _srv && length >= 6 && _isCamera(owner)) {
        reader.skip(4);
        ports.add(reader.u16());
      }
      reader.at = next;
    }
  } on RangeError {
    // The message ended inside a record: keep what came before it.
  }
  return ports;
}

bool _isCamera(String owner) {
  final lower = owner.toLowerCase();
  return mdnsServices.any((service) => lower.endsWith('.$service'));
}

/// Sends one query from [localAddress] to [target]:[port] and, for [wait],
/// collects the camera service ports each local responder announces, keyed
/// by the address it answered from. The ports are a claim, not a fact: the
/// scan confirms each with a connect before it lists one.
Future<Map<String, List<int>>> discoverMdns(
  String localAddress, {
  InternetAddress? target,
  int port = mdnsPort,
  Duration wait = const Duration(seconds: 2),
}) async {
  if (target != null && !isLocalIpv4(target.address)) {
    throw ArgumentError.value(target, 'target', 'not on the local network');
  }
  final socket = await RawDatagramSocket.bind(localAddress, 0);
  final found = <String, List<int>>{};
  // shortcut: no onError, a multicast send gets no ICMP error event; add one if a unicast target ever ships.
  socket.listen((_) => _collect(found, socket.receive()));
  try {
    socket.send(mdnsQuery(), target ?? mdnsGroup, port);
    await Future<void>.delayed(wait);
  } finally {
    socket.close();
  }
  for (final ports in found.values) {
    ports.sort();
  }
  return found;
}

void _collect(Map<String, List<int>> found, Datagram? datagram) {
  if (datagram == null || datagram.data.length > maxMdnsBytes) return;
  final sender = datagram.address.address;
  if (!isLocalIpv4(sender) || (!found.containsKey(sender) && found.length >= maxSenders)) return;
  final ports = found.putIfAbsent(sender, () => []);
  for (final port in mdnsPorts(datagram.data)) {
    if (ports.length >= maxMdnsPortsPerHost) break;
    if (!ports.contains(port)) ports.add(port);
  }
  if (ports.isEmpty) found.remove(sender);
}

/// A cursor over a DNS message; every read past the end throws RangeError.
class _Reader {
  _Reader(this.bytes);

  final List<int> bytes;
  var at = 0;

  int u8() => bytes[at++];

  int u16() => (u8() << 8) | u8();

  void skip(int n) => at += n;

  /// A name, following compression pointers; more than 16 jumps is a loop,
  /// more than 255 bytes of labels is not a name (RFC 1035) but busywork.
  String name() {
    final labels = <String>[];
    var cursor = at;
    int? resume;
    var jumps = 0;
    var total = 0;
    while (true) {
      final length = bytes[cursor++];
      if (length == 0) break;
      if (length & 0xC0 == 0xC0) {
        if (++jumps > 16) throw RangeError('pointer loop');
        final offset = ((length & 0x3F) << 8) | bytes[cursor++];
        resume ??= cursor;
        cursor = offset;
        continue;
      }
      if ((total += length) > 255) throw RangeError('name too long');
      labels.add(String.fromCharCodes(bytes.sublist(cursor, cursor + length)));
      cursor += length;
    }
    at = resume ?? cursor;
    return labels.join('.');
  }
}
