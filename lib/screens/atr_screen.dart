import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gtime/services/api_service.dart';

// --- Model Data (TETAP) ---
class AtrHistoryItem {
  final DateTime tanggal;
  final String kodeShift;
  final String? warna;
  final String? jamIn;
  final String? jamOut;

  AtrHistoryItem({
    required this.tanggal,
    required this.kodeShift,
    this.warna,
    this.jamIn,
    this.jamOut,
  });

  factory AtrHistoryItem.fromJson(Map<String, dynamic> json) {
    return AtrHistoryItem(
      tanggal: DateTime.parse(json['tanggal'] as String),
      kodeShift: json['kode_shift'] as String,
      warna: json['warna'] as String?,
      jamIn: json['jam_in'] as String?,
      jamOut: json['jam_out'] as String?,
    );
  }
}

// --- Enum Filter (TETAP) ---
enum AtrMonthFilter { current, previous }

// --- CONSTANTS COLORS (SAMA SEPERTI SCREEN LAIN) ---
class AppColors {
  static const Color primaryBlue = Color(0xFF0D47A1);
  static const Color accentOrange = Color(0xFFFF6F00);
  static const Color softGrey = Color(0xFFF5F7FA);
  static const LinearGradient blueGradient = LinearGradient(
    colors: [Color(0xFF42A5F5), Color(0xFF1976D2)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class ATRScreen extends StatefulWidget {
  const ATRScreen({super.key});

  @override
  State<ATRScreen> createState() => _ATRScreenState();
}

class _ATRScreenState extends State<ATRScreen> {
  // --- State Data ---
  List<AtrHistoryItem> _history = [];
  bool _isLoading = true;
  String? _error;
  final String _baseUrl = ApiService.baseUrl;

  // --- Info User ---
  String? _namaLengkap;
  String? _username;

  // --- Filter ---
  AtrMonthFilter _selectedMonth = AtrMonthFilter.current;

  // --- Processing ---
  bool _isProcessingPdf = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    await _loadUserDetails();
    await _fetchAtrHistory();
  }

  Future<void> _loadUserDetails() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _namaLengkap = prefs.getString('nama_lengkap');
      _username = prefs.getString('username');
    });
  }

  // --- LOGIC FETCH DATA (TIDAK BERUBAH) ---
  Future<void> _fetchAtrHistory() async {
    if (_username == null) {
      setState(() {
        _isLoading = false;
        _error = 'User not found.';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final now = DateTime.now();
      final year = _selectedMonth == AtrMonthFilter.current
          ? now.year
          : (now.month == 1 ? now.year - 1 : now.year);
      final month = _selectedMonth == AtrMonthFilter.current
          ? now.month
          : (now.month == 1 ? 12 : now.month - 1);

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final endpoint =
          '/api/atrhistory?username=$_username&year=$year&month=$month';

      dynamic response;
      try {
        response = await ApiService().get(endpoint, token: token);
      } on ApiException catch (e) {
        // Token expired/invalid or other API error
        setState(() {
          _isLoading = false;
          if (e.toString().contains('Unauthorized')) {
            _error =
                'Sesi login habis atau token tidak valid. Silakan login ulang.';
          } else {
            _error = e.toString();
          }
        });
        return;
      }

      List<dynamic>? rawList;
      if (response is List) {
        rawList = response;
      } else if (response is Map && response['data'] is List) {
        rawList = response['data'] as List<dynamic>;
      }

      if (rawList == null) {
        setState(() {
          _isLoading = false;
          _error =
              'Format data tidak sesuai. Silakan login ulang atau hubungi admin.';
        });
      } else {
        final parsed = <AtrHistoryItem>[];
        for (final item in rawList) {
          if (item is Map<String, dynamic>) {
            parsed.add(AtrHistoryItem.fromJson(item));
          } else if (item is Map) {
            parsed.add(
              AtrHistoryItem.fromJson(
                item.map((k, v) => MapEntry(k.toString(), v)),
              ),
            );
          }
        }

        setState(() {
          _history = parsed;
          _isLoading = false;
        });
      }
    } catch (e) {
      log("Error ATR: $e");
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  // --- LOGIC PDF (TIDAK BERUBAH) ---
  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.primaryBlue),
              const SizedBox(width: 20),
              Text(message),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _generateAndSharePdf() async {
    if (_isProcessingPdf) return;
    setState(() => _isProcessingPdf = true);
    _showLoadingDialog('Sharing PDF...');
    try {
      final pdfBytes = await _generatePdf();
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/atr_report.pdf');
      await file.writeAsBytes(pdfBytes);
      if (mounted) Navigator.of(context).pop();
      await Share.shareXFiles([
        XFile(file.path),
      ], text: 'Laporan ATR - $_namaLengkap');
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal share: $e')));
    } finally {
      setState(() => _isProcessingPdf = false);
    }
  }

  Future<void> _generateAndDownloadPdf() async {
    if (_isProcessingPdf) return;
    setState(() => _isProcessingPdf = true);
    _showLoadingDialog('Downloading PDF...');
    try {
      final pdfBytes = await _generatePdf();
      await Printing.sharePdf(bytes: pdfBytes, filename: 'atr_report.pdf');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal download: $e')));
    } finally {
      setState(() => _isProcessingPdf = false);
    }
  }

  Future<Uint8List> _generatePdf() async {
    final pdf = pw.Document();
    final monthName = _selectedMonth == AtrMonthFilter.current
        ? DateFormat('MMMM yyyy').format(DateTime.now())
        : DateFormat(
            'MMMM yyyy',
          ).format(DateTime(DateTime.now().year, DateTime.now().month - 1));

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Header(
                level: 0,
                child: pw.Text(
                  'Laporan ATR (Attendance Report)',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Nama: $_namaLengkap'),
                      pw.Text('NIK: $_username'),
                    ],
                  ),
                  pw.Text(
                    'Periode: $monthName',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
              pw.Divider(height: 20),
              pw.Table(
                border: pw.TableBorder.all(
                  color: PdfColors.grey400,
                  width: 0.5,
                ),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey200,
                    ),
                    children: ['Tanggal', 'Shift', 'Jam In', 'Jam Out']
                        .map(
                          (h) => pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(
                              h,
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  ..._history.map((item) {
                    final color = item.warna != null
                        ? PdfColor.fromHex(item.warna!)
                        : PdfColors.white;
                    return pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            DateFormat('dd-MM-yy').format(item.tanggal),
                          ),
                        ),
                        pw.Container(
                          color: color,
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            item.kodeShift,
                            textAlign: pw.TextAlign.center,
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(_formatJam(item.jamIn)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(_formatJam(item.jamOut)),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ],
          );
        },
      ),
    );
    return pdf.save();
  }

  // --- Helper UI ---
  Color _hexToColor(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    try {
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (e) {
      return Colors.transparent;
    }
  }

  String _formatJam(String? jam) {
    if (jam == null) return '-';
    try {
      return jam.substring(0, 5);
    } catch (e) {
      return jam;
    }
  }

  // ===========================================================================
  // === BAGIAN UI YANG DIPERBARUI (MODERN & PROFESSIONAL) ===
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.softGrey,
      appBar: AppBar(
        title: const Text(
          'History Absensi',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        centerTitle: true,
      ),
      // --- FAB Modern untuk Aksi PDF ---
      floatingActionButton: _history.isNotEmpty
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: "share",
                  onPressed: _isProcessingPdf ? null : _generateAndSharePdf,
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primaryBlue,
                  child: const Icon(Icons.share_rounded),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: "download",
                  onPressed: _isProcessingPdf ? null : _generateAndDownloadPdf,
                  backgroundColor: AppColors.accentOrange,
                  child: _isProcessingPdf
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Icon(Icons.file_download_rounded),
                ),
              ],
            )
          : null,
      body: Column(
        children: [
          // --- 1. HEADER PROFILE CARD ---
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppColors.blueGradient,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryBlue.withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                      child: const CircleAvatar(
                        radius: 28,
                        backgroundColor: AppColors.softGrey,
                        child: Icon(
                          Icons.person,
                          size: 32,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _namaLengkap ?? 'Loading...',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _username ?? '-',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // --- 2. MODERN FILTER TABS ---
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(25),
            ),
            child: Row(
              children: [
                _buildFilterTab("Bulan Ini", AtrMonthFilter.current),
                _buildFilterTab("Bulan Lalu", AtrMonthFilter.previous),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // --- 3. DATA TABLE LIST ---
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primaryBlue,
                    ),
                  )
                : _error != null
                ? Center(
                    child: Text(
                      'Error: $_error',
                      style: const TextStyle(color: Colors.red),
                    ),
                  )
                : _history.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.history_toggle_off,
                          size: 60,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "Belum ada data absensi",
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  )
                : Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Column(
                        children: [
                          // Table Header
                          Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 16,
                            ),
                            color: Colors.grey[100],
                            child: Row(
                              children: const [
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    "Tanggal",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: Center(
                                    child: Text(
                                      "Shift",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: Center(
                                    child: Text(
                                      "In",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: Center(
                                    child: Text(
                                      "Out",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Table List
                          Expanded(
                            child: ListView.separated(
                              padding: EdgeInsets.zero,
                              itemCount: _history.length,
                              separatorBuilder: (ctx, i) => const Divider(
                                height: 1,
                                color: Color(0xFFEEEEEE),
                              ),
                              itemBuilder: (context, index) {
                                final item = _history[index];
                                final shiftColor = item.warna != null
                                    ? _hexToColor(item.warna!)
                                    : Colors.grey[300];
                                // Cek apakah warna terlalu terang untuk teks putih
                                final isLightColor =
                                    shiftColor!.computeLuminance() > 0.5;

                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                    horizontal: 16,
                                  ),
                                  color: index % 2 == 0
                                      ? Colors.white
                                      : const Color(
                                          0xFFFAFAFA,
                                        ), // Zebra striping
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              DateFormat(
                                                'dd MMM yyyy',
                                              ).format(item.tanggal),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                              ),
                                            ),
                                            Text(
                                              DateFormat(
                                                'EEEE',
                                              ).format(item.tanggal),
                                              style: TextStyle(
                                                color: Colors.grey[500],
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: Center(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: shiftColor,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              item.kodeShift,
                                              style: TextStyle(
                                                color: isLightColor
                                                    ? Colors.black87
                                                    : Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: Center(
                                          child: Text(
                                            _formatJam(item.jamIn),
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: item.jamIn == null
                                                  ? Colors.grey[300]
                                                  : Colors.green[700],
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: Center(
                                          child: Text(
                                            _formatJam(item.jamOut),
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: item.jamOut == null
                                                  ? Colors.grey[300]
                                                  : Colors.red[700],
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 80), // Space for FAB
        ],
      ),
    );
  }

  // --- Helper Widget: Filter Tab ---
  Widget _buildFilterTab(String label, AtrMonthFilter value) {
    final bool isSelected = _selectedMonth == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedMonth = value;
            _fetchAtrHistory();
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isSelected ? AppColors.primaryBlue : Colors.grey[600],
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
