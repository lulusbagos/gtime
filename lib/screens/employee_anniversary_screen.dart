import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:gtime/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- KONSTANTA WARNA ---
class AppColors {
  static const Color primaryBlue = Color(0xFF0D47A1);
  static const Color accentOrange = Color(0xFFFF6F00);
  static const Color background = Color(0xFFF5F7FA);
  static const Color textDark = Color(0xFF1A1F36);
  static const LinearGradient celebrationGradient = LinearGradient(
    colors: [Color(0xFFFF9800), Color(0xFFF57C00)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class EmployeeAnniversaryScreen extends StatefulWidget {
  const EmployeeAnniversaryScreen({super.key});

  @override
  State<EmployeeAnniversaryScreen> createState() =>
      _EmployeeAnniversaryScreenState();
}

class _EmployeeAnniversaryScreenState extends State<EmployeeAnniversaryScreen> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _employees = [];
  final String _baseUrl = ApiService.baseUrl;

  @override
  void initState() {
    super.initState();
    _loadTodayAnniversaries();
  }

  Future<void> _loadTodayAnniversaries() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final res = await ApiService().get(
        '/employees/anniversary/today',
        token: token,
      );
      if (res is List) {
        _employees = res
            .map((e) => (e as Map).map((k, v) => MapEntry(k.toString(), v)))
            .cast<Map<String, dynamic>>()
            .toList();
      } else {
        _error = 'Format data tidak sesuai.';
      }
    } catch (e) {
      _error = 'Gagal memuat data: $e';
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('d MMMM yyyy').format(DateTime.now());

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Employee Anniversary',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: RefreshIndicator(
        onRefresh: _loadTodayAnniversaries,
        child: Column(
          children: [
            // --- 1. CELEBRATION HEADER ---
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: AppColors.celebrationGradient,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.celebration_rounded,
                    size: 48,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Hari Ini - $today",
                    style: GoogleFonts.poppins(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Rayakan Bersama Tim!",
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // --- 2. CONTENT LIST ---
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.accentOrange,
                      ),
                    )
                  : _error != null
                  ? Center(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    )
                  : _employees.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      itemCount: _employees.length,
                      itemBuilder: (context, index) {
                        final emp = _employees[index];
                        return _buildAnniversaryCard(emp);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_busy, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'Tidak ada anniversary hari ini.',
            style: GoogleFonts.poppins(color: Colors.grey[500], fontSize: 16),
          ),
        ],
      ),
    );
  }

  ImageProvider? _buildAvatarImage(Map<String, dynamic> emp) {
    final raw = emp['profile_image_url'];
    if (raw == null || raw.toString().isEmpty) return null;
    final url = raw.toString();
    return url.startsWith('http')
        ? NetworkImage(url)
        : NetworkImage('$_baseUrl$url');
  }

  Widget _buildAnniversaryCard(Map<String, dynamic> emp) {
    // Hitung umur berdasarkan tgl_lahir (jika tersedia)
    int years = 0;
    try {
      final dobRaw = emp['tgl_lahir'];
      if (dobRaw != null && dobRaw.toString().isNotEmpty) {
        final dob = DateTime.parse(dobRaw.toString());
        final now = DateTime.now();
        years = now.year - dob.year;
        if (now.month < dob.month ||
            (now.month == dob.month && now.day < dob.day)) {
          years -= 1;
        }
      }
    } catch (_) {
      years = 0;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Background decoration
          Positioned(
            right: -10,
            top: -10,
            child: Icon(
              Icons.star,
              size: 80,
              color: Colors.amber.withOpacity(0.1),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                // Avatar
                Builder(
                  builder: (_) {
                    final avatarImage = _buildAvatarImage(emp);
                    return CircleAvatar(
                      radius: 30,
                      backgroundColor:
                          AppColors.primaryBlue.withOpacity(0.1),
                      backgroundImage: avatarImage,
                      child: avatarImage == null
                          ? Text(
                              (emp['nama_lengkap'] ?? emp['name'] ?? 'U')
                                  .toString()
                                  .characters
                                  .first
                                  .toUpperCase(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryBlue,
                                fontSize: 24,
                              ),
                            )
                          : null,
                    );
                  },
                ),
                const SizedBox(width: 16),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (emp['nama_lengkap'] ?? emp['name'] ?? 'Karyawan')
                            .toString(),
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        (emp['depart'] ?? emp['departemen'] ?? emp['department'] ?? '-')
                            .toString(),
                        style: GoogleFonts.poppins(
                          color: Colors.grey[600],
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        (emp['section'] ?? emp['posisi'] ?? '-').toString(),
                        style: GoogleFonts.poppins(
                          color: Colors.grey[500],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                // Badge Tahun
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accentOrange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.accentOrange.withOpacity(0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        "$years",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.accentOrange,
                          fontSize: 18,
                        ),
                      ),
                      const Text(
                        "Tahun",
                        style: TextStyle(
                          color: AppColors.accentOrange,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
