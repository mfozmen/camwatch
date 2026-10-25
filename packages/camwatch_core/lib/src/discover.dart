import 'interfaces.dart';
import 'lan.dart';
import 'port_probe.dart';
import 'ws_discovery.dart';

/// Runs the port probe and WS-Discovery over the local subnet at once and
/// returns one [Device] per host found, or null when the device is not on a
/// LAN. [lock] wraps the whole scan: the app passes the Android multicast
/// lock, everything else runs bare.
Future<List<Device>?> discoverDevices({
  Future<({String address, int prefixLength})?> Function() network = scanNetwork,
  Future<Map<String, List<int>>> Function(Iterable<String> hosts) ports = probePorts,
  Future<Map<String, String>> Function(String localAddress) onvif = discoverOnvif,
  Future<T> Function<T>(Future<T> Function() body) lock = _bare,
}) async {
  final lan = await network();
  if (lan == null) return null;
  return lock(() async {
    final hosts = subnetHosts(lan.address, lan.prefixLength);
    final (openPorts, found) = await (ports(hosts), onvif(lan.address)).wait;
    return mergeDiscovery(openPorts, found);
  });
}

Future<T> _bare<T>(Future<T> Function() body) => body();
