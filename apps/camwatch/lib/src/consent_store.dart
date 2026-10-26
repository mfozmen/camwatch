/// Whether the person has accepted the notice shown before the first scan:
/// the OS secure store in the app, a flag in tests.
abstract interface class ConsentStore {
  Future<bool> read();
  Future<void> write();
}
