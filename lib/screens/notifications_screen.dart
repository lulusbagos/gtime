import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gtime/services/api_service.dart';

// --- Model Data (TETAP) ---
class NotificationItem {
  final String id;
  final String judul;
  final String pesan;
  final int status; // 0 = unread, 1 = read
  final DateTime createdAt;

  NotificationItem({
    required this.id,
    required this.judul,
    required this.pesan,
    required this.status,
    required this.createdAt,
  });

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id'] as String,
      judul: json['judul'] as String? ?? 'Tanpa Judul',
      pesan: json['pesan'] as String? ?? 'Tanpa Pesan',
      status: json['status'] as int? ?? 0,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

// --- CONSTANTS COLORS ---
class AppColors {
  static const Color primaryBlue = Color(0xFF0D47A1);
  static const Color accentOrange = Color(0xFFFF6F00);
  static const Color background = Color(0xFFF5F7FA);
  static const Color textDark = Color(0xFF1A1F36);
  static const Color textGrey = Color(0xFF697386);
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<NotificationItem> _notifications = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  // --- LOGIC FETCH (TIDAK BERUBAH) ---
  Future<List<NotificationItem>> _fetchNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final nik = prefs.getString('username');

    if (token == null || nik == null) throw Exception('Auth required');

    final response = await ApiService().get(
      '/notifications?nik=$nik',
      token: token,
    );

    final List<dynamic> data = response as List<dynamic>;
    final now = DateTime.now();
    final cutOffDate = now.subtract(const Duration(days: 3)); // Filter 3 hari

    final allNotifications = data.map(
      (json) => NotificationItem.fromJson(json),
    );
    return allNotifications
        .where((notif) => notif.createdAt.isAfter(cutOffDate))
        .toList();
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final items = await _fetchNotifications();
      if (!mounted) return;
      setState(() {
        _notifications = items;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _markAsRead(NotificationItem item) async {
    if (item.status == 1) return;
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final nik = prefs.getString('username');
    if (token == null || nik == null) return;

    try {
      _setItemRead(item.id);
      await ApiService().put(
        '/notifications/mark-read',
        token: token,
        body: {'nik': nik, 'id': item.id},
      );
    } catch (_) {
      _loadNotifications();
    }
  }

  void _setItemRead(String id) {
    final idx = _notifications.indexWhere((n) => n.id == id);
    if (idx == -1) return;
    final current = _notifications[idx];
    final updated = NotificationItem(
      id: current.id,
      judul: current.judul,
      pesan: current.pesan,
      status: 1,
      createdAt: current.createdAt,
    );
    setState(() {
      _notifications = List<NotificationItem>.from(_notifications)
        ..[idx] = updated;
    });
  }

  // --- HELPER UI ---
  String _getGroupLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final checkDate = DateTime(date.year, date.month, date.day);

    if (checkDate == today) return 'Hari Ini';
    if (checkDate == yesterday) return 'Kemarin';
    return DateFormat('d MMM yyyy').format(date);
  }

  String _formatTime(DateTime date) {
    return DateFormat('HH:mm').format(date);
  }

  // ===========================================================================
  // === BAGIAN UI YANG DIPERBARUI (MODERN & CLEAN) ===
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Inbox',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textDark),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.done_all_rounded,
              color: AppColors.primaryBlue,
            ),
            onPressed: () {
              // Opsional: Tombol manual refresh/mark read
              _loadNotifications();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryBlue),
            )
          : _errorMessage != null
              ? Center(
                  child: Text(
                    'Gagal memuat: $_errorMessage',
                    style: const TextStyle(color: Colors.red),
                  ),
                )
              : _notifications.isEmpty
                  ? _buildEmptyState()
                  : _buildNotificationList(),
    );
  }

  Widget _buildNotificationList() {
    Map<String, List<NotificationItem>> groupedNotifications = {};
    for (var notif in _notifications) {
      String group = _getGroupLabel(notif.createdAt);
      if (!groupedNotifications.containsKey(group)) {
        groupedNotifications[group] = [];
      }
      groupedNotifications[group]!.add(notif);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: groupedNotifications.length,
      itemBuilder: (context, index) {
        String key = groupedNotifications.keys.elementAt(index);
        List<NotificationItem> items = groupedNotifications[key]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Group Header ---
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 12,
                horizontal: 4,
              ),
              child: Text(
                key.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.textGrey,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ),
            // --- List Items ---
            ...items.map((item) => _buildNotificationCard(item)),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Icon(
              Icons.mark_email_read_outlined,
              size: 64,
              color: AppColors.primaryBlue.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Semua Beres!',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tidak ada notifikasi baru dalam 3 hari terakhir.',
            style: TextStyle(color: AppColors.textGrey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(NotificationItem item) {
    bool isUnread = item.status == 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            _markAsRead(item);
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- Icon Kiri ---
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isUnread
                        ? AppColors.primaryBlue.withOpacity(0.1)
                        : Colors.grey[100],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isUnread
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_none_rounded,
                    color: isUnread ? AppColors.primaryBlue : Colors.grey[400],
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),

                // --- Konten Teks ---
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              item.judul,
                              style: TextStyle(
                                fontWeight: isUnread
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                                fontSize: 15,
                                color: isUnread
                                    ? AppColors.textDark
                                    : AppColors.textDark.withOpacity(0.8),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Waktu di pojok kanan atas
                          Text(
                            _formatTime(item.createdAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: isUnread
                                  ? AppColors.primaryBlue
                                  : AppColors.textGrey,
                              fontWeight: isUnread
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isUnread ? 'Belum dibaca' : 'Sudah dibaca',
                        style: TextStyle(
                          fontSize: 11,
                          color: isUnread
                              ? AppColors.accentOrange
                              : AppColors.textGrey,
                          fontWeight:
                              isUnread ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.pesan,
                        style: TextStyle(
                          fontSize: 13,
                          color: isUnread
                              ? AppColors.textDark.withOpacity(0.8)
                              : AppColors.textGrey,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // --- Indikator Unread (Titik Biru) ---
                if (isUnread)
                  Container(
                    margin: const EdgeInsets.only(left: 8, top: 4),
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.accentOrange, // Orange dot for attention
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
