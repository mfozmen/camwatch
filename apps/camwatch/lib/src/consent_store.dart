/// Whether the person has accepted the notice shown before the first scan:
/// the OS secure store in the app, a flag in tests.
abstract interface class ConsentStore {
  /// True once accepted.
  Future<bool> read();

  /// Whether the notice was ever answered, accepted or refused.
  Future<bool> wasAsked();
  Future<void> write();
  Future<void> refuse();
  Future<void> clear();
}
