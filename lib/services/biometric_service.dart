import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

class BiometricService {
  BiometricService._();

  static final LocalAuthentication _auth = LocalAuthentication();

  static Future<bool> isBiometricAvailable() async {
    try {
      final isDeviceSupported = await _auth.isDeviceSupported();
      // Jika device support, anggap bisa pakai biometrik ATAU device credential (PIN/pola/sandi)
      return isDeviceSupported;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> getAvailabilityIssue() async {
    try {
      final isDeviceSupported = await _auth.isDeviceSupported();
      if (!isDeviceSupported) {
        return 'Perangkat Anda tidak mendukung biometrik.';
      }

      final canCheck = await _auth.canCheckBiometrics;
      final available = await _auth.getAvailableBiometrics();
      if (!canCheck || available.isEmpty) {
        return 'Biometrik tidak siap.\n\nPastikan:\n- Layar terkunci dengan PIN/pola/sandi\n- Sudah mendaftarkan sidik jari/wajah di Pengaturan.';
      }
      return null;
    } catch (_) {
      return 'Biometrik tidak bisa digunakan di perangkat ini.';
    }
  }

  static Future<bool> authenticate() async {
    try {
      final available = await isBiometricAvailable();
      if (!available) return false;

      final didAuthenticate = await _auth.authenticate(
        localizedReason: 'Verifikasi biometrik atau kunci layar untuk masuk',
        options: const AuthenticationOptions(
          biometricOnly: false, // allow PIN/pola/sandi juga
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      return didAuthenticate;
    } catch (e) {
      // Helps show clearer info to the UI about why it failed.
      debugPrint('Biometric auth failed: $e');
      return false;
    }
  }
}
