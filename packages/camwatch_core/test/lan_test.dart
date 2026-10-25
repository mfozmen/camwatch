import 'package:camwatch_core/camwatch_core.dart';
import 'package:test/test.dart';

void main() {
  group('isLocalIpv4', () {
    for (final address in [
      '10.0.0.1',
      '127.0.0.1',
      '172.16.0.1',
      '172.31.255.255',
      '192.168.1.20',
      '169.254.10.10',
    ]) {
      test('accepts $address', () => expect(isLocalIpv4(address), isTrue));
    }

    for (final address in [
      '8.8.8.8',
      '172.15.0.1',
      '172.32.0.1',
      '192.169.0.1',
      '169.253.0.1',
      '192.168.1',
      '192.168.1.1.1',
      '192.168.1.256',
      '192.168.1.-1',
      '192.168.one.1',
      '',
    ]) {
      test('rejects "$address"', () => expect(isLocalIpv4(address), isFalse));
    }
  });
  group('subnetHosts', () {
    test('lists every host of a /30, without network and broadcast', () {
      expect(subnetHosts('192.168.1.5', 30), ['192.168.1.5', '192.168.1.6']);
    });

    test('a /24 has 254 hosts', () {
      final hosts = subnetHosts('10.0.0.77', 24);
      expect(hosts, hasLength(254));
      expect(hosts.first, '10.0.0.1');
      expect(hosts.last, '10.0.0.254');
    });

    test('a wide subnet is cut to the /22 around the address', () {
      final hosts = subnetHosts('172.16.9.1', 16);
      expect(hosts, hasLength(1022));
      expect(hosts.first, '172.16.8.1');
      expect(hosts.last, '172.16.11.254');
    });

    test('/31 and /32 have no hosts', () {
      expect(subnetHosts('192.168.1.1', 31), isEmpty);
      expect(subnetHosts('192.168.1.1', 32), isEmpty);
    });

    test('a non-local address yields nothing', () {
      expect(subnetHosts('8.8.8.8', 24), isEmpty);
    });

    test('rejects a prefix outside 0..32', () {
      expect(() => subnetHosts('192.168.1.1', 33), throwsRangeError);
      expect(() => subnetHosts('192.168.1.1', -1), throwsRangeError);
    });
  });
}
