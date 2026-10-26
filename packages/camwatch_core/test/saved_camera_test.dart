import 'package:camwatch_core/camwatch_core.dart';
import 'package:test/test.dart';

void main() {
  const cameras = [SavedCamera('192.168.1.6', 554), SavedCamera('192.168.1.7', 8554)];

  test('a saved camera plays from its port and compares by value', () {
    expect(cameras.first.device, const Device('192.168.1.6', openPorts: [554]));
    expect(cameras.first.device.rtspPort, 554);
    expect(cameras.first, const SavedCamera('192.168.1.6', 554));
    expect(cameras.first, isNot(cameras.last));
    expect(cameras.first.hashCode, const SavedCamera('192.168.1.6', 554).hashCode);
    expect(cameras.first.toString(), 'SavedCamera(192.168.1.6:554)');
  });

  test('cameras survive a round trip through text', () {
    expect(decodeCameras(encodeCameras(cameras)), cameras);
    expect(decodeCameras(encodeCameras(const [])), isEmpty);
  });

  test('text that is not a camera list, or an entry off the LAN, yields nothing', () {
    expect(decodeCameras(''), isEmpty);
    expect(decodeCameras('not json'), isEmpty);
    expect(decodeCameras('{"address": "192.168.1.6"}'), isEmpty);
    expect(decodeCameras('[{"address": "8.8.8.8", "port": 554}]'), isEmpty);
    expect(decodeCameras('[{"address": "192.168.1.6", "port": "554"}, 7, null]'), isEmpty);
    expect(decodeCameras('[{"address": "192.168.1.6", "port": 554}, {"port": 1}]'), [
      cameras.first,
    ]);
  });
}
