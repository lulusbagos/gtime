import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  SecureStorageService._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
    lOptions: LinuxOptions(),
    wOptions: WindowsOptions(),
  );

  static Future<void> write(String key, String value) {
    return _storage.write(key: key, value: value);
  }

  static Future<String?> read(String key) {
    return _storage.read(key: key);
  }

  static Future<void> delete(String key) {
    return _storage.delete(key: key);
  }

  static Future<void> deleteAll(Iterable<String> keys) async {
    for (final key in keys) {
      await _storage.delete(key: key);
    }
  }
}
