import 'package:camwatch/src/consent_store.dart';

class FakeConsent implements ConsentStore {
  FakeConsent({this.given = true, bool? asked}) : asked = asked ?? given;

  bool given;

  /// Whether the notice was ever answered, either way.
  bool asked;

  /// When set, every [read] throws it, like a broken store would.
  Object? error;

  @override
  Future<bool> read() async {
    if (error case final error?) throw error;
    return given;
  }

  @override
  Future<void> write() async {
    given = true;
    asked = true;
  }

  @override
  Future<void> refuse() async {
    given = false;
    asked = true;
  }

  @override
  Future<bool> wasAsked() async {
    if (error case final error?) throw error;
    return asked;
  }

  @override
  Future<void> clear() async {
    given = false;
    asked = false;
  }
}
