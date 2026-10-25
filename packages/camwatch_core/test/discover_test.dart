import 'dart:async';
import 'dart:io';

import 'package:camwatch_core/camwatch_core.dart';
import 'package:test/test.dart';

void main() {
  group('discoverDevices', () {
    test('is null off the LAN and probes nothing', () async {
      var probed = false;
      final devices = await discoverDevices(
        network: () async => null,
        ports: (_) async {
          probed = true;
          return {};
        },
        onvif: (_) async => {},
      );
      expect(devices, isNull);
      expect(probed, isFalse);
    });

    test('probes the subnet hosts and merges both scans under the lock', () async {
      final log = <String>[];
      final devices = await discoverDevices(
        network: () async => (address: '192.168.1.5', prefixLength: 30),
        ports: (hosts) async {
          log.add('ports ${hosts.join(',')}');
          return {
            '192.168.1.6': [554],
          };
        },
        onvif: (address) async {
          log.add('onvif $address');
          return {'192.168.1.6': 'http://192.168.1.6/onvif/device_service'};
        },
        lock: <T>(body) async {
          log.add('lock');
          return body();
        },
      );
      expect(devices, [
        const Device(
          '192.168.1.6',
          openPorts: [554],
          onvifAddress: 'http://192.168.1.6/onvif/device_service',
        ),
      ]);
      expect(log, ['lock', 'ports 192.168.1.5,192.168.1.6', 'onvif 192.168.1.5']);
    });

    test('a failing scan fails the whole discovery once both have finished', () async {
      final onvifDone = Completer<Map<String, String>>();
      final discovery = discoverDevices(
        network: () async => (address: '10.0.0.1', prefixLength: 30),
        ports: (_) async => throw const SocketException('down'),
        onvif: (_) => onvifDone.future,
      );
      var finished = false;
      unawaited(discovery.then((_) => finished = true, onError: (_) => finished = true));
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
      onvifDone.complete({});
      await expectLater(discovery, throwsA(isA<ParallelWaitError<Object?, Object?>>()));
    });

    test('runs bare without a lock', () async {
      final devices = await discoverDevices(
        network: () async => (address: '10.0.0.1', prefixLength: 30),
        ports: (_) async => {},
        onvif: (_) async => {},
      );
      expect(devices, isEmpty);
    });
  });
}
