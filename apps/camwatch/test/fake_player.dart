import 'dart:async';

import 'package:camwatch/src/player.dart';
import 'package:flutter/material.dart';

class FakePlayer implements StreamPlayer {
  final opened = <String>[];
  final _errors = StreamController<String>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  var disposed = false;

  void fail(String message) => _errors.add(message);
  void ready() => _buffering.add(false);

  @override
  Future<void> open(String url) async => opened.add(url);

  @override
  Stream<String> get errors => _errors.stream;

  @override
  Stream<bool> get buffering => _buffering.stream;

  @override
  Widget get view => const ColoredBox(color: Colors.black, key: Key('video'));

  @override
  Future<void> dispose() async => disposed = true;
}
