import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// An in-memory stand-in for the platform keystore.
///
/// The real one cannot run in a test: it is a platform channel. Faking it is
/// what makes the C-1 failure modes reachable — a key that is missing, a
/// keystore that throws, a key that is present but wrong.
class FakeSecureStorage implements FlutterSecureStorage {
  String? storedKey;
  bool readThrows = false;
  bool writeThrows = false;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (readThrows) throw StateError('keystore unavailable');
    return storedKey;
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (writeThrows) throw StateError('keystore read-only');
    storedKey = value;
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    storedKey = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
