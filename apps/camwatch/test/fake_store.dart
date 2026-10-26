import 'package:camwatch/src/credential_store.dart';
import 'package:camwatch_core/camwatch_core.dart';

class FakeStore implements CredentialStore {
  final saved = <String, Credentials>{};

  /// When set, every [read] throws it, like a broken keystore would.
  Object? error;

  @override
  Future<Credentials?> read(String address) async {
    if (error case final error?) throw error;
    return saved[address];
  }

  @override
  Future<void> write(String address, Credentials credentials) async => saved[address] = credentials;
}
