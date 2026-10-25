import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android drops multicast packets unless an app holds a multicast lock.
/// The Android activity answers this channel.
const multicastChannel = MethodChannel('io.github.mfozmen.camwatch/multicast');

/// Runs [body] while holding the Wi-Fi multicast lock on Android; a plain
/// call on every other platform.
Future<T> withMulticastLock<T>(Future<T> Function() body) async {
  if (defaultTargetPlatform != TargetPlatform.android) return body();
  await multicastChannel.invokeMethod<void>('acquire');
  try {
    return await body();
  } finally {
    await multicastChannel.invokeMethod<void>('release');
  }
}
