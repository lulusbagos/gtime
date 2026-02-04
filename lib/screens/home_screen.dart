library home_screen;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gtime/screens/attendance_screen.dart';
import 'package:gtime/screens/news_screen.dart';
import 'package:gtime/screens/notifications_screen.dart';
import 'package:gtime/screens/profile_screen.dart';
import 'package:gtime/screens/atr_screen.dart';
import 'package:gtime/screens/schedule_screen.dart';
import 'package:gtime/screens/p5m_screen.dart';
import 'package:gtime/screens/smart_zone_screen.dart';
import 'package:gtime/screens/employee_anniversary_screen.dart';
import 'package:gtime/screens/attendance_history_screen.dart';
import 'package:gtime/screens/atr_pribadi_chart_screen.dart';
import 'package:gtime/screens/heregistrasi_screen.dart';
import 'package:gtime/screens/qr_attendance_screen.dart';
import 'package:gtime/services/api_service.dart';
import 'package:gtime/screens/lembur_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gtime/screens/kantin_history_screen.dart';
import 'package:gtime/screens/revisi_absen_screen.dart';
import 'package:gtime/screens/barge_movement_report_screen.dart';
import 'package:gtime/screens/barge_logbook_screen.dart';

// --- PALET WARNA PREMIUM (MINING THEME) ---
class AppColors {
  static const Color primaryDark = Color(0xFF0D47A1); // Deep Navy
  static const Color primaryLight = Color(0xFF1976D2);
  static const Color accentOrange = Color(0xFFFF6F00); // Safety Orange
  static const Color background = Color(0xFFF8F9FD);
  static const Color textDark = Color(0xFF1A1F36);
  static const Color textGrey = Color(0xFF697386);
  static const LinearGradient blueGradient = LinearGradient(
    colors: [Color(0xFF42A5F5), Color(0xFF1565C0)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const String _askedLocationPermissionKey =
      'asked_location_permission';
  String? _namaLengkap;
  String? _posisi;
  String? _profileImageUrl;
  List<Map<String, dynamic>> _newsBanners = [];
  List<Map<String, dynamic>> _runningTexts = [];
  String? _newsError;
  String? _runningTextError;
  String? _todayRosterStatus;
  String? _todayRosterDescription;
  Color _todayRosterColor = Colors.green;
  bool _isLoadingRoster = false;
  String? _rosterError;
  int _unreadCount = 0;
  bool _isLoadingAttendanceStatus = false;
  bool _hasCheckInToday = false;
  bool _hasCheckOutToday = false;
  String? _checkInTime;
  String? _checkOutTime;
  String? _attendanceStatusError;
  final String _baseUrl = ApiService.baseUrl;
  int _bottomNavIndex = 0;
  int _currentCarouselIndex = 0;
  String? _homeAdUrl;
  bool _homeAdShown = false;

  bool _weatherLoading = false;
  String? _weatherError;
  double? _weatherTempC;
  int? _weatherCode;
  String? _weatherLabel;
  IconData _weatherIcon = Icons.wb_sunny_rounded;
  LinearGradient _weatherGradient = AppColors.blueGradient;
  DateTime? _weatherLastUpdatedAt;

  late AnimationController _entranceController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeData();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _entranceController.forward();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _checkAndPromptUpdate(context),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _entranceController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Auto refresh cuaca saat kembali ke app, tapi jangan spam.
      final last = _weatherLastUpdatedAt;
      final shouldRefresh =
          last == null ||
          DateTime.now().difference(last) > const Duration(minutes: 2);
      if (shouldRefresh && !_weatherLoading) {
        _loadWeather();
      }
    }
  }

  Future<void> _initializeData() async {
    await _loadUser();
    await _loadNewsBanners();
    await _fetchUnreadCount();
    await _loadRunningText();
    await _loadTodayRoster();
    await _loadTodayAttendanceStatus();
    await _loadWeather();
    await _loadHomeAd();
  }

  Future<void> _loadHomeAd() async {
    if (_homeAdShown) return;
    try {
      final res = await ApiService().get('/api/ads/home');
      if (res is Map) {
        final raw = (res['image_url'] ?? '').toString().trim();
        if (raw.isNotEmpty) {
          _homeAdUrl = _resolveImageUrl(raw);
          if (!mounted) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showHomeAdDialog();
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _loadWeather() async {
    if (!mounted) return;
    if (_weatherLoading) return;
    setState(() {
      _weatherLoading = true;
      _weatherError = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          _showLocationSettingsDialog(
            'Lokasi Wajib Aktif',
            'Aktifkan layanan lokasi/GPS agar cuaca bisa dimuat.',
            openLocationSettings: true,
          );
        }
        throw Exception('Layanan lokasi tidak aktif.');
      }

      var permission = await Geolocator.checkPermission();
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
            'Berikan izin lokasi agar cuaca bisa dimuat.',
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

      final last = await Geolocator.getLastKnownPosition();
      final pos =
          last ??
          await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.low,
            timeLimit: const Duration(seconds: 8),
          );

      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=${pos.latitude}'
        '&longitude=${pos.longitude}'
        '&current=temperature_2m,weather_code'
        '&timezone=auto',
      );

      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        throw Exception('Gagal memuat cuaca (${res.statusCode}).');
      }

      final json = jsonDecode(res.body);
      final current = (json is Map) ? json['current'] : null;
      if (current is! Map) {
        throw Exception('Format cuaca tidak valid.');
      }

      final tempRaw = current['temperature_2m'];
      final codeRaw = current['weather_code'];
      final temp = (tempRaw is num) ? tempRaw.toDouble() : null;
      final code = (codeRaw is num) ? codeRaw.toInt() : null;
      if (temp == null || code == null) {
        throw Exception('Data cuaca tidak lengkap.');
      }

      final themed = _weatherTheme(code);
      if (!mounted) return;
      setState(() {
        _weatherTempC = temp;
        _weatherCode = code;
        _weatherLabel = themed.label;
        _weatherIcon = themed.icon;
        _weatherGradient = themed.gradient;
        _weatherLoading = false;
        _weatherLastUpdatedAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _weatherLoading = false;
        _weatherError = e.toString();
        _weatherTempC = null;
        _weatherCode = null;
        _weatherLabel = null;
        _weatherIcon = Icons.cloud_off_rounded;
        _weatherGradient = AppColors.blueGradient;
        _weatherLastUpdatedAt = DateTime.now();
      });
    }
  }

