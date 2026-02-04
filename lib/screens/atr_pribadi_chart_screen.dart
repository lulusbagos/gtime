import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gtime/services/api_service.dart';

// --- PALET WARNA PREMIUM (Navy & Gold Accent) ---
class AppColors {
  static const Color darkNavy = Color(
    0xFF0F172A,
  ); // Background utama gelap (opsional) atau teks
  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color background = Color(0xFFF1F5F9); // Light Gray-Blueish
  static const Color cardColor = Colors.white;
  static const Color successGreen = Color(0xFF10B981);
  static const Color errorRed = Color(0xFFEF4444);
  static const Color textDark = Color(0xFF1E293B);
  static const Color textGrey = Color(0xFF64748B);
}

class AtrPribadiChartScreen extends StatefulWidget {
  const AtrPribadiChartScreen({super.key});

  @override
  State<AtrPribadiChartScreen> createState() => _AtrPribadiChartScreenState();
}

class _AtrPribadiChartScreenState extends State<AtrPribadiChartScreen> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) {
        setState(() => _error = 'Sesi berakhir.');
        return;
      }
      final res = await ApiService().get('/api/atr-pribadi', token: token);
      if (res is List) {
        _items = res
            .map((e) => (e as Map).map((k, v) => MapEntry(k.toString(), v)))
            .cast<Map<String, dynamic>>()
            .toList();
      } else {
        _error = 'Format data salah.';
      }
    } catch (e) {
      _error = 'Error: $e';
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- Helper ---
  double _parsePercent(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    if (value is String) {
      if (value.trim().isEmpty) return 0;
      return double.tryParse(value.replaceAll('%', '').trim()) ?? 0;
    }
    return 0;
  }

  Color _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return Colors.blueGrey;
    var value = hex.replaceAll('#', '');
    if (value.length == 6) value = 'FF$value';
    try {
      return Color(int.parse(value, radix: 16));
    } catch (_) {
      return Colors.blueGrey;
    }
  }

  // Menghitung rata-rata performa keseluruhan
  double _calculateOverallScore() {
    if (_items.isEmpty) return 0;
    double totalPercent = 0;
    int count = 0;
    for (var item in _items) {
      final shiftCode = (item['kode_shift'] ?? '').toString().toUpperCase();
      if (shiftCode != 'D' && shiftCode != 'N') {
        continue; // Hanya hitung Day Shift (D) & Night Shift (N)
      }
      totalPercent += _parsePercent(item['persen_in_ada']);
      totalPercent += _parsePercent(item['persen_out_ada']);
      count += 2; // In + Out
    }
    return count == 0 ? 0 : totalPercent / count;
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('MMMM yyyy').format(DateTime.now());
    final overallScore = _calculateOverallScore();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Performa Kehadiran',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
        centerTitle: true,
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textDark),
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primaryBlue),
              )
            : _error != null
            ? Center(
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              )
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // --- 1. HERO SCORE CARD (Lingkaran Besar) ---
                    _buildOverallPerformanceCard(overallScore, dateLabel),

                    const SizedBox(height: 24),

                    // --- 2. SECTION TITLE ---
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Detail Per Shift",
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // --- 3. LIST CARDS (GRID STYLE) ---
                    ..._items.map((item) => _buildDetailCard(item)),

                    const SizedBox(height: 30),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildOverallPerformanceCard(double score, String date) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            "Total Performance",
            style: GoogleFonts.poppins(
              color: AppColors.textGrey,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            date,
            style: GoogleFonts.poppins(
              color: AppColors.textDark,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),

          // --- CIRCULAR INDICATOR BESAR ---
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 140,
                height: 140,
                child: CircularProgressIndicator(
                  value: 1.0, // Background circle
                  strokeWidth: 12,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.grey.shade100,
                  ),
                ),
              ),
              SizedBox(
                width: 140,
                height: 140,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: score / 100),
                  duration: const Duration(seconds: 2),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) {
                    return CircularProgressIndicator(
                      value: value,
                      strokeWidth: 12,
                      strokeCap: StrokeCap.round,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        score >= 90
                            ? AppColors.successGreen
                            : (score >= 70
                                  ? Colors.orange
                                  : AppColors.errorRed),
                      ),
                    );
                  },
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "${score.toStringAsFixed(1)}%",
                    style: GoogleFonts.poppins(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                  Text(
                    "Average",
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppColors.textGrey,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailCard(Map<String, dynamic> item) {
    final shift = (item['kode_shift'] ?? '').toString();
    final desc = (item['keterangan'] ?? '').toString();
    final totalRow = item['total_row']?.toString() ?? '0';
    final pIn = _parsePercent(item['persen_in_ada']);
    final pOut = _parsePercent(item['persen_out_ada']);
    final color = _parseColor(item['warna']?.toString());

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header: Shift Info
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  shift,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      desc,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppColors.textDark,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      "Total Hari: $totalRow",
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Stats Row: IN & OUT side by side
          Row(
            children: [
              _buildMiniCircularStat("IN", pIn, AppColors.successGreen),
              Container(
                width: 1,
                height: 40,
                color: Colors.grey.shade200,
              ), // Divider
              _buildMiniCircularStat("OUT", pOut, AppColors.errorRed),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniCircularStat(String label, double percentage, Color color) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 45,
            height: 45,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: 1.0,
                  strokeWidth: 4,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    color.withOpacity(0.1),
                  ),
                ),
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: percentage / 100),
                  duration: const Duration(seconds: 1),
                  builder: (context, value, _) {
                    return CircularProgressIndicator(
                      value: value,
                      strokeWidth: 4,
                      strokeCap: StrokeCap.round,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    );
                  },
                ),
                Text(
                  "${percentage.toInt()}%",
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: AppColors.textGrey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                "Kehadiran",
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  color: Colors.grey.shade400,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
