import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:ui'; // Diperlukan untuk ImageFilter (Glassmorphism)

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as latlng;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:intl/intl.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

// Pastikan import ini sesuai dengan struktur folder project Anda
// Jika file ini error, sesuaikan path import API service Anda
import 'package:gtime/services/api_service.dart';
import 'package:gtime/services/fake_gps_detector.dart';

// =============================================================================
// === 1. DATA MODELS ===
// =============================================================================

class LocationData {
  final int id;
  final String nama;
  final String nik;
  final String titik;

  LocationData({
    required this.id,
    required this.nama,
    required this.nik,
    required this.titik,
  });

  factory LocationData.fromJson(Map<String, dynamic> json) {
    return LocationData(
      id: json['id'] as int,
      nama: json['nama'] as String,
      nik: json['nik'] as String,
      titik: json['titik'] as String,
    );
  }
}

class AttendanceEntry {
  final String status;
  final String timestamp;
  final double? latitude;
  final double? longitude;
  final String deviceName;
  final String networkType;
  final List<String> macAddresses;

  AttendanceEntry({
    required this.status,
    required this.timestamp,
    this.latitude,
    this.longitude,
    this.deviceName = '',
    required this.networkType,
    required this.macAddresses,
  });

  Map<String, dynamic> toJson() => {
    'status': status,
    'timestamp': timestamp,
    'latitude': latitude,
    'longitude': longitude,
    'deviceName': deviceName,
    'networkType': networkType,
    'macAddresses': macAddresses,
  };

  factory AttendanceEntry.fromJson(Map<String, dynamic> j) => AttendanceEntry(
    status: j['status'] as String,
    timestamp: j['timestamp'] as String,
    latitude: j['latitude'] != null ? (j['latitude'] as num).toDouble() : null,
    longitude: j['longitude'] != null
        ? (j['longitude'] as num).toDouble()
        : null,
    deviceName: j['deviceName'] as String? ?? '',
    networkType: j['networkType'] as String? ?? 'unknown',
    macAddresses: List<String>.from(j['macAddresses'] ?? []),
  );
}

// =============================================================================
// === 2. APP COLORS & THEME (PROFESSIONAL PALETTE) ===
// =============================================================================

class AppColors {
  // Main Brand Colors
  static const Color primaryBlue = Color(0xFF0D47A1); // Corporate Blue
  static const Color accentOrange = Color(0xFFFF6F00); // Highlight

  // Professional Neutrals
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color surfaceGrey = Color(0xFFF8F9FA); // Background Panel
  static const Color textPrimary = Color(0xFF1A1C1E); // Main Text
  static const Color textSecondary = Color(0xFF6C757D); // Subtitles/Labels
  static const Color borderGrey = Color(0xFFE0E0E0); // Dividers

