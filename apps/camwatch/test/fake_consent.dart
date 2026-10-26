import 'package:camwatch/src/consent_store.dart';

class FakeConsent implements ConsentStore {
  FakeConsent({this.given = true});

  bool given;

  /// When set, every [read] throws it, like a broken store would.
  Object? error;

  @override
  Future<bool> read() async {
    if (error case final error?) throw error;
    return given;
  }

  @override
  Future<void> write() async => given = true;

  @override
  Future<void> clear() async => given = false;
}
