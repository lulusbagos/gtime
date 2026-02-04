import 'dart:async';
import 'dart:ui'; // Diperlukan untuk ImageFilter

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Untuk HapticFeedback
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';

class QrAttendanceScreen extends StatefulWidget {
  const QrAttendanceScreen({super.key});

  @override
  State<QrAttendanceScreen> createState() => _QrAttendanceScreenState();
}

class _QrAttendanceScreenState extends State<QrAttendanceScreen>
    with SingleTickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  // Animasi Laser Scanner
  late AnimationController _animationController;
  late Animation<double> _animation;

  bool _isProcessing = false;
  bool _isSuccess = false;
  bool _isError = false;
  String _statusMessage = 'Arahkan kamera ke QR Code';

  @override
  void initState() {
    super.initState();
    // Setup animasi garis scan
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _handleCode(String? rawValue) async {
    if (_isProcessing || rawValue == null || rawValue.isEmpty) return;

    // Efek getar saat terdeteksi
    HapticFeedback.lightImpact();

    setState(() {
      _isProcessing = true;
      _isSuccess = false;
      _isError = false;
      _statusMessage = 'Memverifikasi data...';
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final nik = prefs.getString('username');

      if (token == null || nik == null) {
        throw Exception('Sesi kadaluarsa. Silakan login ulang.');
      }

      final data = await _postEventAttendance(
        rawValue: rawValue,
        nik: nik,
        token: token,
      );
      if (data is Map) {
        final eventName =
            (data['eventName'] ?? data['acara'] ?? '').toString().trim();
        final message = (data['message'] ?? '').toString().toLowerCase();
        final alreadyChecked = message.contains('sudah');

        String detail = alreadyChecked
            ? 'Anda sudah absen untuk acara ini'
            : 'Absensi berhasil, terima kasih!';
        if (eventName.isNotEmpty) {
          detail = alreadyChecked
              ? 'Anda sudah absen untuk "$eventName"'
              : 'Absensi berhasil untuk "$eventName". Terima kasih!';
        }

        HapticFeedback.heavyImpact(); // Getar kuat saat sukses
        setState(() {
          _isSuccess = true;
          _isProcessing = false;
          _statusMessage = detail;
        });

        if (mounted) {
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) Navigator.of(context).pop(true);
        }
      } else {
        throw Exception('Respon server tidak valid.');
      }
    } catch (e) {
      HapticFeedback.vibrate();
      setState(() {
        _isError = true;
        _statusMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted && !_isSuccess) {
        // Reset status setelah delay jika gagal, agar user bisa scan lagi
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _isProcessing = false;
              _isError = false;
              _statusMessage = 'Arahkan kamera ke QR Code';
            });
          }
        });
      }
    }
  }

  Future<dynamic> _postEventAttendance({
    required String rawValue,
    required String nik,
    required String token,
  }) async {
    final endpoints = <String>[
      '/events/attendance',
      '/api/events/attendance',
    ];
    ApiException? lastError;
    for (final endpoint in endpoints) {
      try {
        return await ApiService().post(
          endpoint,
          body: {'eventId': rawValue, 'nik': nik},
          token: token,
        );
      } on ApiException catch (e) {
        lastError = e;
        final msg = e.toString().toLowerCase();
        final isNotFound =
            msg.contains('not found') || msg.contains('endpoint tidak ditemukan');
        if (!isNotFound) rethrow;
      }
    }
    throw lastError ?? ApiException('Endpoint absensi acara tidak tersedia');
  }

  void _toggleFlash() {
    _controller.toggleTorch();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Warna tema futuristik
    const scannerColor = Colors.cyanAccent;
    final screenWidth = MediaQuery.of(context).size.width;
    final scanAreaSize = screenWidth * 0.75;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.5),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        title: const Text(
          'SCAN ATTENDANCE',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        centerTitle: true,
        actions: [
          Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: ValueListenableBuilder(
                valueListenable: _controller.torchState,
                builder: (context, state, child) {
                  return Icon(
                    state == TorchState.on ? Icons.flash_on : Icons.flash_off,
                    color: state == TorchState.on ? Colors.amber : Colors.white,
                  );
                },
              ),
              onPressed: _toggleFlash,
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. Camera Layer
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              final barcode = capture.barcodes.first;
              _handleCode(barcode.rawValue);
            },
            errorBuilder: (context, error, child) {
              return Center(
                child: Text(
                  'Gagal memuat kamera: $error',
                  style: const TextStyle(color: Colors.white),
                ),
              );
            },
          ),

          // 2. Overlay transparan dengan highlight frame (tanpa menutup feed kamera di tengah)
          Positioned.fill(
            child: Stack(
              children: [
                Container(color: Colors.black.withOpacity(0.35)),
                Center(
                  child: Container(
                    width: scanAreaSize,
                    height: scanAreaSize,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.8),
                        width: 2,
                      ),
                      color: Colors.transparent,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 3. Active Scanner UI (Corners & Laser)
          Center(
            child: SizedBox(
              width: scanAreaSize,
              height: scanAreaSize,
              child: Stack(
                children: [
                  // Animated Scanner Line
                  if (!_isSuccess && !_isError)
                    AnimatedBuilder(
                      animation: _animation,
                      builder: (context, child) {
                        return Positioned(
                          top: _animation.value * (scanAreaSize - 10),
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 2,
                            decoration: BoxDecoration(
                              color: scannerColor,
                              boxShadow: [
                                BoxShadow(
                                  color: scannerColor.withOpacity(0.8),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                  // Custom Paint untuk Sudut Futuristik
                  CustomPaint(
                    painter: ScannerOverlayPainter(
                      color: _isSuccess
                          ? Colors.greenAccent
                          : _isError
                          ? Colors.redAccent
                          : scannerColor,
                    ),
                    child: Container(),
                  ),

                  // Loading / Success / Error Icons
                  if (_isProcessing || _isSuccess || _isError)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: _isSuccess
                            ? const Icon(
                                Icons.check_circle,
                                color: Colors.greenAccent,
                                size: 60,
                              )
                            : _isError
                            ? const Icon(
                                Icons.error_outline,
                                color: Colors.redAccent,
                                size: 60,
                              )
                            : const CircularProgressIndicator(
                                color: scannerColor,
                              ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // 4. Bottom Info Panel (Glassmorphism)
          Align(
            alignment: Alignment.bottomCenter,
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _isSuccess
                            ? 'SUKSES'
                            : _isError
                            ? 'GAGAL'
                            : _isProcessing
                            ? 'MEMPROSES'
                            : 'SIAP SCAN',
                        style: TextStyle(
                          color: _isSuccess
                              ? Colors.greenAccent
                              : _isError
                              ? Colors.redAccent
                              : scannerColor,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _statusMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          height: 1.4,
                        ),
                      ),
                      if (_isError) ...[
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _isError = false;
                              _isProcessing = false;
                              _statusMessage = 'Arahkan kamera ke QR Code';
                            });
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text("Coba Lagi"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            shape: const StadiumBorder(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Custom Painter untuk Menggambar Sudut Bingkai
class ScannerOverlayPainter extends CustomPainter {
  final Color color;

  ScannerOverlayPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final double cornerSize = 30;

    // Kiri Atas
    final p1 = Path();
    p1.moveTo(0, cornerSize);
    p1.lineTo(0, 0);
    p1.lineTo(cornerSize, 0);
    canvas.drawPath(p1, paint);

    // Kanan Atas
    final p2 = Path();
    p2.moveTo(size.width - cornerSize, 0);
    p2.lineTo(size.width, 0);
    p2.lineTo(size.width, cornerSize);
    canvas.drawPath(p2, paint);

    // Kiri Bawah
    final p3 = Path();
    p3.moveTo(0, size.height - cornerSize);
    p3.lineTo(0, size.height);
    p3.lineTo(cornerSize, size.height);
    canvas.drawPath(p3, paint);

    // Kanan Bawah
    final p4 = Path();
    p4.moveTo(size.width - cornerSize, size.height);
    p4.lineTo(size.width, size.height);
    p4.lineTo(size.width, size.height - cornerSize);
    canvas.drawPath(p4, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