  // Gradients
  static const LinearGradient orangeGradient = LinearGradient(
    colors: [Color(0xFFFF8F00), Color(0xFFFF6F00)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient blueGradient = LinearGradient(
    colors: [Color(0xFF1565C0), Color(0xFF0D47A1)], // Deep Professional Blue
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF00C853), Color(0xFF1B5E20)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

// =============================================================================
// === 3. MAIN SCREEN ===
// =============================================================================

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  static const Duration _attendanceCooldown = Duration(minutes: 5);
  static const String _mapboxToken =
      'pk.eyJ1Ijoic3lzaW50ZWdpbmRleGltIiwiYSI6ImNtaXM4aG9lczA3emwzZW41ODlvdjlkM20ifQ.TKgZo484YkYm0kCX-7ycZQ';
  static const String _askedLocationPermissionKey =
      'asked_location_permission';

  // --- State Variables ---
  String _status = 'Not checked in';
  String _timestamp = '';
  List<AttendanceEntry> _history = [];

  Position? _currentPosition;
  late final StreamSubscription<Position> _positionStreamSub;
  Timer? _fakeGpsCheckTimer;
  mapbox.MapboxMap? _mapboxMap;
  mapbox.PolygonAnnotationManager? _polygonManager;
  mapbox.CircleAnnotationManager? _circleManager;
  bool _mapReady = false;
  bool _hasCenteredToUser = false;

  String _deviceName = '';
  String? _namaLengkap;
  String? _username;
  String? _currentNetworkType;
  List<String> _currentMacs = [];
  bool _isLoadingInfo = true;
  bool _isCheckingIn = false;
  bool _isLocationReady = false;
  bool _isMockLocation = false;

  List<LocationData> _availableLocations = [];
  LocationData? _selectedLocation;
  List<latlng.LatLng> _polygonPoints = [];
  bool _isInsideGeofence = false;
  bool _isLoadingLocations = true;
  String? _apiError;
  static const _locationsCacheKey = 'cached_locations';

  @override
  void initState() {
    super.initState();
    mapbox.MapboxOptions.setAccessToken(_mapboxToken);
    _initializeScreen();
    _startFakeGpsMonitoring();
  }

  Future<void> _initializeScreen() async {
    await _initPositionStream();
    setState(() => _isLoadingLocations = true);

    await Future.wait([
      _loadHistory(),
      _loadUserDetails(),
      _loadDeviceName(),
      _loadCachedLocations(),
    ]);
    setState(() => _isLoadingInfo = false);

    unawaited(_loadCurrentNetworkInfo());
    unawaited(_fetchAvailableLocations());
  }

  /// Monitor fake GPS setiap 3 detik
  void _startFakeGpsMonitoring() {
    _fakeGpsCheckTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (_currentPosition != null) {
        final result = await FakeGpsDetector.detectFakeGps(_currentPosition!);
        if (result.isFake && mounted) {
          setState(() => _isMockLocation = true);
          // Tampilkan notifikasi/snackbar
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: const [
                  Icon(Icons.warning_amber_rounded, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '⚠️ FAKE GPS TERDETEKSI! Matikan aplikasi fake GPS.',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.red.shade700,
              duration: const Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else if (!result.isFake && mounted) {
          setState(() => _isMockLocation = false);
        }
      }
    });
  }

  // ---------------------------------------------------------------------------
  // --- LOGIC SECTION (API, GPS, GEOLOCATION) ---
  // ---------------------------------------------------------------------------

  Future<void> _fetchAvailableLocations() async {
    if (!_isLocationReady) {
      setState(() {
        _isLoadingLocations = false;
        _apiError = 'Izin lokasi belum diaktifkan.';
      });
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) throw Exception('Token tidak ditemukan.');

      final username = prefs.getString('username');
      final buffer = StringBuffer('/locations');
      if (username != null && username.isNotEmpty) {
        buffer.write('?nik=$username');
      }
      final dynamic response =
          await ApiService().get(buffer.toString(), token: token);

      if (response is List) {
        final locations = response
            .map((json) => LocationData.fromJson(
                  json as Map<String, dynamic>,
                ))
            .toList();
        LocationData? matched;
        if (_selectedLocation != null) {
          for (final loc in locations) {
            if (loc.id == _selectedLocation!.id) {
              matched = loc;
              break;
            }
          }
        }

        try {
          await prefs.setString(_locationsCacheKey, jsonEncode(response));
        } catch (_) {}

        setState(() {
          _availableLocations = locations;
          _selectedLocation = matched;
          if (_selectedLocation != null) {
            _polygonPoints = _parsePolygon(_selectedLocation!.titik);
          }
          _isLoadingLocations = false;
          _apiError = null;
        });

        if (_selectedLocation == null && locations.isNotEmpty) {
          final auto = _autoSelectLocationForCurrentPosition(
            _currentPosition,
            locations,
          );
          if (auto != null) {
            _onLocationSelected(auto);
          } else if (locations.length == 1) {
            _onLocationSelected(locations.first);
          }
        }
        _syncMapOverlays();
      } else {
        throw Exception('Response lokasi tidak valid');
      }
    } catch (e) {
      log("Error locations: $e");
      setState(() {
        _isLoadingLocations = false;
        _apiError = e.toString();
      });
    }
  }

  LocationData? _autoSelectLocationForCurrentPosition(
    Position? position,
    List<LocationData> locations,
  ) {
    if (position == null || locations.isEmpty) return null;

    final currentPoint = latlng.LatLng(position.latitude, position.longitude);
    LocationData? bestLocation;
    double? bestDistance;

    for (final loc in locations) {
      final polygon = _parsePolygon(loc.titik);
      if (polygon.isEmpty) continue;

      if (_isPointInPolygon(currentPoint, polygon)) {
        return loc;
      }

      final center = _calculatePolygonCenter(polygon);
      final distance = latlng.Distance()(currentPoint, center);

      if (bestDistance == null || distance < bestDistance) {
        bestDistance = distance;
        bestLocation = loc;
      }
    }
    return bestLocation;
  }

  void _onLocationSelected(LocationData? location) {
    if (location == null) return;
    setState(() {
      _selectedLocation = location;
      _polygonPoints = _parsePolygon(location.titik);
      _checkIfInsideGeofence(_currentPosition);
    });
    _syncMapOverlays();
    if (_polygonPoints.isNotEmpty) {
      _moveCamera(_calculatePolygonCenter(_polygonPoints), zoom: 16.0);
    }
  }

  List<latlng.LatLng> _parsePolygon(String titikString) {
    final List<latlng.LatLng> points = [];
    final pairs = titikString.split('#');
    for (final pair in pairs) {
      final coords = pair.split(',');
      if (coords.length == 2) {
        try {
          points.add(
            latlng.LatLng(
              double.parse(coords[0].trim()),
              double.parse(coords[1].trim()),
            ),
          );
        } catch (_) {}
      }
    }
    return points;
  }

  latlng.LatLng _calculatePolygonCenter(List<latlng.LatLng> points) {
    if (points.isEmpty) return latlng.LatLng(0, 0);
    double lat = 0, lng = 0;
    for (final point in points) {
      lat += point.latitude;
      lng += point.longitude;
    }
    return latlng.LatLng(lat / points.length, lng / points.length);
  }

  void _checkIfInsideGeofence(Position? pos) {
    if (pos == null || _polygonPoints.isEmpty) {
      if (_isInsideGeofence) setState(() => _isInsideGeofence = false);
      return;
    }
    final point = latlng.LatLng(pos.latitude, pos.longitude);
    final bool isInside = _isPointInPolygon(point, _polygonPoints);
    if (isInside != _isInsideGeofence) {
      setState(() => _isInsideGeofence = isInside);
    }
  }

  bool _isPointInPolygon(latlng.LatLng point, List<latlng.LatLng> polygon) {
    bool isInside = false;
    int j = polygon.length - 1;
    for (int i = 0; i < polygon.length; j = i++) {
      if (((polygon[i].longitude > point.longitude) !=
              (polygon[j].longitude > point.longitude)) &&
          (point.latitude <
              (polygon[j].latitude - polygon[i].latitude) *
                      (point.longitude - polygon[i].longitude) /
                      (polygon[j].longitude - polygon[i].longitude) +
                  polygon[i].latitude)) {
        isInside = !isInside;
      }
    }
    return isInside;
  }

  Future<void> _loadCachedLocations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_locationsCacheKey);
      if (cached == null || cached.isEmpty) return;
      final List<dynamic> data = jsonDecode(cached);
      final locations = data
          .map((json) => LocationData.fromJson(json))
          .toList();
      LocationData? matched;
      if (_selectedLocation != null) {
        for (final loc in locations) {
          if (loc.id == _selectedLocation!.id) {
            matched = loc;
            break;
          }
        }
      }
      setState(() {
        _availableLocations = locations;
        _selectedLocation = matched;
        if (_selectedLocation != null) {
          _polygonPoints = _parsePolygon(_selectedLocation!.titik);
        }
        _isLoadingLocations = false;
      });
    } catch (_) {}
  }

  Future<void> _loadUserDetails() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _namaLengkap = prefs.getString('nama_lengkap') ?? 'N/A';
        _username = prefs.getString('username') ?? 'N/A';
      });
    } catch (_) {}
  }

  Future<void> _loadCurrentNetworkInfo() async {
    final networkType = await _getNetworkType();
    final macs = await _getMacAddresses();
    setState(() {
      _currentNetworkType = networkType;
      _currentMacs = macs;
    });
  }

  Future<void> _loadDeviceName() async {
    try {
      final plugin = DeviceInfoPlugin();
      String name = '';
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        name = '${info.manufacturer} ${info.model}';
      } else if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        name = info.name;
      } else {
        name = Platform.operatingSystem;
      }
      setState(() => _deviceName = name);
    } catch (_) {}
  }

  Future<void> _initPositionStream() async {
    final ready = await _ensureLocationReady(showDialog: true);
    if (!ready) {
      _positionStreamSub = const Stream<Position>.empty().listen((_) {});
      return;
    }

    try {
      final stream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      );
      _positionStreamSub = stream.listen((pos) async {
        setState(() {
          _currentPosition = pos;
          _isMockLocation = pos.isMocked == true;
        });
        if (!_hasCenteredToUser) {
          _moveCamera(latlng.LatLng(pos.latitude, pos.longitude), zoom: 18.0);
          _hasCenteredToUser = true;
        }
        if (_selectedLocation == null && _availableLocations.isNotEmpty) {
          final auto = _autoSelectLocationForCurrentPosition(
            pos,
            _availableLocations,
          );
          if (auto != null) {
            _onLocationSelected(auto);
          }
        }
        _syncMapOverlays();
      });
    } catch (_) {
      _positionStreamSub = const Stream<Position>.empty().listen((_) {});
    }
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('attendance_history');
    if (raw != null && raw.isNotEmpty) {
      final List decoded = jsonDecode(raw) as List;
      setState(() {
        _history = decoded.map((e) => AttendanceEntry.fromJson(e)).toList();
        if (_history.isNotEmpty) {
          final last = _history.last;
          _status = last.status;
          _timestamp = last.timestamp;
        }
      });
    }
  }

  Future<void> _saveEntry(AttendanceEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    _history.add(entry);
    final encoded = jsonEncode(_history.map((e) => e.toJson()).toList());
    await prefs.setString('attendance_history', encoded);
    setState(() {
      _status = entry.status;
      _timestamp = entry.timestamp;
    });
  }

  Future<String> _getNetworkType() async {
    try {
      final connList = await Connectivity().checkConnectivity();
      if (connList.isEmpty || connList.contains(ConnectivityResult.none)) {
        return 'Offline';
      }
      if (connList.contains(ConnectivityResult.wifi)) return 'Wifi';
      if (connList.contains(ConnectivityResult.mobile)) return 'Mobile Data';
      return 'Other';
    } catch (_) {
      return 'unknown';
    }
  }

  Future<List<String>> _getMacAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLinkLocal: false,
        includeLoopback: false,
      );
      final macs = <String>[];
      for (final i in interfaces) {
        final addrs = i.addresses.map((a) => a.address).join(',');
        macs.add('${i.name}: ${addrs.isEmpty ? 'N/A' : addrs}');
      }
      return macs;
    } catch (_) {
      return [];
    }
  }

  String _extractIp(List<String> addrs) {
    final text = addrs.join(' ');
    final match = RegExp(r'\b\d{1,3}(?:\.\d{1,3}){3}\b').firstMatch(text);
    return match?.group(0) ?? 'N/A';
  }

  Future<bool> _ensureLocationReady({bool showDialog = false}) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted && showDialog) {
        _showErrorDialog(
          'Lokasi Wajib Aktif',
          'Aktifkan layanan lokasi/GPS untuk bisa absen.',
          actionLabel: 'Buka Pengaturan',
          onAction: () {
            Geolocator.openLocationSettings();
          },
        );
      }
      setState(() => _isLocationReady = false);
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      final prefs = await SharedPreferences.getInstance();
      final askedBefore = prefs.getBool(_askedLocationPermissionKey) ?? false;
      if (!askedBefore) {
        permission = await Geolocator.requestPermission();
        await prefs.setBool(_askedLocationPermissionKey, true);
      }
      if (permission == LocationPermission.denied) {
        if (mounted && showDialog) {
          _showErrorDialog(
            'Izin Lokasi Ditolak',
            'Berikan izin lokasi agar aplikasi bisa mendeteksi posisi Anda.',
            actionLabel: 'Buka Pengaturan',
            onAction: () {
              Geolocator.openAppSettings();
            },
          );
        }
        setState(() => _isLocationReady = false);
        return false;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      if (mounted && showDialog) {
        _showErrorDialog(
          'Izin Lokasi Permanen Ditolak',
          'Buka pengaturan aplikasi dan izinkan lokasi untuk melanjutkan.',
          actionLabel: 'Buka Pengaturan',
          onAction: () {
            Geolocator.openAppSettings();
          },
        );
      }
      setState(() => _isLocationReady = false);
      return false;
    }

    setState(() => _isLocationReady = true);
    return true;
  }

  Future<Position?> _getLocation() async {
    final ready = await _ensureLocationReady(showDialog: true);
    if (!ready) return null;
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      // Deteksi Fake GPS - tambahan security
      if (position.isMocked) {
        if (mounted) {
          _showErrorDialog(
            'Fake GPS Terdeteksi',
            'Matikan aplikasi Fake GPS dan gunakan lokasi asli.',
          );
        }
        setState(() => _isMockLocation = true);
        return null;
      }
      
      // Deteksi tambahan menggunakan FakeGpsDetector
      final detectionResult = await FakeGpsDetector.detectFakeGps(position);
      if (detectionResult.isFake) {
        if (mounted) {
          _showErrorDialog(
            'Lokasi Palsu Terdeteksi',
            detectionResult.message,
          );
        }
        setState(() => _isMockLocation = true);
        return null;
      }
      
      setState(() => _isMockLocation = false);
      return position;
    } catch (_) {
      if (mounted) {
        _showErrorDialog(
          'Lokasi Tidak Terbaca',
          'Pastikan GPS aktif dan berada di area terbuka.',
        );
      }
      return null;
    }
  }

  Future<void> _check(String status) async {
    if (_isCheckingIn) return;
    if (_isCooldownActive()) return;
    if (_isMockLocation) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Lokasi terdeteksi palsu (mock). Matikan fake GPS terlebih dahulu.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    setState(() => _isCheckingIn = true);

    try {
      final position = await _getLocation();
      if (position == null) {
        setState(() => _isCheckingIn = false);
        return;
      }
      if (position.isMocked) {
        if (mounted) {
          _showErrorDialog('Fake GPS Terdeteksi', 'Matikan aplikasi Fake GPS.');
        }
        setState(() => _isCheckingIn = false);
        return;
      }

      final now = DateTime.now().toIso8601String();
      final entry = AttendanceEntry(
        status: status,
        timestamp: now,
        latitude: position.latitude,
        longitude: position.longitude,
        deviceName: _deviceName,
        networkType: await _getNetworkType(),
        macAddresses: await _getMacAddresses(),
      );

      final bool? confirmed = await _showConfirmationDialog(entry);

      if (confirmed == true) {
        try {
          final prefs = await SharedPreferences.getInstance();
          final token = prefs.getString('auth_token');
          final nik = prefs.getString('username');
          if (token == null || nik == null) throw Exception('Auth gagal');

          final Map<String, dynamic> data = {
            'nik': nik,
            'status': entry.status,
            'timestamp': entry.timestamp,
            'lokasiId': _selectedLocation?.id,
            'latitude': entry.latitude,
            'longitude': entry.longitude,
            'deviceName': entry.deviceName,
            'networkType': entry.networkType,
            'macAddresses': entry.macAddresses,
            'isMocked': false,
          };

          await ApiService().post(
            '/attendance',
            body: data,
            token: token,
          );
          await _saveEntry(entry);
          await _showThanksAndBack();
        } catch (e) {
          _showErrorDialog("Error", "Koneksi gagal: $e");
        }
      }
    } catch (e) {
      if (mounted) _showErrorDialog('Error', '$e');
    } finally {
      setState(() => _isCheckingIn = false);
    }
  }

  bool _isCooldownActive() {
    if (_history.isEmpty) return false;
    final last = DateTime.tryParse(_history.last.timestamp);
    if (last == null) return false;
    final diff = DateTime.now().difference(last);
    if (diff >= _attendanceCooldown) return false;

    final remaining = _attendanceCooldown - diff;
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    final timeText =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Tunggu $timeText sebelum absen lagi.',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.orange.shade700,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return true;
  }

  Future<bool?> _showConfirmationDialog(AttendanceEntry entry) async {
    if (!mounted) return false;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Konfirmasi ${entry.status}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.primaryBlue,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Pastikan data berikut benar:"),
            const SizedBox(height: 10),
            // Reusing the cleaner row style manually here if needed
            Row(
              children: [
                const Icon(
                  Icons.location_on_rounded,
                  color: AppColors.primaryBlue,
                ),
                const SizedBox(width: 8),
                Text(
                  "${entry.latitude?.toStringAsFixed(5)}, ${entry.longitude?.toStringAsFixed(5)}",
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text('Batal', style: TextStyle(color: Colors.grey)),
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              shape: const StadiumBorder(),
            ),
            child: const Text('Ya, Lanjutkan'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(
    String title,
    String content, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(color: Colors.redAccent)),
        content: Text(content),
        actions: [
          if (actionLabel != null && onAction != null)
            TextButton(
              child: Text(actionLabel),
              onPressed: () {
                Navigator.of(ctx).pop();
                onAction();
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

  Future<void> _showThanksAndBack() async {
    if (!mounted) return;

    await showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: "Success",
      barrierColor: Colors.black.withOpacity(0.5),
      transitionDuration: const Duration(milliseconds: 500),
      pageBuilder: (context, anim1, anim2) {
        return _PremiumSuccessDialog(
          onClose: () {
            Navigator.of(context).pop();
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim1, curve: Curves.elasticOut),
          child: child,
        );
      },
    );
  }

  Future<void> _onMapCreated(mapbox.MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    // Gunakan style Mapbox yang sesuai
    await _mapboxMap!.style.setStyleURI(mapbox.MapboxStyles.MAPBOX_STREETS);

    // Konfigurasi Location Component (Pulsing Dot)
    await _mapboxMap!.location.updateSettings(
      mapbox.LocationComponentSettings(
        enabled: true,
        pulsingEnabled: true,
        pulsingColor: AppColors.primaryBlue.value, // Blue Pulse
        pulsingMaxRadius: 20.0,
      ),
    );

    _polygonManager ??= await _mapboxMap!.annotations
        .createPolygonAnnotationManager();
    _circleManager ??= await _mapboxMap!.annotations
        .createCircleAnnotationManager();
    setState(() => _mapReady = true);
    _syncMapOverlays();
  }

  Future<void> _syncMapOverlays() async {
    if (!_mapReady || _mapboxMap == null) return;

    if (_polygonManager != null) {
      await _polygonManager!.deleteAll();
      if (_polygonPoints.isNotEmpty) {
        final coords = _polygonPoints
            .map((p) => mapbox.Position(p.longitude, p.latitude))
            .toList();
        // Area Kantor Overlay
        await _polygonManager!.create(
          mapbox.PolygonAnnotationOptions(
            geometry: mapbox.Polygon(coordinates: [coords]),
            fillColor: AppColors.primaryBlue.value,
            fillOpacity: 0.15,
            fillOutlineColor: AppColors.primaryBlue.value,
          ),
        );
      }
    }
  }

  Future<void> _moveCamera(latlng.LatLng target, {double zoom = 16}) async {
    if (_mapboxMap == null) return;
    try {
      await _mapboxMap!.flyTo(
        mapbox.CameraOptions(
          center: mapbox.Point(
            coordinates: mapbox.Position(target.longitude, target.latitude),
          ),
          zoom: zoom,
        ),
        mapbox.MapAnimationOptions(duration: 500, startDelay: 0),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    try {
      _positionStreamSub.cancel();
    } catch (_) {}
    _fakeGpsCheckTimer?.cancel();
    super.dispose();
  }

  String _formatTimestamp(String isoTimestamp) {
    if (isoTimestamp.isEmpty) return 'Belum Absen Hari Ini';
    try {
      final DateTime dt = DateTime.parse(isoTimestamp);
      return DateFormat('dd MMMM yyyy • HH:mm').format(dt);
    } catch (e) {
      return isoTimestamp;
    }
  }

  // ---------------------------------------------------------------------------
  // --- UI & WIDGET BUILDER (PROFESSIONAL & CLEAN) ---
  // ---------------------------------------------------------------------------

  Widget _buildInfoRow(IconData icon, String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primaryBlue, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationDropdown() {
    if (_isLoadingLocations) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceGrey,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primaryBlue,
            ),
          ),
        ),
      );
    }

    if (_apiError != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          "Error: $_apiError",
          style: TextStyle(color: Colors.red.shade700, fontSize: 12),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            "LOKASI KERJA",
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary,
              letterSpacing: 1.0,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surfaceGrey,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderGrey),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<LocationData>(
              isExpanded: true,
              hint: Row(
                children: const [
                  Icon(
                    Icons.apartment_rounded, // Simbol profesional
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                  SizedBox(width: 12),
                  Text(
                    "Pilih Lokasi Absen",
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
              value: _selectedLocation,
              icon: const Icon(
                Icons.expand_more_rounded,
                color: AppColors.primaryBlue,
              ),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              items: _availableLocations.map((loc) {
                return DropdownMenuItem(
                  value: loc,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.business_rounded,
                        size: 20,
                        color: AppColors.primaryBlue,
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(loc.nama)),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (val) => _onLocationSelected(val),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAttendanceButtons() {
    if (_isCheckingIn) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(50),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const CircularProgressIndicator(color: AppColors.primaryBlue),
        ),
      );
    }

    // STATE 1: Lokasi Belum Dipilih
    if (_selectedLocation == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orange.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.touch_app_rounded, color: Colors.orange.shade800),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "Silakan pilih lokasi kantor di atas untuk melanjutkan.",
                style: TextStyle(
                  color: Colors.orange.shade900,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // STATE 2: Diluar Radius (Geofence Alert)
    if (!_isInsideGeofence) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2), // Merah sangat muda
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.red.shade100),
              ),
              child: Icon(
                Icons.share_location_rounded,
                color: Colors.red.shade400,
                size: 28,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "Anda berada di luar area kantor",
              style: TextStyle(
                color: Colors.red.shade800,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Silakan masuk ke area radius untuk absen.",
              style: TextStyle(color: Colors.red.shade600, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // STATE 3: Siap Absen (Tombol Clean & Professional)
    return Row(
      children: [
        Expanded(
          child: _BouncingButton(
            onTap: () => _check('IN'),
            gradient: const LinearGradient(
              colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)], // Hijau Corporate
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shadowColor: const Color(0xFF1B5E20),
            label: 'CLOCK IN',
            icon: Icons.login_rounded,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _BouncingButton(
            onTap: () => _check('OUT'),
            gradient: const LinearGradient(
              colors: [Color(0xFFC62828), Color(0xFFB71C1C)], // Merah Corporate
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shadowColor: const Color(0xFFB71C1C),
            label: 'CLOCK OUT',
            icon: Icons.logout_rounded,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Attendance',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        backgroundColor: Colors.white.withOpacity(0.7),
        elevation: 0,
        centerTitle: true,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const BackButton(color: AppColors.textPrimary),
        ),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
      ),
      body: Stack(
        children: [
          if (_isMockLocation)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                color: Colors.redAccent.withOpacity(0.9),
                child: Row(
                  children: const [
                    Icon(Icons.warning_amber_rounded, color: Colors.white),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Fake GPS terdeteksi. Matikan aplikasi lokasi palsu untuk melanjutkan absensi.',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // LAYER 1: MAP
          mapbox.MapWidget(
            cameraOptions: mapbox.CameraOptions(
              center: mapbox.Point(
                coordinates: mapbox.Position(
                  _currentPosition?.longitude ?? 106.8,
                  _currentPosition?.latitude ?? -6.2,
                ),
              ),
              zoom: 16.0,
            ),
            styleUri: mapbox.MapboxStyles.MAPBOX_STREETS,
            onMapCreated: _onMapCreated,
          ),

          // LAYER 2: RECENTER BUTTON (Styled)
          Positioned(
            top: 110,
            right: 16,
            child: FloatingActionButton(
              heroTag: "recenter",
              mini: true,
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primaryBlue,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ), // Lebih kotak
              onPressed: () {
                if (_currentPosition != null) {
                  _moveCamera(
                    latlng.LatLng(
                      _currentPosition!.latitude,
                      _currentPosition!.longitude,
                    ),
                    zoom: 18.0,
                  );
                }
              },
              child: const Icon(Icons.my_location_rounded),
            ),
          ),

          // LAYER 3: BOTTOM SHEET (Clean Glassmorphism)
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.90), // Lebih solid
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: Colors.white),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Handle Bar
                        Center(
                          child: Container(
                            margin: const EdgeInsets.only(top: 12),
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),

                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // 1. DROPDOWN LOKASI
                              _buildLocationDropdown(),
                              const SizedBox(height: 20),

                              // 2. STATUS CARD (Modern)
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  gradient: AppColors.blueGradient,
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primaryBlue.withOpacity(
                                        0.3,
                                      ),
                                      blurRadius: 15,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Icon(
                                        _status == 'IN'
                                            ? Icons.login_rounded
                                            : Icons.logout_rounded,
                                        color: Colors.white,
                                        size: 28,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _status == 'IN'
                                              ? "SUDAH ABSEN MASUK"
                                              : (_status == 'OUT'
                                                    ? "SUDAH ABSEN PULANG"
                                                    : "BELUM ABSEN"),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _formatTimestamp(_timestamp),
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(
                                              0.9,
                                            ),
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 20),

                              // 3. COLLAPSIBLE DETAIL INFO (Clean)
                              Theme(
                                data: Theme.of(
                                  context,
                                ).copyWith(dividerColor: Colors.transparent),
                                child: ExpansionTile(
                                  tilePadding: EdgeInsets.zero,
                                  childrenPadding: const EdgeInsets.only(
                                    bottom: 10,
                                  ),
                                  title: Row(
                                    children: const [
                                      Icon(
                                        Icons.info_outline_rounded,
                                        size: 18,
                                        color: AppColors.textSecondary,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        "Informasi Perangkat",
                                        style: TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(20),
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceGrey,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: AppColors.borderGrey,
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          _buildInfoRow(
                                            Icons.badge_rounded,
                                            "Nama Karyawan",
                                            _namaLengkap ?? '-',
                                          ),
                                          _buildInfoRow(
                                            Icons.smartphone_rounded,
                                            "Model Perangkat",
                                            _deviceName,
                                          ),
                                          _buildInfoRow(
                                            Icons.hub_rounded,
                                            "Koneksi Jaringan",
                                            _currentNetworkType ?? '-',
                                          ),
                                          Container(
                                            height: 1,
                                            color: AppColors.borderGrey,
                                          ),
                                          const SizedBox(height: 16),
                                          _buildInfoRow(
                                            Icons.dns_rounded,
                                            "IP Address",
                                            _extractIp(_currentMacs),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 10),

                              // 4. ACTION BUTTONS
                              _buildAttendanceButtons(),
                            ],
                          ),
                        ),
                      ],
                    ),
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

// =============================================================================
// === 4. CUSTOM WIDGETS ===
// =============================================================================

class _BouncingButton extends StatefulWidget {
  final VoidCallback onTap;
  final LinearGradient gradient;
  final Color shadowColor;
  final String label;
  final IconData icon;

  const _BouncingButton({
    required this.onTap,
    required this.gradient,
    required this.shadowColor,
    required this.label,
    required this.icon,
  });

  @override
  State<_BouncingButton> createState() => _BouncingButtonState();
}

class _BouncingButtonState extends State<_BouncingButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) => _controller.forward();
  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
    widget.onTap();
  }

  void _onTapCancel() => _controller.reverse();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) => Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            height: 55,
            decoration: BoxDecoration(
              gradient: widget.gradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: widget.shadowColor.withOpacity(0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  widget.label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.0,
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

class _PremiumSuccessDialog extends StatefulWidget {
  final VoidCallback onClose;
  const _PremiumSuccessDialog({required this.onClose});

  @override
  State<_PremiumSuccessDialog> createState() => _PremiumSuccessDialogState();
}

class _PremiumSuccessDialogState extends State<_PremiumSuccessDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _scaleAnim = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Card Background
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Attendance Recorded",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Data kehadiran Anda telah berhasil disimpan di server.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B5E20),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    onPressed: widget.onClose,
                    child: const Text(
                      "SELESAI",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Animated Icon on Top
          Positioned(
            top: -40,
            child: ScaleTransition(
              scale: _scaleAnim,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  gradient: AppColors.successGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green,
                      blurRadius: 15,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
