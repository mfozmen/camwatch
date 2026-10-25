import 'package:camwatch/src/multicast_lock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <String>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      multicastChannel,
      (call) async => calls.add(call.method),
    );
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('holds the Android multicast lock around the body, even when it throws', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(await withMulticastLock(() async => 42), 42);
    expect(calls, ['acquire', 'release']);
    calls.clear();
    await expectLater(withMulticastLock(() async => throw StateError('x')), throwsStateError);
    expect(calls, ['acquire', 'release']);
  });

  test('is a plain call elsewhere', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(await withMulticastLock(() async => 'ok'), 'ok');
    expect(calls, isEmpty);
  });
}