  _WeatherTheme _weatherTheme(int code) {
    // Open-Meteo weather_code groups:
    // 0 clear, 1-3 cloudy, 45-48 fog, 51-57 drizzle, 61-67 rain,
    // 71-77 snow, 80-82 showers, 95-99 thunder.
    if (code == 0) {
      return _WeatherTheme(
        label: 'Cerah',
        icon: Icons.wb_sunny_rounded,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.accentOrange, AppColors.primaryLight],
        ),
      );
    }

    if (code >= 1 && code <= 3) {
      return _WeatherTheme(
        label: 'Berawan',
        icon: Icons.cloud_rounded,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryLight, AppColors.primaryDark],
        ),
      );
    }

    if (code == 45 || code == 48) {
      return _WeatherTheme(
        label: 'Berkabut',
        icon: Icons.blur_on_rounded,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.grey.shade700, AppColors.primaryDark],
        ),
      );
    }

    if (code >= 51 && code <= 57) {
      return _WeatherTheme(
        label: 'Gerimis',
        icon: Icons.grain_rounded,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryLight, Colors.grey.shade600],
        ),
      );
    }

    if (code >= 61 && code <= 67) {
      return _WeatherTheme(
        label: 'Hujan',
        icon: Icons.beach_access_rounded,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryDark, AppColors.primaryLight],
        ),
      );
    }

    if (code >= 71 && code <= 77) {
      return _WeatherTheme(
        label: 'Salju',
        icon: Icons.ac_unit_rounded,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryLight, Colors.white],
        ),
      );
    }

    if (code >= 80 && code <= 82) {
      return _WeatherTheme(
        label: 'Hujan',
        icon: Icons.opacity_rounded,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryDark, AppColors.accentOrange],
        ),
      );
    }

    if (code >= 95 && code <= 99) {
      return _WeatherTheme(
        label: 'Badai',
        icon: Icons.thunderstorm_rounded,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.textDark, AppColors.primaryDark],
        ),
      );
    }

    return _WeatherTheme(
      label: 'Cuaca',
      icon: Icons.cloud_rounded,
      gradient: AppColors.blueGradient,
    );
  }

  // --- LOGIC FETCH DATA ---
  Future<void> _fetchUnreadCount() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null) return;
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/notifications/unread-count'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() => _unreadCount = data['count'] as int? ?? 0);
      }
    } catch (_) {}
  }

  Future<void> _loadNewsBanners() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null) return;
    try {
      final response = await ApiService().get('/news', token: token);
      final List<dynamic> newsData;
      if (response is List) {
        newsData = response;
      } else if (response is Map && response['data'] is List) {
        newsData = response['data'] as List<dynamic>;
      } else {
        newsData = const [];
      }
      setState(() {
        _newsBanners = newsData
            .whereType<Map>()
            .map(
              (item) => {
                'title': item['title']?.toString() ?? 'No Title',
                'subtitle': item['subtitle']?.toString() ?? 'No Subtitle',
                'image_url': item['image_url']?.toString(),
              },
            )
            .toList();
        _newsError = _newsBanners.isEmpty ? 'Belum ada berita tersedia' : null;
      });
    } catch (e) {
      setState(() {
        _newsError = 'Gagal memuat berita: $e';
        _newsBanners = [];
      });
    }
  }

  Future<void> _loadRunningText() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null) return;
    try {
      final response = await ApiService().get(
        '/api/running-text',
        token: token,
      );
      final List<dynamic> data;
      if (response is List) {
        data = response;
      } else if (response is Map && response['data'] is List) {
        data = response['data'] as List<dynamic>;
      } else {
        data = const [];
      }
      setState(() {
        _runningTexts = data
            .whereType<Map>()
            .map(
              (item) => {
                'id': item['id'],
                'text': item['text'] ?? '',
                'color': item['color'] ?? '#FFDD00',
              },
            )
            .toList();
        _runningTextError = _runningTexts.isEmpty
            ? 'Belum ada pengumuman berjalan.'
            : null;
      });
    } catch (e) {
      setState(() {
        _runningTextError = 'Gagal memuat running text: $e';
        _runningTexts = [];
      });
    }
  }

  Color _parseHexColor(String? hex, {Color fallback = Colors.green}) {
    if (hex == null || hex.isEmpty) return fallback;
    var value = hex.replaceAll('#', '');
    if (value.length == 6) value = 'FF$value';
    try {
      return Color(int.parse(value, radix: 16));
    } catch (_) {
      return fallback;
    }
  }

  DateTime? _parseDateOnly(dynamic raw) {
    if (raw == null) return null;
    final value = raw.toString();
    DateTime? parsed;
    try {
      parsed = DateTime.parse(value).toLocal();
    } catch (_) {
      final trimmed = value.length >= 10 ? value.substring(0, 10) : value;
      try {
        parsed = DateTime.parse(trimmed);
      } catch (_) {
        return null;
      }
    }
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  void _showLocationSettingsDialog(
    String title,
    String message, {
    bool openLocationSettings = false,
  }) {
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
              if (openLocationSettings) {
                Geolocator.openLocationSettings();
              } else {
                Geolocator.openAppSettings();
              }
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

  String? _pickLatestTime(String? current, String? candidate) {
    if (candidate == null || candidate.trim().isEmpty) return current;
    if (current == null || current.trim().isEmpty) return candidate;

    final currentDt = DateTime.tryParse(current);
    final candidateDt = DateTime.tryParse(candidate);
    if (currentDt != null && candidateDt != null) {
      return candidateDt.isAfter(currentDt) ? candidate : current;
    }

    final currentText = current.trim();
    final candidateText = candidate.trim();
    return candidateText.compareTo(currentText) > 0 ? candidate : current;
  }

  Future<void> _loadTodayRoster() async {
    setState(() {
      _isLoadingRoster = true;
      _rosterError = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) {
        setState(() {
          _isLoadingRoster = false;
          _rosterError = 'Token tidak ditemukan.';
        });
        return;
      }

      final response = await ApiService().get(
        '/api/calendar-roster',
        token: token,
      );
      String? status;
      String? desc;
      Color color = Colors.green;

      if (response is List) {
        final today = DateTime.now();
        final todayKey = DateTime(today.year, today.month, today.day);
        for (final item in response) {
          if (item is! Map) continue;
          final workingDate = _parseDateOnly(item['working_date']);
          if (workingDate == null) continue;
          if (workingDate == todayKey) {
            status = item['status']?.toString();
            desc = item['keterangan']?.toString();
            color = _parseHexColor(item['warna']?.toString(), fallback: color);
            break;
          }
        }
      } else {
        throw Exception('Format roster tidak valid');
      }

      setState(() {
        _todayRosterStatus = status;
        _todayRosterDescription = desc;
        _todayRosterColor = color;
        _isLoadingRoster = false;
        _rosterError = null;
      });
    } catch (e) {
      setState(() {
        _isLoadingRoster = false;
        _rosterError = 'Gagal memuat jadwal: $e';
      });
    }
  }

  Future<void> _loadTodayAttendanceStatus() async {
    setState(() {
      _isLoadingAttendanceStatus = true;
      _attendanceStatusError = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) {
        setState(() {
          _attendanceStatusError = 'Token tidak ditemukan.';
          _isLoadingAttendanceStatus = false;
        });
        return;
      }

      final response = await ApiService().get(
        '/api/attendance-today',
        token: token,
      );

      bool hasIn = false;
      bool hasOut = false;
      String? inTime;
      String? outTime;
      final today = DateTime.now();
      final todayKey = DateTime(today.year, today.month, today.day);

      if (response is List) {
        for (final item in response) {
          if (item is! Map) continue;
          final dateKey = _parseDateOnly(item['tanggal']);
          if (dateKey == null || dateKey != todayKey) continue;

          final jamIn = item['jam_in']?.toString().trim();
          final jamOut = item['jam_out']?.toString().trim();
          if (jamIn != null && jamIn.isNotEmpty) {
            hasIn = true;
            inTime = _pickLatestTime(inTime, jamIn);
          }
          if (jamOut != null && jamOut.isNotEmpty) {
            hasOut = true;
            outTime = _pickLatestTime(outTime, jamOut);
          }
        }
      } else {
        throw Exception('Respon status absen tidak valid');
      }

      if (!hasIn || !hasOut) {
        final raw = prefs.getString('attendance_history');
        if (raw != null && raw.isNotEmpty) {
          final List decoded = jsonDecode(raw) as List;
          for (final item in decoded) {
            if (item is! Map) continue;
            final dateKey = _parseDateOnly(item['timestamp']);
            if (dateKey == null || dateKey != todayKey) continue;

            final status =
                item['status']?.toString().trim().toUpperCase();
            final timestamp = item['timestamp']?.toString();
            if (status == 'IN' && !hasIn) {
              hasIn = true;
              inTime = _pickLatestTime(inTime, timestamp);
            } else if (status == 'OUT' && !hasOut) {
              hasOut = true;
              outTime = _pickLatestTime(outTime, timestamp);
            }

            if (hasIn && hasOut) break;
          }
        }
      }

      setState(() {
        _hasCheckInToday = hasIn;
        _hasCheckOutToday = hasOut;
        _checkInTime = inTime;
        _checkOutTime = outTime;
        _isLoadingAttendanceStatus = false;
      });
    } catch (e) {
      setState(() {
        _attendanceStatusError = 'Gagal memuat status absen: $e';
        _isLoadingAttendanceStatus = false;
      });
    }
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _namaLengkap = prefs.getString('nama_lengkap') ?? 'Guest';
      _posisi = prefs.getString('posisi') ?? '-';
      _profileImageUrl =
          prefs.getString('avatar') ?? prefs.getString('profile_image_url');
    });
  }

  Future<void> _checkAndPromptUpdate(BuildContext context) async {
    try {
      final info = await PackageInfo.fromPlatform();
      final localVersion = '${info.version}+${info.buildNumber}';
      final res = await ApiService().get('/api/app-version');
      if (res is Map) {
        final serverVersion = (res['version'] ?? '').toString();
        final apkUrl = (res['apk_url'] ?? '').toString();
        if (serverVersion.isNotEmpty &&
            apkUrl.isNotEmpty &&
            serverVersion.trim() != localVersion.trim()) {
          // Logic update dialog here
        }
      }
    } catch (_) {}
  }

  ImageProvider? _buildAvatarImageProvider() {
    if (_profileImageUrl != null && _profileImageUrl!.isNotEmpty) {
      return _profileImageUrl!.startsWith('http')
          ? NetworkImage(_profileImageUrl!)
          : NetworkImage(_resolveImageUrl(_profileImageUrl!));
    }
    return null;
  }

  String _resolveImageUrl(String raw) {
    if (raw.startsWith('http')) return raw;
    final base = ApiService.baseUrl;
    final baseNormalized =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final path = raw.startsWith('/') ? raw : '/$raw';
    return '$baseNormalized$path';
  }

  void _showHomeAdDialog() {
    if (_homeAdShown || _homeAdUrl == null || _homeAdUrl!.isEmpty) return;
    _homeAdShown = true;
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          backgroundColor: Colors.transparent,
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.network(
                  _homeAdUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: InkWell(
                  onTap: () => Navigator.pop(ctx),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- NAVIGATION ---
  void _navTo(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  void _openNotifications() => _navTo(const NotificationsScreen());
  void _openProfile() => _navTo(const ProfileScreen());
  void _openQrAttendance() => _navTo(const QrAttendanceScreen());

  // --- UI BUILDER ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: _buildBottomNavBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Header (Profile & Greeting)
              _buildAnimated(0, _buildHeader()),
              const SizedBox(height: 20),

              // 2. RUNNING TEXT (PENGUMUMAN) - BARU
              _buildAnimated(1, _buildRunningTickerSection()),
              const SizedBox(height: 16),

              // 3. STATS ROW (CUACA + JAM & NETWORK) - DIPERBAIKI
              _buildAnimated(2, _buildStatsRow()),
              const SizedBox(height: 16),

              // 4. SHIFT INFO CARD - BARU
              _buildAnimated(
                3,
                CurrentShiftCard(
                  isLoading: _isLoadingRoster,
                  status: _todayRosterStatus,
                  description: _todayRosterDescription,
                  error: _rosterError,
                  accentColor: _todayRosterColor,
                  attendanceLoading: _isLoadingAttendanceStatus,
                  hasCheckIn: _hasCheckInToday,
                  hasCheckOut: _hasCheckOutToday,
                  checkInTime: _checkInTime,
                  checkOutTime: _checkOutTime,
                  attendanceError: _attendanceStatusError,
                ),
              ),
              const SizedBox(height: 24),

              // 5. News Carousel
              _buildAnimated(4, _buildNewsSection()),
              const SizedBox(height: 32),

              // 6. MAIN MENUS
              _buildAnimated(
                5,
                _buildSectionTitle('Menu Utama', 'Akses Cepat'),
              ),
              const SizedBox(height: 16),
              _buildAnimated(6, _buildMainMenuGrid()),

              const SizedBox(height: 32),
              _buildAnimated(
                7,
                _buildSectionTitle('Kekaryawanan', 'HRIS & Administrasi'),
              ),
              const SizedBox(height: 16),
              _buildAnimated(8, _buildEmployeeGrid()),

              const SizedBox(height: 32),
              _buildAnimated(
                9,
                _buildSectionTitle('Barge', 'Movement & Report'),
              ),
              const SizedBox(height: 16),
              _buildAnimated(10, _buildBargeGrid()),

              const SizedBox(height: 32),
              _buildAnimated(
                11,
                _buildSectionTitle('Keuangan & Fasilitas', 'Data Pribadi'),
              ),
              const SizedBox(height: 16),
              _buildAnimated(12, _buildFinanceOfficeGrid()),

              const SizedBox(height: 32),
              _buildAnimated(
                13,
                _buildSectionTitle('Layanan Umum', 'Support & Operasional'),
              ),
              const SizedBox(height: 16),
              _buildAnimated(14, _buildGeneralServicesGrid()),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnimated(int index, Widget child) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(
          parent: _entranceController,
          curve: Interval(index * 0.05, 1.0, curve: Curves.easeOut),
        ),
      ),
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
            .animate(
              CurvedAnimation(
                parent: _entranceController,
                curve: Interval(index * 0.05, 1.0, curve: Curves.easeOut),
              ),
            ),
        child: child,
      ),
    );
  }

  Widget _buildBottomNavBar() {
    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final alignmentX = -1 + (2 * ((_bottomNavIndex + 0.5) / 4));
          return ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(22),
              topRight: Radius.circular(22),
            ),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.primaryLight.withOpacity(0.05),
                    Colors.white,
                  ],
                ),
                border: Border(
                  top: BorderSide(
                    color: AppColors.primaryLight.withOpacity(0.10),
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 24,
                    offset: const Offset(0, -8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 3,
                    child: AnimatedAlign(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment(alignmentX, 0),
                      child: Container(
                        width: constraints.maxWidth / 7,
                        height: 3,
                        decoration: BoxDecoration(
                          color: AppColors.primaryDark,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  BottomNavigationBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    selectedItemColor: AppColors.primaryDark,
                    unselectedItemColor: Colors.grey[450],
                    type: BottomNavigationBarType.fixed,
                    currentIndex: _bottomNavIndex,
                    iconSize: 22,
                    selectedFontSize: 11,
                    unselectedFontSize: 11,
                    onTap: (index) {
                      setState(() => _bottomNavIndex = index);
                      if (index == 1) _navTo(const ScheduleScreen());
                      if (index == 2) _openNotifications();
                      if (index == 3) _openProfile();
                    },
                    items: const [
                      BottomNavigationBarItem(
                        icon: Icon(Icons.dashboard_rounded),
                        label: 'Home',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.calendar_month_rounded),
                        label: 'Jadwal',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.notifications_rounded),
                        label: 'Inbox',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.person_rounded),
                        label: 'Profil',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Halo, Selamat Pagi',
                style: TextStyle(color: AppColors.textGrey, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                _namaLengkap ?? 'Loading...',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                _posisi ?? '-',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Row(
          children: [
            InkWell(
              onTap: _openQrAttendance,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.qr_code_scanner_rounded,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: _openProfile,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primaryLight, width: 2),
                ),
                child: CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.grey[200],
                  backgroundImage: _buildAvatarImageProvider(),
                  child: _profileImageUrl == null
                      ? const Icon(Icons.person, color: Colors.grey)
                      : null,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatsRow() {
    return SizedBox(
      height: 95, // Tinggi sedikit ditambah agar muat jam
      child: Row(
        children: [
          Expanded(
            flex: 6,
            child: ForecastBanner(
              isLoading: _weatherLoading,
              error: _weatherError,
              tempC: _weatherTempC,
              label: _weatherLabel,
              icon: _weatherIcon,
              gradient: _weatherGradient,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(flex: 4, child: NetworkStatusCard()), // Sinyal + Ping
        ],
      ),
    );
  }

  Widget _buildRunningTickerSection() {
    if (_runningTexts.isNotEmpty) {
      return AnnouncementTicker(items: _runningTexts);
    }
    if (_runningTextError != null) {
      return _buildInfoBanner(
        _runningTextError!,
        icon: Icons.campaign_outlined,
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildInfoBanner(
    String message, {
    IconData icon = Icons.info_outline_rounded,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.primaryLight.withOpacity(0.12),
            child: Icon(icon, color: AppColors.primaryDark),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: AppColors.textGrey.withOpacity(0.9),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- MENU GRIDS ---
  Widget _buildNewsSection() {
    if (_newsBanners.isEmpty) {
      if (_newsError != null) {
        return _buildInfoBanner(_newsError!, icon: Icons.article_outlined);
      }
      return const SizedBox();
    }
    return Column(
      children: [
        CarouselSlider.builder(
          itemCount: _newsBanners.length,
          options: CarouselOptions(
            height: 160,
            autoPlay: true,
            viewportFraction: 1.0,
            onPageChanged: (index, reason) =>
                setState(() => _currentCarouselIndex = index),
          ),
          itemBuilder: (context, index, _) {
            final item = _newsBanners[index];
            final title = (item['title'] as String?) ?? 'No Title';
            final subtitle = (item['subtitle'] as String?) ?? '';
            final imageUrl = (item['image_url'] as String?) ?? '';
            DecorationImage? backgroundImage;
            if (imageUrl.isNotEmpty) {
              final resolvedUrl = _resolveImageUrl(imageUrl);
              backgroundImage = DecorationImage(
                image: NetworkImage(resolvedUrl),
                fit: BoxFit.cover,
                onError: (_, __) {},
              );
            }

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.grey[300],
                image: backgroundImage,
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                padding: const EdgeInsets.all(16),
                alignment: Alignment.bottomLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: _newsBanners.asMap().entries.map((entry) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: _currentCarouselIndex == entry.key ? 20.0 : 8.0,
              height: 8.0,
              margin: const EdgeInsets.symmetric(horizontal: 4.0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: _currentCarouselIndex == entry.key
                    ? AppColors.primaryDark
                    : Colors.grey[300],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: AppColors.textGrey),
        ),
      ],
    );
  }

  Widget _buildMainMenuGrid() {
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: _HeroCard(
            title: 'Absensi',
            subtitle: 'Check In/Out',
            icon: Icons.fingerprint_rounded,
            color: AppColors.primaryDark,
            onTap: () => _navTo(const AttendanceScreen()),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 4,
          child: Column(
            children: [
              _MenuCard(
                title: 'ATR System',
                icon: Icons.analytics_rounded,
                color: AppColors.primaryLight,
                onTap: () => _navTo(const ATRScreen()),
              ),
              const SizedBox(height: 12),
              _MenuCard(
                title: 'Berita',
                icon: Icons.newspaper_rounded,
                color: AppColors.accentOrange,
                onTap: () => _navTo(const NewsScreen()),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmployeeGrid() {
    final items = [
      {
        't': 'Scan QR',
        'i': Icons.qr_code_scanner_rounded,
        'c': AppColors.primaryDark,
        'p': const QrAttendanceScreen(),
      },
      {
        't': 'P5M',
        'i': Icons.checklist_rtl_rounded,
        'c': AppColors.primaryLight,
        'p': const P5MScreen(),
      },
      {
        't': 'Smart Zone',
        'i': Icons.school_rounded,
        'c': AppColors.accentOrange,
        'p': const SmartZoneScreen(),
      },
      {
        't': 'ATR Pribadi',
        'i': Icons.pie_chart_rounded,
        'c': AppColors.primaryDark,
        'p': const AtrPribadiChartScreen(),
      },
      {
        't': 'Anniversary',
        'i': Icons.cake_rounded,
        'c': AppColors.primaryLight,
        'p': const EmployeeAnniversaryScreen(),
      },
      {
        't': 'Riwayat',
        'i': Icons.history_rounded,
        'c': AppColors.accentOrange,
        'p': const AttendanceHistoryScreen(),
      },
      {
        't': 'Heregistrasi',
        'i': Icons.badge_rounded,
        'c': AppColors.primaryDark,
        'p': const HeregistrasiScreen(),
      },
      {
        't': 'Revisi Absen',
        'i': Icons.edit_calendar_rounded,
        'c': AppColors.primaryLight,
        'p': const RevisiAbsenScreen(),
      },
      {
        't': 'Lembur',
        'i': Icons.watch_later_rounded,
        'c': AppColors.accentOrange,
        'p': const LemburScreen(),
      },
      {
        't': 'Tugas Saya',
        'i': Icons.assignment_rounded,
        'c': AppColors.primaryDark,
        'cs': true,
      },
      {
        't': 'Laporan',
        'i': Icons.summarize_rounded,
        'c': AppColors.primaryLight,
        'cs': true,
      },
    ];
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: items
          .map(
            (e) => _IconMenu(
              title: e['t'] as String,
              icon: e['i'] as IconData,
              color: e['c'] as Color,
              isComingSoon: e['cs'] == true,
              onTap: () => e['cs'] == true
                  ? _showComingSoon()
                  : _navTo(e['p'] as Widget),
            ),
          )
          .toList(),
    );
  }

  Widget _buildBargeGrid() {
    final items = [
      {
        't': 'Movement Report',
        'i': Icons.directions_boat_filled_rounded,
        'c': AppColors.primaryDark,
        'p': const BargeMovementReportScreen(),
      },
      {
        't': 'Log Book',
        'i': Icons.menu_book_rounded,
        'c': AppColors.primaryDark,
        'p': const BargeLogbookScreen(),
      },
      {
        't': 'Laporan Cuaca',
        'i': Icons.cloud_rounded,
        'c': AppColors.primaryLight,
        'cs': true,
      },
      {
        't': 'Map Movement Barge',
        'i': Icons.map_rounded,
        'c': AppColors.accentOrange,
        'cs': true,
      },
      {
        't': 'Sea State',
        'i': Icons.waves_rounded,
        'c': AppColors.primaryDark,
        'cs': true,
      },
      {
        't': 'Tide & Current',
        'i': Icons.water_rounded,
        'c': AppColors.primaryLight,
        'cs': true,
      },
      {
        't': 'Safety Check',
        'i': Icons.shield_rounded,
        'c': AppColors.accentOrange,
        'cs': true,
      },
    ];
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: items
          .map(
            (e) => _IconMenu(
              title: e['t'] as String,
              icon: e['i'] as IconData,
              color: e['c'] as Color,
              isComingSoon: e['cs'] == true,
              onTap: () => e['cs'] == true
                  ? _showComingSoon()
                  : _navTo(e['p'] as Widget),
            ),
          )
          .toList(),
    );
  }

  Widget _buildFinanceOfficeGrid() {
    final items = [
      {
        't': 'Payslip',
        'i': Icons.receipt_long_rounded,
        'c': AppColors.primaryDark,
      },
      {
        't': 'Pinjaman',
        'i': Icons.monetization_on_rounded,
        'c': AppColors.primaryLight,
      },
      {
        't': 'Ruangan',
        'i': Icons.meeting_room_rounded,
        'c': AppColors.accentOrange,
      },
      {
        't': 'Kendaraan',
        'i': Icons.directions_car_rounded,
        'c': AppColors.primaryDark,
      },
      {
        't': 'Reimburse',
        'i': Icons.attach_money_rounded,
        'c': AppColors.primaryLight,
      },
      {
        't': 'Klaim',
        'i': Icons.assignment_turned_in_rounded,
        'c': AppColors.accentOrange,
      },
      {
        't': 'BPJS',
        'i': Icons.health_and_safety_rounded,
        'c': AppColors.primaryDark,
      },
      {
        't': 'Koperasi',
        'i': Icons.storefront_rounded,
        'c': AppColors.primaryLight,
      },
    ];
    return Wrap(
      spacing: 20,
      runSpacing: 20,
      alignment: WrapAlignment.start,
      children: items
          .map(
            (e) => _IconMenu(
              title: e['t'] as String,
              icon: e['i'] as IconData,
              color: e['c'] as Color,
              isComingSoon: true,
              onTap: _showComingSoon,
            ),
          )
          .toList(),
    );
  }

  Widget _buildGeneralServicesGrid() {
    final items = [
      {
        't': 'Helpdesk',
        'i': Icons.support_agent_rounded,
        'c': AppColors.primaryDark,
      },
      {
        't': 'Reimburse',
        'i': Icons.attach_money_rounded,
        'c': AppColors.primaryLight,
      },
      {
        't': 'Dinas Luar',
        'i': Icons.flight_takeoff_rounded,
        'c': AppColors.accentOrange,
      },
      {
        't': 'Kantin',
        'i': Icons.restaurant_rounded,
        'c': AppColors.accentOrange,
      },
      {'t': 'Tamu', 'i': Icons.qr_code_rounded, 'c': AppColors.primaryDark},
      {
        't': 'Directory',
        'i': Icons.contacts_rounded,
        'c': AppColors.primaryLight,
      },
      {'t': 'Survey', 'i': Icons.poll_rounded, 'c': AppColors.accentOrange},
      {'t': 'Training', 'i': Icons.school_rounded, 'c': AppColors.primaryDark},
      {
        't': 'Dokumen',
        'i': Icons.folder_copy_rounded,
        'c': AppColors.primaryLight,
      },
    ];
    return Wrap(
      spacing: 20,
      runSpacing: 20,
      alignment: WrapAlignment.start,
      children: items.map((e) {
        final title = e['t'] as String;
        final isKantin = title == 'Kantin';
        return _IconMenu(
          title: title,
          icon: e['i'] as IconData,
          color: e['c'] as Color,
          isComingSoon: !isKantin,
          onTap: isKantin
              ? () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const KantinHistoryScreen(),
                  ),
                )
              : _showComingSoon,
        );
      }).toList(),
    );
  }

  void _showComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          "Fitur ini akan segera hadir dalam update berikutnya.",
        ),
        backgroundColor: AppColors.textDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

// ==========================================
// --- CUSTOM WIDGETS ---
// ==========================================

// 1. Tombol Bounce
class _BounceButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _BounceButton({required this.child, required this.onTap});
  @override
  State<_BounceButton> createState() => _BounceButtonState();
}

class _BounceButtonState extends State<_BounceButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
      lowerBound: 0.9,
      upperBound: 1.0,
    )..value = 1.0;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.reverse(),
      onTapUp: (_) {
        _controller.forward();
        widget.onTap();
      },
      onTapCancel: () => _controller.forward(),
      child: ScaleTransition(scale: _controller, child: widget.child),
    );
  }
}

// 2. Kartu Besar & Menu
class _HeroCard extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _HeroCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return _BounceButton(
      onTap: onTap,
      child: Container(
        height: 160,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.4),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 32),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _MenuCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return _BounceButton(
      onTap: onTap,
      child: Container(
        height: 74,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, AppColors.primaryLight.withOpacity(0.04)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primaryLight.withOpacity(0.08)),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryDark.withOpacity(0.06),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color.withOpacity(0.18), color.withOpacity(0.06)],
                ),
                border: Border.all(color: color.withOpacity(0.16)),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconMenu extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final bool isComingSoon;
  final VoidCallback onTap;
  const _IconMenu({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
    this.isComingSoon = false,
  });

  static const String _comingSoonBadgeAsset = 'icon/logoapps.png';

  @override
  Widget build(BuildContext context) {
    final iconColor = isComingSoon ? Colors.grey.shade400 : color;
    return _BounceButton(
      onTap: onTap,
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white,
                      AppColors.primaryLight.withOpacity(0.035),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isComingSoon
                        ? Colors.grey.shade200
                        : iconColor.withOpacity(0.12),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryDark.withOpacity(0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Center(child: Icon(icon, color: iconColor, size: 26)),
                    if (isComingSoon)
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: Opacity(
                          opacity: 0.55,
                          child: Image.asset(
                            _comingSoonBadgeAsset,
                            width: 16,
                            height: 16,
                            color: Colors.grey.shade500,
                            colorBlendMode: BlendMode.srcIn,
                          ),
                        ),
                      ),
                    if (!isComingSoon)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  iconColor.withOpacity(0.10),
                                  Colors.transparent,
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (isComingSoon)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock_rounded,
                      color: Colors.grey,
                      size: 10,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 60,
            child: Text(
              title,
              style: TextStyle(
                fontSize: 11,
                color: isComingSoon ? Colors.grey : AppColors.textDark,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// 3. Network Card (Live Ping Simulation)
class NetworkStatusCard extends StatefulWidget {
  const NetworkStatusCard({super.key});
  @override
  State<NetworkStatusCard> createState() => _NetworkStatusCardState();
}

class _NetworkStatusCardState extends State<NetworkStatusCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _blinkController;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _refreshTimer;
  bool isOnline = false;
  bool _apiOnline = false;
  bool _isCheckingApi = false;
  int? _pingMs;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _startMonitoring();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _connSub?.cancel();
    _blinkController.dispose();
    super.dispose();
  }

  void _startMonitoring() {
    _refreshStatus();
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final online =
          results.isNotEmpty && !results.contains(ConnectivityResult.none);
      if (online != isOnline && mounted) {
        setState(() => isOnline = online);
      }
      if (online) {
        _checkApi();
      } else if (mounted) {
        setState(() {
          _apiOnline = false;
          _pingMs = null;
        });
      }
    });

    _refreshTimer = Timer.periodic(
      const Duration(seconds: 25),
      (_) => _refreshStatus(),
    );
  }

  Future<void> _refreshStatus() async {
    final results = await Connectivity().checkConnectivity();
    final online =
        results.isNotEmpty && !results.contains(ConnectivityResult.none);
    if (mounted) {
      setState(() => isOnline = online);
    }
    if (online) {
      await _checkApi();
    } else if (mounted) {
      setState(() {
        _apiOnline = false;
        _pingMs = null;
      });
    }
  }

  Future<void> _checkApi() async {
    if (_isCheckingApi) return;
    _isCheckingApi = true;
    final stopwatch = Stopwatch()..start();
    try {
      final base = ApiService.baseUrl;
      final normalizedBase = base.endsWith('/')
          ? base.substring(0, base.length - 1)
          : base;
      final uri = Uri.parse('$normalizedBase/api/app-version');
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      stopwatch.stop();
      if (!mounted) return;
      setState(() {
        _apiOnline = res.statusCode >= 200 && res.statusCode < 300;
        _pingMs = _apiOnline ? stopwatch.elapsedMilliseconds : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _apiOnline = false;
        _pingMs = null;
      });
    } finally {
      _isCheckingApi = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 140;
        final apiLabel = _apiOnline ? 'API TERHUBUNG' : 'API PUTUS';
        final apiLabelCompact = _apiOnline ? 'API OK' : 'API DOWN';
        final apiColor = _apiOnline ? Colors.green.shade700 : Colors.red;
        final statusLabel = isOnline ? 'TERHUBUNG' : 'TERPUTUS';
        final statusLabelCompact = isOnline ? 'ON' : 'OFF';
        final pingText =
            "Ping ${_pingMs != null ? '${_pingMs}ms' : '--'}";

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isOnline ? Icons.wifi : Icons.wifi_off_rounded,
                    color: isOnline ? Colors.green : Colors.red,
                    size: compact ? 16 : 20,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      compact ? statusLabelCompact : statusLabel,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isOnline ? Colors.green[700] : Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: compact ? 11 : 13,
                      ),
                    ),
                  ),
                  if (!compact) ...[
                    const Spacer(),
                    if (isOnline)
                      FadeTransition(
                        opacity: _blinkController,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                  if (compact && isOnline)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: FadeTransition(
                        opacity: _blinkController,
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              if (compact)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pingText,
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.grey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      apiLabelCompact,
                      style: TextStyle(
                        fontSize: 9,
                        color: apiColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pingText,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.grey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: apiColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        apiLabel,
                        style: TextStyle(
                          fontSize: 9,
                          color: apiColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

// 4. Forecast Banner + Realtime Clock
class ForecastBanner extends StatelessWidget {
  const ForecastBanner({
    super.key,
    required this.isLoading,
    required this.error,
    required this.tempC,
    required this.label,
    required this.icon,
    required this.gradient,
  });

  final bool isLoading;
  final String? error;
  final double? tempC;
  final String? label;
  final IconData icon;
  final LinearGradient gradient;

  @override
  Widget build(BuildContext context) {
    final effectiveTemp = (tempC != null) ? '${tempC!.round()}°C' : '--°C';
    final primaryLabel = label ?? 'Lokasi Saya';

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 170;
        final ultraCompact = constraints.maxWidth < 155;
        final now = DateTime.now();
        final time =
            "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

        Widget content;
        if (compact) {
          content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.22),
                        width: 1,
                      ),
                    ),
                    child: Icon(icon, color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    effectiveTemp,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                  if (isLoading) ...[
                    const SizedBox(width: 8),
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ],
                ],
              ),
              if (!ultraCompact) ...[
                const SizedBox(height: 4),
                Text(
                  time,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  "WITA",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
              ] else
                const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(
                    Icons.location_on,
                    color: Colors.white70,
                    size: 11,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      error != null ? 'Cuaca tidak tersedia' : primaryLabel,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ],
          );
        } else {
          content = Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.22),
                            width: 1,
                          ),
                        ),
                        child: Icon(icon, color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        effectiveTemp,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 26,
                        ),
                      ),
                      if (isLoading) ...[
                        const SizedBox(width: 10),
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        color: Colors.white70,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        error != null ? 'Cuaca tidak tersedia' : primaryLabel,
                        style:
                            const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
              StreamBuilder(
                stream: Stream.periodic(const Duration(seconds: 1)),
                builder: (context, snapshot) {
                  final live = DateTime.now();
                  final liveTime =
                      "${live.hour.toString().padLeft(2, '0')}:${live.minute.toString().padLeft(2, '0')}";
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        liveTime,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      const Text(
                        "WITA",
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          );
        }

        return Container(
          padding: EdgeInsets.all(compact ? 12 : 16),
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryDark.withOpacity(0.22),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: compact
              ? FittedBox(
                  alignment: Alignment.topLeft,
                  fit: BoxFit.scaleDown,
                  child: SizedBox(width: constraints.maxWidth, child: content),
                )
              : content,
        );
      },
    );
  }
}

class _WeatherTheme {
  const _WeatherTheme({
    required this.label,
    required this.icon,
    required this.gradient,
  });

  final String label;
  final IconData icon;
  final LinearGradient gradient;
}

// 5. Shift Info Card
class CurrentShiftCard extends StatelessWidget {
  final bool isLoading;
  final String? status;
  final String? description;
  final String? error;
  final Color accentColor;
  final bool attendanceLoading;
  final bool hasCheckIn;
  final bool hasCheckOut;
  final String? checkInTime;
  final String? checkOutTime;
  final String? attendanceError;

  const CurrentShiftCard({
    super.key,
    required this.isLoading,
    this.status,
    this.description,
    this.error,
    this.accentColor = Colors.green,
    this.attendanceLoading = false,
    this.hasCheckIn = false,
    this.hasCheckOut = false,
    this.checkInTime,
    this.checkOutTime,
    this.attendanceError,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasData =
        (status != null && status!.trim().isNotEmpty) ||
        (description != null && description!.trim().isNotEmpty);
    final String primaryLine = hasData
        ? (status ?? description ?? '-')
        : 'Shift belum tersedia';
    final String secondaryLine = hasData
        ? (description != null && description!.trim().isNotEmpty
              ? description!
              : 'Tidak ada keterangan tambahan.')
        : (error ?? 'Belum ada data roster untuk hari ini.');
    final Color badgeColor = hasData ? accentColor : Colors.grey.shade500;
    final String badgeText = hasData ? 'Aktif' : 'N/A';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
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
                  color: accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.wb_sunny_rounded, color: accentColor),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Jadwal Hari Ini",
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    if (isLoading)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(
                          minHeight: 4,
                          color: accentColor,
                          backgroundColor: accentColor.withOpacity(0.2),
                        ),
                      )
                    else ...[
                      Text(
                        primaryLine,
                        style: const TextStyle(
                          color: AppColors.textDark,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        secondaryLine,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: error != null && !hasData
                              ? Colors.red
                              : AppColors.textGrey,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!isLoading)
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        badgeText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (!isLoading) const SizedBox(height: 14),
          if (!isLoading)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _AttendanceStatusChip(
                        label: 'Check In',
                        isLoading: attendanceLoading,
                        isDone: hasCheckIn,
                        time: checkInTime,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _AttendanceStatusChip(
                        label: 'Check Out',
                        isLoading: attendanceLoading,
                        isDone: hasCheckOut,
                        time: checkOutTime,
                      ),
                    ),
                  ],
                ),
                if (attendanceError != null && !attendanceLoading)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      attendanceError!,
                      style: const TextStyle(color: Colors.red, fontSize: 11),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _AttendanceStatusChip extends StatelessWidget {
  final String label;
  final bool isLoading;
  final bool isDone;
  final String? time;

  const _AttendanceStatusChip({
    required this.label,
    required this.isLoading,
    required this.isDone,
    this.time,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg = isDone
        ? Colors.green.withOpacity(0.12)
        : Colors.orange.withOpacity(0.12);
    final Color fg = isDone ? Colors.green.shade700 : Colors.orange.shade700;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: fg.withOpacity(0.3)),
      ),
      child: isLoading
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                ),
                const SizedBox(width: 8),
                Text(
                  '$label ...',
                  style: TextStyle(
                    fontSize: 12,
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: fg,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      isDone ? Icons.check_circle : Icons.access_time,
                      size: 14,
                      color: fg,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isDone ? (time ?? 'Terekam') : 'Belum tercatat',
                        style: TextStyle(
                          fontSize: 12,
                          color: fg.withOpacity(0.9),
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

// 6. Running Text (marquee)
class AnnouncementTicker extends StatefulWidget {
  final List<Map<String, dynamic>> items;

  const AnnouncementTicker({super.key, required this.items});

  @override
  State<AnnouncementTicker> createState() => _AnnouncementTickerState();
}

class _AnnouncementTickerState extends State<AnnouncementTicker> {
  final ScrollController _controller = ScrollController();
  String _mergedText = '';
  Color _barColor = AppColors.accentOrange;
  bool _shouldScroll = false;
  bool _isScrolling = false;

  @override
  void initState() {
    super.initState();
    _rebuildContent();
  }

  @override
  void didUpdateWidget(covariant AnnouncementTicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items) {
      _rebuildContent();
    }
  }

  Color _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return AppColors.accentOrange;
    var value = hex.replaceAll('#', '');
    if (value.length == 6) value = 'FF' + value;
    if (value.length == 8) {
      try {
        return Color(int.parse(value, radix: 16));
      } catch (_) {}
    }
    return AppColors.accentOrange;
  }

  void _rebuildContent() {
    final texts = widget.items
        .map((e) => (e['text'] ?? '').toString())
        .where((t) => t.trim().isNotEmpty)
        .toList();
    if (texts.isEmpty) {
      setState(() {
        _mergedText = '';
        _shouldScroll = false;
      });
      return;
    }
    _mergedText = texts.join('     �     ');
    _barColor = _parseColor(widget.items.first['color']?.toString());
    _shouldScroll = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _shouldScroll = true;
      _startScrollLoop();
    });
  }

  Future<void> _startScrollLoop() async {
    if (_isScrolling || !mounted || !_controller.hasClients) return;
    _isScrolling = true;
    try {
      while (mounted && _shouldScroll && _controller.hasClients) {
        final max = _controller.position.maxScrollExtent;
        final min = _controller.position.minScrollExtent;
        if (max <= min) break;
        _controller.jumpTo(max);
        await _controller.animateTo(
          min,
          duration: const Duration(seconds: 12),
          curve: Curves.linear,
        );
        if (!mounted || !_controller.hasClients || !_shouldScroll) break;
        await Future.delayed(const Duration(milliseconds: 300));
      }
    } catch (_) {
    } finally {
      _isScrolling = false;
    }
  }

  @override
  void dispose() {
    _shouldScroll = false;
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_mergedText.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      height: 40,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: _barColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _barColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            color: _barColor,
            height: double.infinity,
            alignment: Alignment.center,
            child: Image.asset(
              'assets/images/logo_toa.png',
              width: 22,
              height: 22,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.campaign_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          Expanded(
            child: ClipRect(
              child: ListView(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Center(
                      child: Text(
                        _mergedText,
                        style: const TextStyle(
                          color: AppColors.textDark,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.visible,
                        softWrap: false,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
