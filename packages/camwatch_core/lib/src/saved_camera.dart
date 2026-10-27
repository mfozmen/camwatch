import 'dart:convert';

import 'lan.dart';
import 'ws_discovery.dart';

/// A camera kept across restarts: where its stream is and what the user
/// calls it. Nothing secret, the login stays in the credential store under
/// the same address.
class SavedCamera {
  const SavedCamera(this.address, this.port, {this.name = ''});

  /// Longer names do not fit a tile or a title.
  static const maxNameLength = 40;

  final String address;
  final int port;
  final String name;

  /// The camera as the player takes it.
  Device get device => Device(address, openPorts: [port]);

  /// What to show for it: the name, or the address until there is one.
  String get label => name.trim().isEmpty ? address : name;

  /// The same camera called [name], trimmed and cut to [maxNameLength].
  SavedCamera named(String name) {
    final trimmed = name.trim();
    return SavedCamera(
      address,
      port,
      name: trimmed.length > maxNameLength ? trimmed.substring(0, maxNameLength) : trimmed,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SavedCamera && other.address == address && other.port == port && other.name == name;

  @override
  int get hashCode => Object.hash(address, port, name);

  @override
  String toString() => 'SavedCamera($address:$port)';
}

/// [cameras] as one JSON text.
String encodeCameras(List<SavedCamera> cameras) => jsonEncode([
  for (final camera in cameras)
    {'address': camera.address, 'port': camera.port, 'name': camera.name},
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
        if (isLocalIpv4(address) && port > 0 && port <= 65535)
          SavedCamera(address, port).named(switch (entry['name']) {
            final String name => name,
            _ => '',
          }),
  ];
}
