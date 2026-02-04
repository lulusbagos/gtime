import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:gtime/services/fake_gps_detector.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Widget untuk testing dan debugging fake GPS detection
/// Gunakan ini untuk validasi apakah detection system bekerja dengan baik
class FakeGpsTestWidget extends StatefulWidget {
  const FakeGpsTestWidget({super.key});

  @override
  State<FakeGpsTestWidget> createState() => _FakeGpsTestWidgetState();
}

class _FakeGpsTestWidgetState extends State<FakeGpsTestWidget> {
  static const String _askedLocationPermissionKey =
      'asked_location_permission';
  Position? _currentPosition;
  FakeGpsDetectionResult? _detectionResult;
  bool _isChecking = false;
  String _statusMessage = 'Tap tombol untuk cek lokasi';

  Future<void> _checkLocation() async {
    setState(() {
      _isChecking = true;
      _statusMessage = 'Mengambil lokasi...';
    });

    try {
      // Check location permission
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final prefs = await SharedPreferences.getInstance();
        final askedBefore = prefs.getBool(_askedLocationPermissionKey) ?? false;
        if (!askedBefore) {
          permission = await Geolocator.requestPermission();
          await prefs.setBool(_askedLocationPermissionKey, true);
        }
      }
      if (permission == LocationPermission.denied) {
        if (mounted) {
          _showLocationSettingsDialog(
            'Izin Lokasi Ditolak',
            'Berikan izin lokasi agar bisa mengecek fake GPS.',
          );
        }
        throw Exception('Izin lokasi ditolak.');
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          _showLocationSettingsDialog(
            'Izin Lokasi Permanen Ditolak',
            'Buka pengaturan aplikasi dan izinkan lokasi untuk melanjutkan.',
          );
        }
        throw Exception('Izin lokasi ditolak permanen.');
      }

      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentPosition = position;
        _statusMessage = 'Mendeteksi fake GPS...';
      });

      // Detect fake GPS
      final result = await FakeGpsDetector.detectFakeGps(position);

      setState(() {
        _detectionResult = result;
        _statusMessage = result.isFake 
            ? '⚠️ FAKE GPS TERDETEKSI!' 
            : '✅ Lokasi Valid';
        _isChecking = false;
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: $e';
        _isChecking = false;
      });
    }
  }

  void _showLocationSettingsDialog(String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(color: Colors.redAccent)),
        content: Text(message),
        actions: [
          TextButton(
            child: const Text('Buka Pengaturan'),
            onPressed: () {
              Navigator.of(ctx).pop();
              Geolocator.openAppSettings();
            },
          ),
          TextButton(
            child: const Text('OK'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fake GPS Detector Test'),
        backgroundColor: Colors.blueGrey[800],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Card
            Card(
              elevation: 4,
              color: _detectionResult?.isFake == true 
                  ? Colors.red.shade50 
                  : Colors.green.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(
                      _detectionResult?.isFake == true
                          ? Icons.warning_rounded
                          : Icons.check_circle_rounded,
                      size: 64,
                      color: _detectionResult?.isFake == true
                          ? Colors.red
                          : Colors.green,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _statusMessage,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _detectionResult?.isFake == true
                            ? Colors.red.shade900
                            : Colors.green.shade900,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Check Button
            ElevatedButton.icon(
              onPressed: _isChecking ? null : _checkLocation,
              icon: _isChecking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.gps_fixed),
              label: Text(_isChecking ? 'Checking...' : 'Check Location'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueGrey[800],
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),

            const SizedBox(height: 24),

            // Position Info
            if (_currentPosition != null) ...[
              _buildInfoSection(
                title: 'Position Info',
                icon: Icons.location_on,
                children: [
                  _buildInfoRow('Latitude', '${_currentPosition!.latitude}'),
                  _buildInfoRow('Longitude', '${_currentPosition!.longitude}'),
                  _buildInfoRow('Accuracy', '${_currentPosition!.accuracy.toStringAsFixed(2)} m'),
                  _buildInfoRow('Altitude', '${_currentPosition!.altitude.toStringAsFixed(2)} m'),
                  _buildInfoRow('Speed', '${_currentPosition!.speed.toStringAsFixed(2)} m/s'),
                  _buildInfoRow('Is Mocked', '${_currentPosition!.isMocked}'),
                  _buildInfoRow(
                    'Timestamp',
                    '${_currentPosition!.timestamp ?? 'N/A'}',
                  ),
                ],
              ),
            ],

            const SizedBox(height: 16),

            // Detection Result
            if (_detectionResult != null) ...[
              _buildInfoSection(
                title: 'Detection Result',
                icon: Icons.security,
                children: [
                  _buildInfoRow('Is Fake', '${_detectionResult!.isFake}'),
                  _buildInfoRow('Confidence', _detectionResult!.confidence),
                  const SizedBox(height: 8),
                  const Text(
                    'Detection Reasons:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ..._detectionResult!.reasons.map(
                    (reason) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '• ',
                            style: TextStyle(
                              color: _detectionResult!.isFake
                                  ? Colors.red
                                  : Colors.green,
                            ),
                          ),
                          Expanded(child: Text(reason)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 24),

            // Info Box
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'Testing Tips',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '1. Test dengan GPS asli dulu (hasil: valid)\n'
                    '2. Install fake GPS app (Fake GPS Location, etc)\n'
                    '3. Enable mock location di Developer Options\n'
                    '4. Set fake location\n'
                    '5. Test lagi (hasil: fake terdeteksi)',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.blueGrey[800]),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey[800],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }
}
