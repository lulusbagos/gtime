import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';

class KantinHistoryEntry {
  final String nik;
  final String namaLengkap;
  final String depart;
  final DateTime? tanggal;
  final String waktuRaw;
  final String sesiMakan;
  final String perusahaan;
  final String originalDepart;

  KantinHistoryEntry({
    required this.nik,
    required this.namaLengkap,
    required this.depart,
    required this.tanggal,
    required this.waktuRaw,
    required this.sesiMakan,
    required this.perusahaan,
    required this.originalDepart,
  });

  DateTime? get timestamp {
    if (tanggal == null) return null;
    if (waktuRaw.isEmpty) return tanggal;
    try {
      final parts = waktuRaw.split(':');
      if (parts.length >= 2) {
        final seconds = parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0;
        return DateTime(
          tanggal!.year,
          tanggal!.month,
          tanggal!.day,
          int.tryParse(parts[0]) ?? 0,
          int.tryParse(parts[1]) ?? 0,
          seconds,
        );
      }
    } catch (_) {
      // ignore parse error and fallback below
    }
    return tanggal;
  }

  String get tanggalString =>
      tanggal != null ? DateFormat('EEEE, dd MMM yyyy', 'id_ID').format(tanggal!) : '-';

  factory KantinHistoryEntry.fromJson(Map<String, dynamic> json) {
    DateTime? parsedDate;
    final tanggalRaw = json['tanggal']?.toString();
    if (tanggalRaw != null && tanggalRaw.isNotEmpty) {
      parsedDate = DateTime.tryParse(tanggalRaw);
    }

    return KantinHistoryEntry(
      nik: json['nik']?.toString() ?? '-',
      namaLengkap: json['nama_lengkap']?.toString() ?? '-',
      depart: json['depart']?.toString() ?? '-',
      tanggal: parsedDate,
      waktuRaw: json['waktu']?.toString() ?? json['time']?.toString() ?? '',
      sesiMakan: json['sesi_makan']?.toString() ?? '-',
      perusahaan: json['nama_perusahaan']?.toString() ?? '-',
      originalDepart: json['original_depart']?.toString() ?? '-',
    );
  }
}

class KantinHistoryScreen extends StatefulWidget {
  const KantinHistoryScreen({super.key});

  @override
  State<KantinHistoryScreen> createState() => _KantinHistoryScreenState();
}

class _KantinHistoryScreenState extends State<KantinHistoryScreen> {
  final DateFormat _timeFormat = DateFormat('HH:mm');
  final List<KantinHistoryEntry> _history = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await initializeDateFormatting('id_ID', null);
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) {
        throw ApiException('Token tidak ditemukan. Silakan login ulang.');
      }

      final response = await ApiService().get('/api/kantin/history', token: token);
      final List<dynamic> rows;
      if (response is Map<String, dynamic>) {
        final payload = response['data'];
        rows = payload is List ? payload : const [];
      } else if (response is List) {
        rows = response;
      } else {
        rows = const [];
      }

      final parsed = rows
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .map(KantinHistoryEntry.fromJson)
          .toList();

      setState(() {
        _history
          ..clear()
          ..addAll(parsed);
      });
    } catch (e) {
      setState(() {
        _errorMessage = e is ApiException ? e.message : e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        title: const Text('Histori Kantin'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: RefreshIndicator(
        onRefresh: _loadHistory,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _ErrorState(message: _errorMessage!, onRetry: _loadHistory),
        ],
      );
    }

    if (_history.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: const [
          _EmptyState(),
        ],
      );
    }

    final lastVisit = _history.isEmpty ? null : _history.first;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      itemCount: _history.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _SummaryCard(totalVisit: _history.length, lastVisit: lastVisit);
        }
        final item = _history[index - 1];
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: _HistoryCard(entry: item, timeFormat: _timeFormat),
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final int totalVisit;
  final KantinHistoryEntry? lastVisit;

  const _SummaryCard({required this.totalVisit, required this.lastVisit});

  @override
  Widget build(BuildContext context) {
    final subtitle = lastVisit == null
        ? 'Belum ada kunjungan'
        : 'Terakhir ${lastVisit!.tanggalString} | ${lastVisit!.waktuRaw}';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade200.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.restaurant_menu_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Kunjungan Kantin',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${totalVisit}x',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.white.withOpacity(0.9)),
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final KantinHistoryEntry entry;
  final DateFormat timeFormat;

  const _HistoryCard({required this.entry, required this.timeFormat});

  @override
  Widget build(BuildContext context) {
    final timestamp = entry.timestamp;
    final timeDisplay = timestamp != null ? timeFormat.format(timestamp) : entry.waktuRaw;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.schedule_rounded, color: Color(0xFF1565C0)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.tanggalString,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${entry.namaLengkap} | ${entry.depart}',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              _SessionBadge(text: entry.sesiMakan),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.access_time, size: 16, color: Colors.grey.shade500),
              const SizedBox(width: 6),
              Text(timeDisplay, style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Icon(Icons.apartment_rounded, size: 16, color: Colors.grey.shade500),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  entry.perusahaan,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.layers_rounded, size: 16, color: Colors.grey.shade500),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Original Depart: ${entry.originalDepart}',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SessionBadge extends StatelessWidget {
  final String text;
  const _SessionBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = _sessionColors(text);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: colors.text,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  _SessionColor _sessionColors(String sesi) {
    switch (sesi.toUpperCase()) {
      case 'MAKAN PAGI':
        return const _SessionColor(
          background: Color(0xFFFFF3E0),
          border: Color(0xFFFFB74D),
          text: Color(0xFFEF6C00),
        );
      case 'MAKAN SIANG':
        return const _SessionColor(
          background: Color(0xFFE3F2FD),
          border: Color(0xFF64B5F6),
          text: Color(0xFF1565C0),
        );
      case 'MAKAN MALAM':
        return const _SessionColor(
          background: Color(0xFFEDE7F6),
          border: Color(0xFF9575CD),
          text: Color(0xFF5E35B1),
        );
      default:
        return const _SessionColor(
          background: Color(0xFFF5F5F5),
          border: Color(0xFFBDBDBD),
          text: Color(0xFF616161),
        );
    }
  }
}

class _SessionColor {
  final Color background;
  final Color border;
  final Color text;

  const _SessionColor({
    required this.background,
    required this.border,
    required this.text,
  });
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        children: [
          const Icon(Icons.restaurant_outlined, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            'Belum ada histori kantin',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Kunjungi kantin perusahaan untuk melihat riwayat di sini.',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
          const SizedBox(height: 12),
          Text(
            'Gagal memuat data',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: Colors.red.shade400),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => onRetry(),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Coba Lagi'),
          ),
        ],
      ),
    );
  }
}

