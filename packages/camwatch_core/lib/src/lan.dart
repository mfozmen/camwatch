/// Whether [address] is an IPv4 address on a local network: private
/// (RFC 1918), loopback or link-local. camwatch never talks to anything else.
bool isLocalIpv4(String address) {
  final parts = address.split('.');
  if (parts.length != 4) return false;
  final octets = parts.map(int.tryParse).toList();
  if (octets.any((o) => o == null || o < 0 || o > 255)) return false;
  final [a, b, _, _] = octets.cast<int>();
  return a == 10 ||
      a == 127 ||
      (a == 172 && b >= 16 && b <= 31) ||
      (a == 192 && b == 168) ||
      (a == 169 && b == 254);
}

/// Every host address of the subnet holding [address] with [prefixLength],
/// without the network and broadcast addresses. A subnet wider than
/// /[minPrefix] is cut to the /[minPrefix] around [address]: probing a /16
/// would take hours. Only addresses [isLocalIpv4] accepts are returned.
List<String> subnetHosts(String address, int prefixLength, {int minPrefix = 22}) {
  RangeError.checkValueInInterval(prefixLength, 0, 32, 'prefixLength');
  if (!isLocalIpv4(address)) return const [];
  final prefix = prefixLength < minPrefix ? minPrefix : prefixLength;
  final mask = prefix == 0 ? 0 : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
  final network = _toInt(address) & mask;
  final broadcast = network | (~mask & 0xFFFFFFFF);
  return [
    for (var host = network + 1; host < broadcast; host++)
      if (isLocalIpv4(_toAddress(host))) _toAddress(host),
  ];
}

int _toInt(String address) =>
    address.split('.').map(int.parse).fold(0, (acc, octet) => (acc << 8) | octet);

String _toAddress(int value) =>
    '${value >> 24 & 255}.${value >> 16 & 255}.${value >> 8 & 255}.${value & 255}';
