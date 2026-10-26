import 'lan.dart';

/// A camera login. Printing it never reveals the password, so a stray
/// `print` or log line cannot leak it.
class Credentials {
  const Credentials(this.user, this.password);

  final String user;
  final String password;

  @override
  bool operator ==(Object other) =>
      other is Credentials && other.user == user && other.password == password;

  @override
  int get hashCode => Object.hash(user, password);

  @override
  String toString() => 'Credentials($user, ***)';
}

/// The RTSP URL for one stream, with [credentials] as escaped user info.
/// Hand it to the player only: it is never logged or shown. A host off the
/// local network is refused, so a login can never travel further.
String rtspUrl(String host, int port, String path, [Credentials? credentials]) {
  if (!isLocalIpv4(host)) throw ArgumentError.value(host, 'host', 'not on the local network');
  final auth = credentials == null
      ? ''
      : '${Uri.encodeComponent(credentials.user)}:${Uri.encodeComponent(credentials.password)}@';
  return 'rtsp://$auth$host:$port$path';
}
