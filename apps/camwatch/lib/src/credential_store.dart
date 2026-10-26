import 'package:camwatch_core/camwatch_core.dart';

/// Where camera logins live, keyed by device address: the OS secure store
/// in the app, a map in tests.
abstract interface class CredentialStore {
  Future<Credentials?> read(String address);
  Future<void> write(String address, Credentials credentials);
}
