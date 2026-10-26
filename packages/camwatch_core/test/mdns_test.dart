import 'dart:io';

import 'package:camwatch_core/camwatch_core.dart';
import 'package:test/test.dart';

/// A DNS name as labels, or a compression pointer to [offset].
List<int> name(String name) => [
  for (final label in name.split('.')) ...[label.length, ...label.codeUnits],
  0,
];
List<int> pointer(int offset) => [0xC0 | (offset >> 8), offset & 0xff];
List<int> u16(int n) => [n >> 8, n & 0xff];

List<int> record(List<int> owner, int type, List<int> rdata) => [
  ...owner,
  ...u16(type),
  ...u16(1),
  0,
  0,
  0,
  120,
  ...u16(rdata.length),
  ...rdata,
];

List<int> srv(List<int> owner, int port, List<int> target) =>
    record(owner, 33, [...u16(0), ...u16(0), ...u16(port), ...target]);

/// A response: header, [questions] questions already encoded in [body], the records in [body].
List<int> response(List<int> body, {int questions = 0, int answers = 1}) => [
  ...u16(0),
  0x84,
  0x00,
  ...u16(questions),
  ...u16(answers),
  ...u16(0),
  ...u16(0),
  ...body,
];

final rtspCam = name('Cam._rtsp._tcp.local');

void main() {
  test('mdnsQuery asks for RTSP and ONVIF services', () {
    final query = mdnsQuery();
    expect(query.sublist(0, 12), [0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0]);
    expect(query.sublist(12), [
      ...name('_rtsp._tcp.local'),
      ...u16(12),
      ...u16(1),
      ...name('_onvif._tcp.local'),
      ...u16(12),
      ...u16(1),
    ]);
  });

  group('mdnsPorts', () {
    test('reads the port of every RTSP or ONVIF service instance', () {
      final body = [
        ...srv(rtspCam, 10554, name('cam.local')),
        ...record(name('cam.local'), 1, [192, 168, 1, 30]),
        ...srv(name('Cam._onvif._tcp.local'), 8080, name('cam.local')),
        ...srv(name('Printer._ipp._tcp.local'), 631, name('printer.local')),
      ];
      expect(mdnsPorts(response(body, answers: 4)), [10554, 8080]);
    });

    test('follows compressed names, whatever their case', () {
      final question = [...name('_RTSP._tcp.LOCAL'), ...u16(12), ...u16(1)];
      final instance = [3, ...'Cam'.codeUnits, ...pointer(12)];
      final body = [...question, ...srv(instance, 554, pointer(12))];
      expect(mdnsPorts(response(body, questions: 1)), [554]);
    });

    test('yields nothing for garbage, a truncated record or a pointer loop', () {
      expect(mdnsPorts([1, 2, 3]), isEmpty);
      expect(mdnsPorts(response(srv(rtspCam, 554, name('c.local')).sublist(0, 20))), isEmpty);
      final loop = [...pointer(12), ...u16(33), ...u16(1), 0, 0, 0, 1, ...u16(2), 0, 0];
      expect(mdnsPorts(response(loop)), isEmpty);
      expect(mdnsPorts(response([])), isEmpty);
    });
  });

  group('discoverMdns', () {
    Future<RawDatagramSocket> responder(List<int> Function() reply) async {
      final socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      socket.listen((_) {
        final datagram = socket.receive();
        if (datagram != null) socket.send(reply(), datagram.address, datagram.port);
      });
      return socket;
    }

    test('collects the ports each local responder announces', () async {
      final cam = await responder(
        () => response([
          ...srv(rtspCam, 554, name('c.local')),
          ...srv(name('Cam._onvif._tcp.local'), 80, name('c.local')),
        ], answers: 2),
      );
      final found = await discoverMdns(
        '127.0.0.1',
        target: InternetAddress.loopbackIPv4,
        port: cam.port,
        wait: const Duration(milliseconds: 300),
      );
      cam.close();
      expect(found, {
        '127.0.0.1': [80, 554],
      });
    });

    test('drops an oversized reply', () async {
      final cam = await responder(() => List.filled(maxMdnsBytes + 1, 0));
      final found = await discoverMdns(
        '127.0.0.1',
        target: InternetAddress.loopbackIPv4,
        port: cam.port,
        wait: const Duration(milliseconds: 300),
      );
      cam.close();
      expect(found, isEmpty);
    });

    test('keeps at most maxSenders responders and the first ports of each', () async {
      final senders = <RawDatagramSocket>[];
      final cam = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      cam.listen((_) async {
        final query = cam.receive();
        if (query == null) return;
        for (var i = 0; i < maxSenders + 10; i++) {
          final sender = await RawDatagramSocket.bind('127.0.${1 + i ~/ 200}.${1 + i % 200}', 0);
          senders.add(sender);
          final many = [
            for (var p = 1; p <= maxMdnsPortsPerHost + 5; p++) ...srv(rtspCam, p, name('c.local')),
          ];
          sender.send(response(many, answers: maxMdnsPortsPerHost + 5), query.address, query.port);
        }
      });
      final found = await discoverMdns(
        '127.0.0.1',
        target: InternetAddress.loopbackIPv4,
        port: cam.port,
        wait: const Duration(seconds: 2),
      );
      cam.close();
      for (final sender in senders) {
        sender.close();
      }
      expect(found, hasLength(maxSenders));
      expect(found.values.first, hasLength(maxMdnsPortsPerHost));
    });

    test('refuses a target off the local network', () {
      expect(
        () => discoverMdns('127.0.0.1', target: InternetAddress('8.8.8.8')),
        throwsArgumentError,
      );
    });

    test('the query goes to the mDNS group by default', () {
      expect(mdnsGroup.address, '224.0.0.251');
      expect(mdnsPort, 5353);
    });
  });
}
