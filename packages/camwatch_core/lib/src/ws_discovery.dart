import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'lan.dart';

/// The WS-Discovery multicast group ONVIF cameras listen on.
final wsDiscoveryGroup = InternetAddress('239.255.255.250');
const wsDiscoveryPort = 3702;

/// Replies larger than this are dropped unread: a ProbeMatch is a few
/// hundred bytes, anything bigger is not a camera talking.
const maxProbeMatchBytes = 16 * 1024;

/// A WS-Discovery Probe for ONVIF network video transmitters.
String probeMessage() =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<e:Envelope xmlns:e="http://www.w3.org/2003/05/soap-envelope" '
    'xmlns:w="http://schemas.xmlsoap.org/ws/2004/08/addressing" '
    'xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery" '
    'xmlns:dn="http://www.onvif.org/ver10/network/wsdl">'
    '<e:Header><w:MessageID>urn:uuid:${_uuid()}</w:MessageID>'
    '<w:To e:mustUnderstand="true">urn:schemas-xmlsoap-org:ws:2005:04:discovery</w:To>'
    '<w:Action e:mustUnderstand="true">http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</w:Action>'
    '</e:Header><e:Body><d:Probe><d:Types>dn:NetworkVideoTransmitter</d:Types></d:Probe></e:Body>'
    '</e:Envelope>';

String _uuid() {
  final random = Random.secure();
  final hex = [for (var i = 0; i < 16; i++) random.nextInt(256).toRadixString(16).padLeft(2, '0')]
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

final _xaddrs = RegExp(r'<(?:\w+:)?XAddrs>([^<]*)</(?:\w+:)?XAddrs>');

/// The local HTTP device service addresses in a ProbeMatch [reply]. A
/// regular expression, not an XML parser: nothing resolves entities.
List<String> parseProbeMatch(String reply) => [
  for (final match in _xaddrs.allMatches(reply))
    for (final url in match.group(1)!.trim().split(RegExp(r'\s+')))
      if (url.startsWith('http://') && isLocalIpv4(Uri.tryParse(url)?.host ?? '')) url,
];

/// Sends one Probe from [localAddress] to [target]:[port] and, for [wait],
/// collects every local camera's device service address keyed by the
/// address it answered from. Only an address on that same host counts: a
/// reply cannot point the app at another device. [target] is the
/// WS-Discovery group unless a test passes a local address.
Future<Map<String, String>> discoverOnvif(
  String localAddress, {
  InternetAddress? target,
  int port = wsDiscoveryPort,
  Duration wait = const Duration(seconds: 2),
}) async {
  if (target != null && !isLocalIpv4(target.address)) {
    throw ArgumentError.value(target, 'target', 'not on the local network');
  }
  final socket = await RawDatagramSocket.bind(localAddress, 0);
  final found = <String, String>{};
  socket.listen((_) {
    final datagram = socket.receive();
    if (datagram == null || datagram.data.length > maxProbeMatchBytes) return;
    final sender = datagram.address.address;
    if (!isLocalIpv4(sender)) return;
    for (final url in parseProbeMatch(utf8.decode(datagram.data, allowMalformed: true))) {
      if (Uri.parse(url).host == sender) found.putIfAbsent(sender, () => url);
    }
  });
  // shortcut: no onError, a multicast send gets no ICMP error event; add one if a unicast target ever ships.
  try {
    socket.send(utf8.encode(probeMessage()), target ?? wsDiscoveryGroup, port);
    await Future<void>.delayed(wait);
  } finally {
    socket.close();
  }
  return found;
}

/// A host the scan found: its open camera ports and, when it answered
/// WS-Discovery, its ONVIF device service address.
class Device {
  const Device(this.address, {required this.openPorts, this.onvifAddress});

  final String address;
  final List<int> openPorts;
  final String? onvifAddress;

  /// The port to stream from, 554 before 8554, or null without RTSP.
  int? get rtspPort => [554, 8554].where(openPorts.contains).firstOrNull;

  @override
  bool operator ==(Object other) =>
      other is Device &&
      other.address == address &&
      other.onvifAddress == onvifAddress &&
      other.openPorts.join(',') == openPorts.join(',');

  @override
  int get hashCode => Object.hash(address, onvifAddress, openPorts.join(','));

  @override
  String toString() => 'Device($address, ports: $openPorts, onvif: $onvifAddress)';
}

/// One [Device] per host seen by the port probe or WS-Discovery, by address.
List<Device> mergeDiscovery(Map<String, List<int>> openPorts, Map<String, String> onvif) {
  final hosts = {...openPorts.keys, ...onvif.keys}.toList()..sort(_byAddress);
  return [
    for (final host in hosts)
      Device(host, openPorts: openPorts[host] ?? const [], onvifAddress: onvif[host]),
  ];
}

int _byAddress(String a, String b) {
  final left = a.split('.').map(int.parse).toList();
  final right = b.split('.').map(int.parse).toList();
  for (var i = 0; i < 4; i++) {
    if (left[i] != right[i]) return left[i] - right[i];
  }
  return 0;
}
