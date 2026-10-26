import 'dart:convert';

import 'lan.dart';
import 'ws_discovery.dart';

/// A camera kept across restarts: where its stream is. Nothing secret, the
/// login stays in the credential store under the same address.
class SavedCamera {
  const SavedCamera(this.address, this.port);

  final String address;
  final int port;

  /// The camera as the player takes it.
  Device get device => Device(address, openPorts: [port]);

  @override
  bool operator ==(Object other) =>
      other is SavedCamera && other.address == address && other.port == port;

  @override
  int get hashCode => Object.hash(address, port);

  @override
  String toString() => 'SavedCamera($address:$port)';
}

/// [cameras] as one JSON text.
String encodeCameras(List<SavedCamera> cameras) => jsonEncode([
  for (final camera in cameras) {'address': camera.address, 'port': camera.port},
]);

/// The cameras in [text]. An entry that is not one, or whose address is off
/// the local network, is dropped; text that is not a list is no cameras.
List<SavedCamera> decodeCameras(String text) {
  Object? parsed;
  try {
    parsed = jsonDecode(text);
  } on FormatException {
    return const [];
  }
  if (parsed is! List) return const [];
  return [
    for (final entry in parsed)
      if (entry case {'address': final String address, 'port': final int port})
        if (isLocalIpv4(address) && port > 0 && port <= 65535) SavedCamera(address, port),
  ];
}
