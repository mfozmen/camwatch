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
