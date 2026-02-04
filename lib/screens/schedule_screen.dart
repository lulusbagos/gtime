import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gtime/services/api_service.dart';
import 'package:http/http.dart' as http;

// --- CONSTANTS COLORS ---
class AppColors {
  static const Color primaryBlue = Color(0xFF0D47A1);
  static const Color accentOrange = Color(0xFFFF6F00);
  static const Color background = Color(0xFFF5F7FA);
  static const Color textDark = Color(0xFF1A1F36);
  static const Color textGrey = Color(0xFF697386);
  static const LinearGradient blueGradient = LinearGradient(
    colors: [Color(0xFF42A5F5), Color(0xFF1976D2)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

// --- MODEL EVENT (TETAP) ---
class CalendarEvent {
  final String status;
  final String? description;
  final Color color;
  final num lembur;
  final num total;
  final bool isHoliday;

  CalendarEvent({
    required this.status,
    this.description,
    required this.color,
    this.lembur = 0,
    this.total = 0,
    this.isHoliday = false,
  });
}

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  final CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  bool _isLoading = true;
  String? _error;
  Map<DateTime, List<CalendarEvent>> _events = {};
  String? _nik;

  // Legend (Data Tetap)
  final List<Map<String, String>> _legendItems = const [
    {'kode': 'TERM', 'ket': 'Termination', 'warna': '#000000'},
    {'kode': 'A', 'ket': 'Alpha', 'warna': '#f00505'},
    {'kode': 'RSG', 'ket': 'Resign', 'warna': '#a9dbc8'},
    {'kode': 'IN', 'ket': 'Induksi', 'warna': '#928cde'},
    {'kode': 'LWP', 'ket': 'Ijin Dengan Upah', 'warna': '#fff700'},
    {'kode': 'LWoP', 'ket': 'Ijin Tanpa Upah', 'warna': '#f39120'},
    {'kode': 'S', 'ket': 'Sakit', 'warna': '#00ffd5'},
    {'kode': 'TRV', 'ket': 'Travel', 'warna': '#ffae00'},
    {'kode': 'D', 'ket': 'Day Shift', 'warna': '#f79cd4'},
    {'kode': 'N', 'ket': 'Night Shift', 'warna': '#aff381'},
    {'kode': 'CR', 'ket': 'Cuti Roster', 'warna': '#ff4242'},
    {'kode': 'OFF', 'ket': 'OFF', 'warna': '#afa7a7'},
    {'kode': 'AL', 'ket': 'Annual Leave', 'warna': '#c1c2bc'},
    {'kode': 'STB', 'ket': 'STANDBY', 'warna': '#ff0080'},
    {'kode': 'TGS', 'ket': 'TUGAS', 'warna': '#007bff'},
    {'kode': 'DNS', 'ket': 'DINAS', 'warna': '#00ff00'},
    {'kode': 'EOC', 'ket': 'KONTRAK BERAKHIR', 'warna': '#f00000'},
    {'kode': 'MCU', 'ket': 'MCU', 'warna': '#ff8ada'},
    {'kode': 'FMCU', 'ket': 'Followup MCU', 'warna': '#a23f7d'},
    {'kode': 'R', 'ket': 'Reguler', 'warna': '#da49e4'},
  ];

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _loadRosterCalendar();
  }

  // --- LOGIC FUNCTIONS (TIDAK BERUBAH) ---
  List<CalendarEvent> _getEventsForDay(DateTime day) {
    final normalizedDay = DateTime(day.year, day.month, day.day);
    return _events[normalizedDay] ?? [];
  }

  Color _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return AppColors.primaryBlue;
    var value = hex.replaceAll('#', '');
    if (value.length == 6) value = 'FF$value';
    try {
      return Color(int.parse(value, radix: 16));
    } catch (_) {
      return AppColors.primaryBlue;
    }
  }

  Future<void> _loadRosterCalendar() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      _nik = prefs.getString('username');
      if (token == null) {
        setState(() => _error = 'Token expired');
        return;
      }

      final res = await ApiService().get('/api/calendar-roster', token: token);
      final Map<DateTime, List<CalendarEvent>> map = {};

