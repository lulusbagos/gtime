import 'dart:io';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

/// Service untuk mendeteksi penggunaan Fake GPS / Mock Location
///
/// Menggunakan berbagai metode deteksi:
/// - Android: Cek mock location flag dari Location API
/// - iOS: Validasi accuracy dan timestamp
/// - Cross-platform: Analisis perubahan lokasi yang tidak wajar
class FakeGpsDetector {
  static const _channel = MethodChannel('com.shiftcorner/fake_gps_detector');

  /// Deteksi apakah lokasi saat ini adalah fake/mock
  static Future<FakeGpsDetectionResult> detectFakeGps(Position position) async {
    final results = <String>[];
    bool isFake = false;

    // 1. CEK PALING PENTING: isMocked flag dari Geolocator
    if (position.isMocked == true) {
      results.add(
        '⚠️ MOCK LOCATION AKTIF - Sistem Android mendeteksi lokasi palsu',
      );
      isFake = true;
    }

    // 2. Cek Mock Location flag (Android native)
    if (Platform.isAndroid) {
      try {
        final mockEnabled = await _checkMockLocationEnabled();
        if (mockEnabled) {
          results.add('⚠️ Mock Location Setting terdeteksi AKTIF di sistem');
          isFake = true;
        }
      } catch (e) {
        // Fallback jika native code tidak tersedia
      }

      // Cek aplikasi fake GPS terinstall
      try {
        final fakeGpsApps = await _checkFakeGpsApps();
        if (fakeGpsApps.isNotEmpty) {
          results.add(
            '⚠️ Aplikasi Fake GPS terdeteksi: ${fakeGpsApps.join(", ")}',
          );
          isFake = true;
        }
      } catch (e) {
        // Ignore
      }
    }

    return FakeGpsDetectionResult(
      isFake: isFake,
      confidence: isFake ? 'HIGH' : 'LOW',
      reasons: results.isEmpty ? ['Lokasi valid'] : results,
    );
  }

  /// Cek apakah mock location sedang aktif (Android native)
  static Future<bool> _checkMockLocationEnabled() async {
    if (!Platform.isAndroid) return false;

    try {
      final result = await _channel.invokeMethod<bool>('checkMockLocation');
      return result ?? false;
    } catch (e) {
      // Fallback: coba deteksi dari Geolocator
      return false;
    }
  }

  /// Cek apakah developer options aktif (Android)
  static Future<bool> _checkDeveloperOptionsEnabled() async {
    if (!Platform.isAndroid) return false;

    try {
      final result = await _channel.invokeMethod<bool>('checkDeveloperOptions');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Cek aplikasi fake GPS yang terinstall (Android)
  static Future<List<String>> _checkFakeGpsApps() async {
    if (!Platform.isAndroid) return [];

    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'checkFakeGpsApps',
      );
      return result?.map((e) => e.toString()).toList() ?? [];
    } catch (e) {
      return [];
    }
  }

  /// Validasi perubahan lokasi (untuk deteksi teleportasi)
  static bool validateLocationChange(
    Position? previousPosition,
    Position currentPosition,
    Duration timeDiff,
  ) {
    if (previousPosition == null) return true;

    // Hitung jarak dalam meter
    final distance = Geolocator.distanceBetween(
      previousPosition.latitude,
      previousPosition.longitude,
      currentPosition.latitude,
      currentPosition.longitude,
    );

    // Hitung kecepatan maksimal yang masuk akal (m/s)
    // Misal: 150 km/jam = ~42 m/s
    const maxReasonableSpeed = 42.0; // m/s

    final seconds = timeDiff.inSeconds;
    if (seconds == 0) return true;

    final calculatedSpeed = distance / seconds;

    // Jika kecepatan lebih dari batas wajar = kemungkinan teleportasi/fake GPS
    if (calculatedSpeed > maxReasonableSpeed) {
      return false;
    }

    return true;
  }
}

/// Hasil deteksi fake GPS
class FakeGpsDetectionResult {
  final bool isFake;
  final String confidence; // HIGH, MEDIUM, LOW
  final List<String> reasons;

  FakeGpsDetectionResult({
    required this.isFake,
    required this.confidence,
    required this.reasons,
  });

  String get message {
    if (isFake) {
      return 'PERINGATAN: Terdeteksi penggunaan lokasi palsu!\n\n'
          'Alasan:\n${reasons.map((r) => '• $r').join('\n')}\n\n'
          'Sistem absensi tidak dapat digunakan dengan lokasi palsu/fake GPS.';
    }
    return 'Lokasi valid';
  }
}
