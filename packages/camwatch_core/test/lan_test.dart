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
}
