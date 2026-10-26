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

/// Runs the port probe, WS-Discovery and mDNS over the local subnet at once,
/// then probes the [gradePorts] of the hosts found and the ports mDNS
/// announced, and returns one [Device] per host, or null when the device is
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
    // An mDNS claim is only believed once a connect confirms it, and only
    // for a port the first pass did not already try.
    final claims = {
      for (final MapEntry(key: host, value: claimed) in announced.entries)
        if (inSubnet.contains(host))
          host: claimed.where((port) => !cameraPorts.contains(port)).toList(),
    }..removeWhere((_, claimed) => claimed.isEmpty);
    final (graded, confirmed) = await (
      ports({...openPorts.keys, ...found.keys.where(inSubnet.contains)}, gradePorts),
      Future.wait([
        for (final MapEntry(key: host, value: claimed) in claims.entries) ports([host], claimed),
      ]),
    ).wait;
    final merged = {...openPorts};
    for (final open in [graded, ...confirmed]) {
      open.forEach((host, ports) => merged[host] = {...?merged[host], ...ports}.toList()..sort());
    }
    return mergeDiscovery(merged, found);
  });
}

Future<T> _bare<T>(Future<T> Function() body) => body();
