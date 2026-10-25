import 'dart:io';

import 'lan.dart';

/// Interfaces that never reach a camera: VPN tunnels, mobile data, virtual
/// switches and container bridges. Matched case-insensitively in the name.
const _skippedNames = [
  'tun',
  'tap',
  'vpn',
  'wg',
  'ppp',
  'rmnet',
  'ccmni',
  'docker',
  'veth',
  'virtual',
  'vmnet',
  'vmware',
  'tailscale',
  'zerotier',
];

/// The IPv4 network camwatch scans: the first Wi-Fi or Ethernet address
/// [isLocalIpv4] accepts with its prefix, or null when the device is not on
/// a LAN. Feed it to [subnetHosts].
Future<({String address, int prefixLength})?> scanNetwork({
  Future<List<NetworkInterface>> Function() listInterfaces = _listInterfaces,
}) async {
  for (final interface in await listInterfaces()) {
    final name = interface.name.toLowerCase();
    if (_skippedNames.any(name.contains)) continue;
    for (final address in interface.addresses) {
      if (address.isLoopback || !isLocalIpv4(address.address)) continue;
      return (address: address.address, prefixLength: address.prefixLength);
    }
  }
  return null;
}

Future<List<NetworkInterface>> _listInterfaces() =>
    NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
