import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:gtime/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- KONSTANTA WARNA ---
class AppColors {
  static const Color primaryBlue = Color(0xFF0D47A1);
  static const Color accentOrange = Color(0xFFFF6F00);
  static const Color background = Color(0xFFF5F7FA);
  static const Color textDark = Color(0xFF1A1F36);
  static const Color successGreen = Color(0xFF43A047);
  static const Color errorRed = Color(0xFFE53935);
}

class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  State<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _loadAttendanceHistory();
  }

  Future<void> _loadAttendanceHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) {
        setState(() => _error = 'Token expired.');
        return;
      }
      final res = await ApiService().get(
        '/api/attendance-history',
        token: token,
      );

      List<dynamic>? rawList;
      if (res is List) {
        rawList = res;
      } else if (res is Map && res['data'] is List) {
        rawList = res['data'] as List<dynamic>;
      }

      if (rawList == null) {
        _error = 'Format data riwayat tidak valid.';
      } else {
        final parsed = <Map<String, dynamic>>[];
        for (final entry in rawList) {
          if (entry is Map<String, dynamic>) {
            parsed.add(entry);
          } else if (entry is Map) {
            parsed.add(
              entry.map((key, value) => MapEntry(key.toString(), value)),
            );
          }
        }
        _items = parsed;
      }
    } catch (e) {
      _error = 'Gagal memuat: $e';
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- Helper Methods ---
  Color _statusColor(String status) {
    final s = status.toUpperCase();
    if (s == 'IN') return AppColors.successGreen;
    if (s == 'OUT') return AppColors.errorRed;
    return Colors.grey;
  }

  IconData _statusIcon(String status) {
    final s = status.toUpperCase();
    if (s == 'IN') return Icons.login_rounded;
    if (s == 'OUT') return Icons.logout_rounded;
    return Icons.access_time_rounded;
  }

  String _formatDateHeader(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = DateTime(now.year, now.month, now.day - 1);
      final checkDate = DateTime(date.year, date.month, date.day);

      if (checkDate == today) return 'Hari Ini';
      if (checkDate == yesterday) return 'Kemarin';
      return DateFormat(
        'EEEE, d MMM yyyy',
        'id_ID',
      ).format(date); // Butuh inisialisasi locale ID jika error
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Riwayat Aktivitas',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textDark),
      ),
      body: RefreshIndicator(
        onRefresh: _loadAttendanceHistory,
        child: Column(
          children: [
            // --- 1. SUMMARY CARD ---
            _buildSummaryCard(),

            // --- 2. LIST DATA ---
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
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    )
                  : _items.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        // Cek apakah perlu header tanggal (Simple logic for demonstration)
                        // Di production, sebaiknya group data dulu.
                        return _buildTimelineItem(
                          item,
                          index == 0 ||
                              _items[index]['tanggal'] !=
                                  _items[index - 1]['tanggal'],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    // Hitung ringkasan sederhana dari data yang ada
    final totalIn = _items
        .where((i) => i['status_kerja'].toString().toUpperCase() == 'IN')
        .length;
    final totalOut = _items
        .where((i) => i['status_kerja'].toString().toUpperCase() == 'OUT')
        .length;

    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryBlue, Color(0xFF1976D2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('Total Masuk', '$totalIn', Icons.login),
          Container(width: 1, height: 40, color: Colors.white24),
          _buildStatItem('Total Pulang', '$totalOut', Icons.logout),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_toggle_off, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text(
            'Belum ada aktivitas tercatat.',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(Map<String, dynamic> item, bool showHeader) {
    final status = (item['status_kerja'] ?? '').toString();
    final statusColor = _statusColor(status);
    final fingerTime = (item['finger_date'] ?? '').toString();
    final lokasi = (item['nama_printer'] ?? '-').toString();
    final dateLabel = _formatDateHeader(item['tanggal']?.toString() ?? '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeader)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
            child: Text(
              dateLabel.toUpperCase(),
              style: const TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 1,
              ),
            ),
          ),

        Container(
          margin: const EdgeInsets.only(
            bottom: 0,
          ), // Spasi dihandle oleh Padding container
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Timeline Line & Dot
              Column(
                children: [
                  Container(width: 2, height: 20, color: Colors.grey[300]),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _statusIcon(status),
                      size: 16,
                      color: statusColor,
                    ),
                  ),
                  Container(
                    width: 2,
                    height: 50, // Sesuaikan tinggi konten
                    color: Colors.grey[300],
                  ),
                ],
              ),
              const SizedBox(width: 16),

              // Content Card
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              status.toUpperCase() == 'IN'
                                  ? 'Check In'
                                  : 'Check Out',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: AppColors.textDark,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.location_on_outlined,
                                  size: 14,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    lokasi,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            fingerTime,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: statusColor,
                            ),
                          ),
                          Text(
                            status.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: statusColor.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
