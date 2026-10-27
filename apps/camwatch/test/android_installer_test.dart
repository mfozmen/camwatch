import 'dart:io';

import 'package:camwatch/src/android_installer.dart';
import 'package:camwatch/src/installer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  var answer = 'started';

  setUp(() {
    calls.clear();
    answer = 'started';
    messenger.setMockMethodCallHandler(installChannel, (call) async {
      calls.add(call);
      return answer;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(installChannel, null));

  test('hands the file path to the activity, which starts the installer', () async {
    await const AndroidInstaller().install(
      File('/data/cache/camwatch-update-x/camwatch-0.2.0.apk'),
    );
    expect(calls.single.method, 'install');
    expect(calls.single.arguments, '/data/cache/camwatch-update-x/camwatch-0.2.0.apk');
  });

  test('says when the user has not yet allowed installs, so the button can tell them', () async {
    answer = 'blocked';
    await expectLater(
      const AndroidInstaller().install(File('x.apk')),
      throwsA(isA<InstallBlocked>()),
    );
  });

  test('anything else the activity answers is a failure', () async {
    answer = 'odd';
    await expectLater(const AndroidInstaller().install(File('x.apk')), throwsA(isA<StateError>()));
  });
}
