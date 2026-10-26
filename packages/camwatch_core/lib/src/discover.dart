import 'interfaces.dart';
import 'lan.dart';
import 'mdns.dart';
import 'port_probe.dart';
import 'ws_discovery.dart';

/// The open [ports] of each of [hosts]; [probePorts] in the app.
typedef PortProbe = Future<Map<String, List<int>>> Function(
  Iterable<String> hosts,
  Iterable<int> ports,
);

/// Connects spent per scan on ports mDNS announced. Past that a flooder is
/// crowding out cameras, which the port probe lists anyway.
const maxMdnsClaimsPerScan = 128;

/// Runs the port probe, WS-Discovery and mDNS over the local subnet at once,
/// confirms the ports mDNS announced, then probes the [gradePorts] of every
/// host found, and returns one [Device] per host, or null when the device is
/// not on a LAN. [lock] wraps the whole scan: the app passes the Android
/// multicast lock, everything else runs bare.
Future<List<Device>?> discoverDevices({
  Future<({String address, int prefixLength})?> Function() network = scanNetwork,
  PortProbe ports = probePorts,
  Future<Map<String, String>> Function(String localAddress) onvif = discoverOnvif,
  Future<Map<String, List<int>>> Function(String localAddress) mdns = discoverMdns,
  Future<T> Function<T>(Future<T> Function() body) lock = _bare,
}) async {
  final lan = await network();
  if (lan == null) return null;
  return lock(() async {
    final hosts = subnetHosts(lan.address, lan.prefixLength);
    final (openPorts, found, announced) = await (
      ports(hosts, cameraPorts),
      onvif(lan.address),
      mdns(lan.address),
    ).wait;
    // A WS-Discovery sender may be off the subnet (a spoofed reply): it is listed, never probed.
    final inSubnet = hosts.toSet();
    final confirmed = await _confirm(announced, inSubnet, ports);
    final graded = await ports({
      ...openPorts.keys,
      ...found.keys.where(inSubnet.contains),
      ...confirmed.keys,
    }, gradePorts);
    final merged = {...openPorts};
    for (final open in [confirmed, graded]) {
      open.forEach((host, ports) => merged[host] = {...?merged[host], ...ports}.toList()..sort());
    }
    return mergeDiscovery(merged, found);
  });
}

/// The ports mDNS [announced] that answer a connect. A claim is believed on
/// no other evidence: in-subnet hosts only, never a port the first pass or
/// the grade probe decides, and at most [maxMdnsClaimsPerScan] connects.
Future<Map<String, List<int>>> _confirm(
  Map<String, List<int>> announced,
  Set<String> inSubnet,
  PortProbe ports,
) async {
  final claims = <String, List<int>>{};
  var budget = maxMdnsClaimsPerScan;
  for (final MapEntry(key: host, value: claimed) in announced.entries) {
    if (!inSubnet.contains(host)) continue;
    for (final port in claimed) {
      if (cameraPorts.contains(port) || gradePorts.contains(port) || budget-- <= 0) continue;
      claims.putIfAbsent(host, () => []).add(port);
    }
  }
  final results = await Future.wait([
    for (final MapEntry(key: host, value: claimed) in claims.entries) ports([host], claimed),
  ]);
  return {for (final result in results) ...result};
}

Future<T> _bare<T>(Future<T> Function() body) => body();
