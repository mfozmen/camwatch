import 'dart:io';

import 'package:camwatch/src/version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the version the app reports is the one in its pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(RegExp(r'^version: (\S+)$', multiLine: true).firstMatch(pubspec)?.group(1), appVersion);
  });
}
