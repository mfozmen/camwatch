import 'interfaces.dart';
import 'lan.dart';
import 'port_probe.dart';
import 'ws_discovery.dart';

/// The open [ports] of each of [hosts]; [probePorts] in the app.
typedef PortProbe = Future<Map<String, List<int>>> Function(
  Iterable<String> hosts,
  Iterable<int> ports,
);

/// Runs the port probe and WS-Discovery over the local subnet at once, then
/// probes the [gradePorts] of the hosts found, and returns one [Device] per
/// host, or null when the device is not on a LAN. [lock] wraps the whole
/// scan: the app passes the Android multicast lock, everything else runs bare.
Future<List<Device>?> discoverDevices({
  Future<({String address, int prefixLength})?> Function() network = scanNetwork,
  PortProbe ports = probePorts,
  Future<Map<String, String>> Function(String localAddress) onvif = discoverOnvif,
  Future<T> Function<T>(Future<T> Function() body) lock = _bare,
}) async {
  final lan = await network();
  if (lan == null) return null;
  return lock(() async {
    final hosts = subnetHosts(lan.address, lan.prefixLength);
    final (openPorts, found) = await (ports(hosts, cameraPorts), onvif(lan.address)).wait;
    // A WS-Discovery sender may be off the subnet (a spoofed reply): it is listed, never probed.
    final inSubnet = hosts.toSet();
    final graded = await ports({
      ...openPorts.keys,
      ...found.keys.where(inSubnet.contains),
    }, gradePorts);
    final merged = {...openPorts};
    graded.forEach((host, open) => merged[host] = [...?merged[host], ...open]..sort());
    return mergeDiscovery(merged, found);
  });
}

Future<T> _bare<T>(Future<T> Function() body) => body();