      if (res is List) {
        for (final raw in res) {
          final row = raw as Map;
          final dateRaw = row['working_date'];
          if (dateRaw == null) continue;
          // Normalisasi ke tanggal lokal tanpa jam supaya cocok dengan kalender
          final dateString = dateRaw.toString().substring(0, 10);
          DateTime? d = DateTime.tryParse(dateString);
          if (d == null) continue;

          final dayKey = DateTime(d.year, d.month, d.day);
          final status = (row['status'] ?? '').toString();
          final desc = row['keterangan']?.toString();
          final color = _parseColor(row['warna']?.toString());
          final lemburVal = num.tryParse(row['lembur']?.toString() ?? '0') ?? 0;
          final totalVal = num.tryParse(row['total']?.toString() ?? '0') ?? 0;

          map
              .putIfAbsent(dayKey, () => [])
              .add(
                CalendarEvent(
                  status: status,
                  description: desc,
                  color: color,
                  lembur: lemburVal,
                  total: totalVal,
                ),
              );
        }
      }

      // Load Holidays
      try {
        final uri = Uri.parse(
          'https://hari-libur-api.vercel.app/api?year=${_focusedDay.year}',
        );
        final resp = await http.get(uri).timeout(const Duration(seconds: 5));
        if (resp.statusCode == 200) {
          final List data = jsonDecode(resp.body);
          for (final item in data) {
            final dateStr = item['event_date']?.toString();
            final name = item['event_name']?.toString();
            if (dateStr == null) continue;
            // API sudah YYYY-MM-DD, pakai langsung tanpa zona waktu
            DateTime? d = DateTime.tryParse(dateStr);
            if (d == null) continue;

            final dayKey = DateTime(d.year, d.month, d.day);
            final isNational = item['is_national_holiday'] == true;
            map
                .putIfAbsent(dayKey, () => [])
                .add(
                  CalendarEvent(
                    status: '',
                    description: name,
                    color: isNational ? Colors.redAccent : Colors.orangeAccent,
                    isHoliday: true,
                  ),
                );
          }
        }
      } catch (_) {}

