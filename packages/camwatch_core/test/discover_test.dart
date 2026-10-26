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
        ports: (_, _) async {
          probed = true;
          return {};
        },
        mdns: (_) async => {},
        onvif: (_) async => {},
      );
      expect(devices, isNull);
      expect(probed, isFalse);
    });

    test('probes the subnet hosts and merges both scans under the lock', () async {
      final log = <String>[];
      final devices = await discoverDevices(
        network: () async => (address: '192.168.1.5', prefixLength: 30),
        ports: (hosts, ports) async {
          log.add('ports ${hosts.join(',')} on ${ports.join(',')}');
          return ports == cameraPorts
              ? {
                  '192.168.1.6': [554],
                }
              : {
                  '192.168.1.6': [23],
                };
        },
        mdns: (_) async => {},
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
          openPorts: [23, 554],
          onvifAddress: 'http://192.168.1.6/onvif/device_service',
        ),
      ]);
      expect(log, [
        'lock',
        'ports 192.168.1.5,192.168.1.6 on ${cameraPorts.join(',')}',
        'onvif 192.168.1.5',
        'ports 192.168.1.6 on ${gradePorts.join(',')}',
      ]);
    });

    test('probes the grade ports on every found device, ONVIF-only ones too', () async {
      final devices = await discoverDevices(
        network: () async => (address: '192.168.1.5', prefixLength: 29),
        ports: (hosts, ports) async => ports == cameraPorts
            ? {
                '192.168.1.2': [80],
              }
            : {
                for (final host in hosts) host: const [443],
              },
        mdns: (_) async => {},
        onvif: (_) async => {'192.168.1.3': 'http://192.168.1.3/o'},
      );
      expect(devices, [
        const Device('192.168.1.2', openPorts: [80, 443]),
        const Device('192.168.1.3', openPorts: [443], onvifAddress: 'http://192.168.1.3/o'),
      ]);
    });

    test('probes the grade ports inside the scanned subnet only', () async {
      final graded = <String>[];
      final devices = await discoverDevices(
        network: () async => (address: '192.168.1.5', prefixLength: 30),
        ports: (hosts, ports) async {
          if (ports == gradePorts) graded.addAll(hosts);
          return {};
        },
        mdns: (_) async => {},
        onvif: (_) async => {
          '10.0.0.9': 'http://10.0.0.9/o',
          '192.168.1.6': 'http://192.168.1.6/o',
        },
      );
      expect(graded, ['192.168.1.6']);
      expect(devices, [
        const Device('10.0.0.9', openPorts: [], onvifAddress: 'http://10.0.0.9/o'),
        const Device('192.168.1.6', openPorts: [], onvifAddress: 'http://192.168.1.6/o'),
      ]);
    });

    test('lists an mDNS-announced port only once a connect confirms it, in the subnet', () async {
      final probed = <String>[];
      final devices = await discoverDevices(
        network: () async => (address: '192.168.1.5', prefixLength: 29),
        ports: (hosts, ports) async {
          probed.add('${hosts.join(',')}:${ports.join(',')}');
          return ports.contains(10554)
              ? {
                  '192.168.1.2': [10554],
                }
              : {};
        },
        mdns: (_) async => {
          '192.168.1.2': [554, 10554],
          '192.168.1.3': [8554],
          '10.0.0.9': [554],
        },
        onvif: (_) async => {},
      );
      expect(devices, [
        const Device('192.168.1.2', openPorts: [10554]),
      ]);
      expect(probed, contains('192.168.1.2:10554'));
      expect(probed.where((p) => p.startsWith('10.0.0.9')), isEmpty);
      expect(
        probed.where((p) => p.contains(':554')),
        isEmpty,
        reason: 'camera ports were probed already',
      );
    });

    test('a failing scan fails the whole discovery once both have finished', () async {
      final onvifDone = Completer<Map<String, String>>();
      final discovery = discoverDevices(
        network: () async => (address: '10.0.0.1', prefixLength: 30),
        ports: (_, _) async => throw const SocketException('down'),
        mdns: (_) async => {},
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
        ports: (_, _) async => {},
        mdns: (_) async => {},
        onvif: (_) async => {},
      );
      expect(devices, isEmpty);
    });
  });
}
