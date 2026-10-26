import 'dart:convert';
import 'dart:io';

import 'package:camwatch_core/camwatch_core.dart';
import 'package:test/test.dart';

String probeMatch(String xaddrs) =>
    '<?xml version="1.0"?><e:Envelope xmlns:e="http://www.w3.org/2003/05/soap-envelope" '
    'xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery"><e:Body><d:ProbeMatches>'
    '<d:ProbeMatch><d:XAddrs>$xaddrs</d:XAddrs></d:ProbeMatch>'
    '</d:ProbeMatches></e:Body></e:Envelope>';

/// A camera on the loopback interface that answers every probe with [reply].
Future<RawDatagramSocket> fakeCamera(List<int> Function() reply) async {
  final socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  socket.listen((_) {
    final datagram = socket.receive();
    if (datagram != null) socket.send(reply(), datagram.address, datagram.port);
  });
  return socket;
}

void main() {
  test('probeMessage asks for network video transmitters with a fresh id', () {
    final message = probeMessage();
    expect(message, contains('dn:NetworkVideoTransmitter'));
    expect(message, contains('<w:MessageID>urn:uuid:'));
    expect(message, contains('http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe'));
    expect(probeMessage(), isNot(message));
  });

  group('parseProbeMatch', () {
    test('keeps the local device service addresses', () {
      final xaddrs = 'http://192.168.1.30/onvif/device_service http://8.8.8.8/onvif/device_service';
      expect(parseProbeMatch(probeMatch(xaddrs)), ['http://192.168.1.30/onvif/device_service']);
    });

    test('yields nothing for a reply without XAddrs or with garbage', () {
      expect(parseProbeMatch('<e:Envelope/>'), isEmpty);
      expect(parseProbeMatch('not xml'), isEmpty);
      expect(parseProbeMatch(probeMatch('ftp://192.168.1.30/x')), isEmpty);
      expect(parseProbeMatch(probeMatch('http://[ http://192.168.1.1:abc/')), isEmpty);
    });
  });

  group('discoverOnvif', () {
    test('collects the service address of every camera that answers', () async {
      final camera = await fakeCamera(
        () => utf8.encode(probeMatch('http://127.0.0.1:8000/onvif/device_service')),
      );
      final found = await discoverOnvif(
        '127.0.0.1',
        target: InternetAddress.loopbackIPv4,
        port: camera.port,
        wait: const Duration(milliseconds: 300),
      );
      camera.close();
      expect(found, {'127.0.0.1': 'http://127.0.0.1:8000/onvif/device_service'});
    });

    for (final (name, reply) in [
      ('oversized', 'x' * 20000),
      ('pointing at another host', 'http://192.168.1.5/onvif/device_service'),
    ]) {
      test('drops a reply that is $name', () async {
        final camera = await fakeCamera(() => utf8.encode(probeMatch(reply)));
        final found = await discoverOnvif(
          '127.0.0.1',
          target: InternetAddress.loopbackIPv4,
          port: camera.port,
          wait: const Duration(milliseconds: 300),
        );
        camera.close();
        expect(found, isEmpty);
      });
    }

    test('keeps at most maxSenders senders, however many addresses answer', () async {
      // One probe, replies from more loopback addresses than the cap, each
      // naming itself; a spoofing device on the Wi-Fi could do the same.
      final senders = <RawDatagramSocket>[];
      final camera = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      camera.listen((_) async {
        final probe = camera.receive();
        if (probe == null) return;
        for (var i = 0; i < maxSenders + 20; i++) {
          final address = '127.0.${1 + i ~/ 200}.${1 + i % 200}';
          final sender = await RawDatagramSocket.bind(address, 0);
          senders.add(sender);
          sender.send(
            utf8.encode(probeMatch('http://$address/onvif/device_service')),
            probe.address,
            probe.port,
          );
        }
      });
      final found = await discoverOnvif(
        '127.0.0.1',
        target: InternetAddress.loopbackIPv4,
        port: camera.port,
        wait: const Duration(seconds: 2),
      );
      camera.close();
      for (final sender in senders) {
        sender.close();
      }
      expect(senders, hasLength(maxSenders + 20));
      expect(found, hasLength(maxSenders));
    });

    test('refuses a target off the local network', () {
      expect(
        () => discoverOnvif('127.0.0.1', target: InternetAddress('8.8.8.8')),
        throwsArgumentError,
      );
    });
  });

  test('mergeDiscovery joins port and ONVIF results into one device per host', () {
    final devices = mergeDiscovery(
      {
        '192.168.1.30': [80, 554],
        '192.168.1.10': [8080],
      },
      {
        '192.168.1.30': 'http://192.168.1.30/onvif/device_service',
        '192.168.1.40': 'http://192.168.1.40/o',
      },
    );
    expect(devices, [
      const Device('192.168.1.10', openPorts: [8080]),
      const Device(
        '192.168.1.30',
        openPorts: [80, 554],
        onvifAddress: 'http://192.168.1.30/onvif/device_service',
      ),
      const Device('192.168.1.40', openPorts: [], onvifAddress: 'http://192.168.1.40/o'),
    ]);
    expect(devices.toSet(), hasLength(3));
    expect(devices.first.toString(), 'Device(192.168.1.10, ports: [8080], onvif: null)');
  });

  test('a device streams from 554 before 8554, or not at all', () {
    expect(const Device('10.0.0.1', openPorts: [8554, 80, 554]).rtspPort, 554);
    expect(const Device('10.0.0.1', openPorts: [8554]).rtspPort, 8554);
    expect(const Device('10.0.0.1', openPorts: [80]).rtspPort, isNull);
  });

  test('the probe goes to the WS-Discovery group by default', () {
    expect(wsDiscoveryGroup.address, '239.255.255.250');
    expect(wsDiscoveryPort, 3702);
  });
}