      setState(() => _events = map);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
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
          'Jadwal Kerja',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryBlue),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 16, right: 16, top: 12),
                  child: _buildTodaySummaryCard(),
                ),
                // --- 1. KALENDER CARD ---
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        Container(
                          margin: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 15,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: TableCalendar<CalendarEvent>(
                            firstDay: DateTime.utc(2024, 1, 1),
                            lastDay: DateTime.utc(2030, 12, 31),
                            focusedDay: _focusedDay,
                            calendarFormat: _calendarFormat,
                            availableGestures:
                                AvailableGestures.horizontalSwipe,

                            // Header Style
                            headerStyle: const HeaderStyle(
                              formatButtonVisible: false,
                              titleCentered: true,
                              titleTextStyle: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                                color: AppColors.textDark,
                              ),
                              leftChevronIcon: Icon(
                                Icons.chevron_left,
                                color: AppColors.primaryBlue,
                              ),
                              rightChevronIcon: Icon(
                                Icons.chevron_right,
                                color: AppColors.primaryBlue,
                              ),
                            ),

                            // Calendar Style
                            calendarStyle: CalendarStyle(
                              weekendTextStyle: const TextStyle(
                                color: Colors.red,
                              ),
                              outsideDaysVisible: false,
                            ),

                            // Builders
                            calendarBuilders: CalendarBuilders(
                              defaultBuilder: (context, day, focusedDay) =>
                                  _buildDayCell(day, false, false),
                              todayBuilder: (context, day, focusedDay) =>
                                  _buildDayCell(day, false, true),
                              selectedBuilder: (context, day, focusedDay) =>
                                  _buildDayCell(day, true, false),
                              markerBuilder: (context, day, events) {
                                if (events.isEmpty) return null;
                                return Positioned(
                                  bottom: 1,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: events
                                        .map(
                                          (e) => Container(
                                            margin: const EdgeInsets.symmetric(
                                              horizontal: 1,
                                            ),
                                            width: 5,
                                            height: 5,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: e.color,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                );
                              },
                            ),

                            eventLoader: _getEventsForDay,
                            selectedDayPredicate: (day) =>
                                isSameDay(_selectedDay, day),
                            onDaySelected: (selectedDay, focusedDay) {
                              if (!isSameDay(_selectedDay, selectedDay)) {
                                setState(() {
                                  _selectedDay = selectedDay;
                                  _focusedDay = focusedDay;
                                });
                              }
                            },
                            onPageChanged: (focusedDay) =>
                                _focusedDay = focusedDay,
                          ),
                        ),

                        // --- 2. LEGEND (Expandable) ---
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: ExpansionTile(
                            title: const Text(
                              "Keterangan Kode",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            tilePadding: EdgeInsets.zero,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _legendItems
                                    .map(
                                      (item) => _buildLegendChip(
                                        code: item['kode']!,
                                        label: item['ket']!,
                                        color: _parseColor(item['warna']),
                                      ),
                                    )
                                    .toList(),
                              ),
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 20,
                            right: 20,
                            bottom: 12,
                          ),
                          child: _buildUpcomingAgendaSection(),
                        ),
                      ],
                    ),
                  ),
                ),

                // --- 3. DETAIL EVENT (Bottom Panel) ---
                _buildEventDetailsPanel(),
              ],
            ),
    );
  }

  Widget _buildEventDetailsPanel() {
    final events = _selectedDay != null
        ? _getEventsForDay(_selectedDay!)
        : <CalendarEvent>[];
    final dateStr = _selectedDay != null
        ? DateFormat('EEEE, d MMMM yyyy').format(_selectedDay!)
        : '-';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            dateStr,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            "Detail Jadwal",
            style: TextStyle(
              color: AppColors.textDark,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          if (events.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  children: [
                    Icon(
                      Icons.event_available,
                      size: 40,
                      color: Colors.grey[300],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Tidak ada jadwal khusus",
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
            )
          else
            ...events.map((e) => _buildEventCard(e)),
        ],
      ),
    );
  }

  Widget _buildEventCard(CalendarEvent event) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: event.color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: event.color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: event.color.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: event.isHoliday
                ? Icon(Icons.event_rounded, color: event.color, size: 18)
                : Text(
                    event.status,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: event.color,
                      fontSize: 12,
                    ),
                  ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.description ?? '-',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppColors.textDark,
                  ),
                ),
                if (event.lembur > 0)
                  Text(
                    "Lembur: ${event.lembur} Jam",
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textGrey,
                    ),
                  ),
              ],
            ),
          ),
          if (event.isHoliday)
            const Icon(Icons.beach_access_rounded, color: Colors.orangeAccent),
        ],
      ),
    );
  }

  Widget _buildTodaySummaryCard() {
    final today = DateTime.now();
    final todayKey = DateTime(today.year, today.month, today.day);
    final events = _getEventsForDay(todayKey);
    CalendarEvent? ev;
    if (events.isNotEmpty) {
      ev = events.firstWhere((e) => !e.isHoliday, orElse: () => events.first);
    }

    final nikDisplay = _nik ?? '-';
    final status = ev?.status ?? '-';
    final desc =
        ev?.description ??
        (ev?.isHoliday == true ? 'Roster Kosong' : 'Belum ada keterangan');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.calendar_today_rounded,
              color: AppColors.primaryBlue,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hari ini - NIK $nikDisplay',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textGrey,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Shift: $status',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textGrey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpcomingAgendaSection() {
    if (_events.isEmpty) {
      return const SizedBox.shrink();
    }

    final today = DateTime.now();
    final todayKey = DateTime(today.year, today.month, today.day);

    final upcoming =
        _events.entries
            .where((e) => e.key.isAfter(todayKey) && e.value.isNotEmpty)
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));

    if (upcoming.isEmpty) {
      return const SizedBox.shrink();
    }

    final displayItems = upcoming.take(3);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Agenda Berikutnya',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 8),
        ...displayItems.map((entry) {
          final day = entry.key;
          final events = entry.value;
          CalendarEvent ev = events.firstWhere(
            (e) => !e.isHoliday,
            orElse: () => events.first,
          );
          final dateStr = DateFormat('EEEE, d MMMM').format(day);

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ev.color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ev.color.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 40,
                  decoration: BoxDecoration(
                    color: ev.color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dateStr,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textGrey,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        ev.status,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                      ),
                      if (ev.description != null &&
                          ev.description!.trim().isNotEmpty)
                        Text(
                          ev.description!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textGrey,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildDayCell(DateTime day, bool isSelected, bool isToday) {
    final events = _getEventsForDay(day);
    final CalendarEvent? ev = events.isNotEmpty ? events.first : null;

    final bgColor = ev != null
        ? ev.color.withOpacity(isSelected ? 0.35 : 0.2)
        : (isToday ? AppColors.accentOrange.withOpacity(0.2) : Colors.white);

    final borderColor = isSelected
        ? (ev?.color ?? AppColors.primaryBlue)
        : (isToday ? AppColors.accentOrange : Colors.transparent);

    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
      ),
      child: Center(
        child: Text(
          '${day.day}',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
      ),
    );
  }

  Widget _buildLegendChip({
    required String code,
    required String label,
    required Color color,
  }) {
    return Chip(
      label: Text("$code - $label", style: const TextStyle(fontSize: 11)),
      backgroundColor: Colors.white,
      side: BorderSide(color: color.withOpacity(0.5)),
      avatar: CircleAvatar(backgroundColor: color, radius: 4),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}
