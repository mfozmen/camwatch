import 'dart:io';

import 'package:camwatch_core/camwatch_core.dart';
import 'package:test/test.dart';

class _Address implements InterfaceAddress {
  _Address(this.address, this.prefixLength);

  @override
  final String address;
  @override
  final int prefixLength;
  @override
  bool get isLoopback => address.startsWith('127.');

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Interface implements NetworkInterface {
  _Interface(this.name, List<String> cidrs)
    : addresses = [
        for (final cidr in cidrs) _Address(cidr.split('/').first, int.parse(cidr.split('/').last)),
      ];

  @override
  final String name;
  @override
  final List<InterfaceAddress> addresses;
  @override
  int get index => 0;
}

void main() {
  Future<List<NetworkInterface>> Function() list(List<_Interface> interfaces) =>
      () async => interfaces;

  group('scanNetwork', () {
    test('takes the Wi-Fi or Ethernet address', () async {
      final address = await scanNetwork(
        listInterfaces: list([
          _Interface('lo', ['127.0.0.1/8']),
          _Interface('wlan0', ['192.168.1.20/24']),
        ]),
      );
      expect(address, (address: '192.168.1.20', prefixLength: 24));
    });

    test('skips VPN, mobile and virtual interfaces', () async {
      final address = await scanNetwork(
        listInterfaces: list([
          _Interface('tun0', ['10.8.0.2/24']),
          _Interface('rmnet_data0', ['10.20.30.40/29']),
          _Interface('vEthernet (Default Switch)', ['172.20.0.1/20']),
          _Interface('VirtualBox Host-Only Network', ['192.168.56.1/24']),
          _Interface('Ethernet', ['192.168.0.9/16']),
        ]),
      );
      expect(address, (address: '192.168.0.9', prefixLength: 16));
    });

    test('skips public and loopback addresses', () async {
      final address = await scanNetwork(
        listInterfaces: list([
          _Interface('eth0', ['100.64.1.2/10', '127.0.0.1/8']),
        ]),
      );
      expect(address, isNull);
    });

    test('the real interface list only ever yields a local address', () async {
      final network = await scanNetwork();
      expect(network == null || isLocalIpv4(network.address), isTrue);
    });
  });
}
