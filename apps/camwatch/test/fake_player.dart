import 'dart:async';

import 'package:camwatch/src/player.dart';
import 'package:flutter/material.dart';

class FakePlayer implements StreamPlayer {
  final opened = <String>[];
  final _errors = StreamController<String>.broadcast();
  final _frames = StreamController<void>.broadcast();
  final _redirects = StreamController<void>.broadcast();
  var disposed = false;

  /// When set, every [open] waits on it instead of succeeding at once.
  Completer<void>? opening;

  void fail(String message) => _errors.add(message);
  void ready() => _frames.add(null);
  void redirect() => _redirects.add(null);

  @override
  Future<void> open(String url) {
    opened.add(url);
    return opening?.future ?? Future.value();
  }

  @override
  Stream<String> get errors => _errors.stream;

  @override
  Stream<void> get firstFrame => _frames.stream;

  @override
  Stream<void> get redirected => _redirects.stream;

  @override
  Widget get view => const ColoredBox(color: Colors.black, key: Key('video'));

  @override
  Future<void> dispose() async => disposed = true;
}
