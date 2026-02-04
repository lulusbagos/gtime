
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:gtime/services/api_service.dart';

class BargeMovementReportScreen extends StatefulWidget {
  const BargeMovementReportScreen({super.key});

  @override
  State<BargeMovementReportScreen> createState() =>
      _BargeMovementReportScreenState();
}

class _BargeMovementReportScreenState extends State<BargeMovementReportScreen> {
  static const String _entriesKey = 'barge_movement_reports';
  static const String _masterCacheKey = 'barge_movement_master_cache';
  static const String _askedLocationPermissionKey =
      'asked_location_permission';

  final DateFormat _dateFormat = DateFormat('EEEE, dd MMM yyyy');
  final DateFormat _timeFormat = DateFormat('HH:mm');

  String _kapalName = '';

  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();

  bool _isOnline = true;
  bool _isLocating = false;
  Position? _position;
  String? _locationError;

  bool _isLoadingMaster = false;
  String? _masterError;
  List<MovementMaster> _masters = [];
  MovementMaster? _selectedMaster;
  final TextEditingController _masterSearchController = TextEditingController();
  final TextEditingController _keteranganController = TextEditingController();
  final FocusNode _keteranganFocusNode = FocusNode();

  bool _isSaving = false;
  String? _formError;

  String _nik = '-';
  String _nama = '-';
  String _jabatan = '-';

  List<BargeMovementEntry> _entries = [];
  String? _editingId;

  _FilterMode _filterMode = _FilterMode.daily;
  DateTime _filterDate = DateTime.now();
  TimeOfDay _filterHour = TimeOfDay.now();

  @override
  void initState() {
    super.initState();
    _startClock();
    _initializeData();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _masterSearchController.dispose();
    _keteranganController.dispose();
    _keteranganFocusNode.dispose();
    super.dispose();
  }

  void _startClock() {
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  Future<void> _initializeData() async {
    await _loadUser();
    await _loadEntries();
    await _refreshConnectivity();
    if (_isOnline) {
      await _loadRemoteReports();
    }
    await _loadMasterMovements();
    await _resolveLocation();
    _resetReportDateTime();
  }

  Future<void> _refreshConnectivity() async {
    final connectivity = await Connectivity().checkConnectivity();
    if (!mounted) return;
    setState(() => _isOnline = connectivity != ConnectivityResult.none);
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    final nama = prefs.getString('nama_lengkap') ?? '-';
    final nik = prefs.getString('username') ?? '-';
    final jabatan = prefs.getString('posisi') ?? '-';
    final kapal =
        prefs.getString('kapal') ?? prefs.getString('nama_kapal') ?? '';
    if (!mounted) return;
    setState(() {
      _nama = nama;
      _nik = nik;
      _jabatan = jabatan;
      _kapalName = kapal.trim();
    });
  }

  Future<void> _loadEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_entriesKey);
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final List data = jsonDecode(raw) as List;
      final items = data
          .whereType<Map>()
          .map((e) => BargeMovementEntry.fromJson(e.cast<String, dynamic>()))
          .toList();
      if (!mounted) return;
      setState(() {
        _entries = items..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      });
    } catch (_) {}
  }

  Future<void> _saveEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _entries.map((e) => e.toJson()).toList();
    await prefs.setString(_entriesKey, jsonEncode(data));
  }
  Future<void> _loadMasterMovements() async {
    setState(() {
      _isLoadingMaster = true;
      _masterError = null;
    });

    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_masterCacheKey);
    if (cached != null && cached.isNotEmpty) {
      try {
        final List data = jsonDecode(cached) as List;
        _masters = data
            .whereType<Map>()
            .map((e) => MovementMaster.fromJson(e.cast<String, dynamic>()))
            .toList();
      } catch (_) {}
    }

    try {
      final token = prefs.getString('auth_token');
      final response = await ApiService().get(
        '/api/barge-movement/master',
        token: token,
      );
      final list = _extractList(response);
      if (list.isNotEmpty) {
        final masters = list
            .map(
              (item) => MovementMaster.fromJson(
                item.cast<String, dynamic>(),
              ),
            )
            .toList();
        _masters = masters;
        await prefs.setString(
          _masterCacheKey,
          jsonEncode(_masters.map((e) => e.toJson()).toList()),
        );
      }
    } catch (e) {
      _masterError = 'Gagal memuat master movement: $e';
    }

    if (!mounted) return;
    setState(() {
      _isLoadingMaster = false;
      if (_masters.isEmpty && _masterError == null) {
        _masterError = 'Master movement belum tersedia.';
      }
      if (_selectedMaster == null && _masters.isNotEmpty) {
        _selectedMaster = _masters.first;
      }
    });
  }

  List<Map<String, dynamic>> _extractList(dynamic response) {
    if (response is List) {
      return response.whereType<Map>().cast<Map<String, dynamic>>().toList();
    }
    if (response is Map && response['data'] is List) {
      return (response['data'] as List)
          .whereType<Map>()
          .cast<Map<String, dynamic>>()
          .toList();
    }
    return [];
  }

  Future<void> _loadRemoteReports() async {
    final kapal = _kapalName.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) return;
      final endpoint = kapal.isEmpty
          ? '/api/barge-movement/reports?limit=200'
          : '/api/barge-movement/reports?nama_kapal=${Uri.encodeQueryComponent(kapal)}&limit=200';
      final response = await ApiService().get(endpoint, token: token);
      final list = _extractList(response);
      if (list.isEmpty) return;

      final remoteEntries = list
          .map((item) => _fromServer(item.cast<String, dynamic>()))
          .toList();
      if (remoteEntries.isEmpty) return;

      final merged = List<BargeMovementEntry>.from(_entries);
      for (final remote in remoteEntries) {
        final index =
            merged.indexWhere((e) => e.serverId == remote.serverId);
        if (index >= 0) {
          merged[index] = remote.copyWith(
            synced: true,
            serverId: remote.serverId,
          );
        } else {
          merged.insert(0, remote.copyWith(synced: true));
        }
      }
      _entries = merged;
      await _saveEntries();
    } catch (_) {}
  }

  BargeMovementEntry _fromServer(Map<String, dynamic> json) {
    final serverId = (json['id'] ?? '').toString();
    final timestamp = _parseServerTimestamp(
      json['tanggal']?.toString(),
      json['jam']?.toString(),
      json['created_at']?.toString(),
    );
    return BargeMovementEntry(
      id: 'srv_$serverId',
      timestamp: timestamp,
      movementId: (json['movement_id'] ?? '').toString(),
      movementName: (json['movement_name'] ?? '').toString(),
      latitude: _parseDouble(json['latitude']),
      longitude: _parseDouble(json['longitude']),
      nik: (json['nik'] ?? '-').toString(),
      nama: (json['nama'] ?? '-').toString(),
      jabatan: (json['jabatan'] ?? '-').toString(),
      namaKapal: (json['nama_kapal'] ?? '-').toString(),
      keterangan: (json['keterangan'] ?? '').toString(),
      synced: true,
      serverId: serverId.isEmpty ? null : serverId,
    );
  }

  DateTime _parseServerTimestamp(String? tanggal, String? jam, String? createdAt) {
    if (tanggal != null && jam != null) {
      final parsed = DateTime.tryParse('${tanggal.trim()} ${jam.trim()}');
      if (parsed != null) return parsed.toLocal();
    }
    final created = createdAt != null ? DateTime.tryParse(createdAt) : null;
    if (created != null) return created.toLocal();
    return DateTime.now();
  }

  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return double.tryParse(text.replaceAll(',', '.'));
  }

  Future<List<BargeMovementEntry>> _fetchMapEntries(DateTime date) async {
    await _refreshConnectivity();
    if (!_isOnline) return const [];
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) return const [];
      final kapal = _kapalName.trim();
      final dateParam = DateFormat('yyyy-MM-dd').format(date);
      final endpoint = kapal.isEmpty
          ? '/api/barge-movement/reports?tanggal=$dateParam&limit=500'
          : '/api/barge-movement/reports?nama_kapal=${Uri.encodeQueryComponent(kapal)}&tanggal=$dateParam&limit=500';
      final response = await ApiService().get(endpoint, token: token);
      final list = _extractList(response);
      if (list.isEmpty) return const [];
      return list
          .map((item) => _fromServer(item.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  String _normalizeKapal(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? '-' : trimmed.toUpperCase();
  }

  List<LatLng> _distinctPoints(List<LatLng> points) {
    if (points.length <= 1) return points;
    final unique = <LatLng>[];
    for (final point in points) {
      if (unique.isEmpty) {
        unique.add(point);
        continue;
      }
      final last = unique.last;
      if (last.latitude != point.latitude || last.longitude != point.longitude) {
        unique.add(point);
      }
    }
    return unique;
  }

  Future<void> _resolveLocation() async {
    if (!mounted) return;
    setState(() {
      _isLocating = true;
      _locationError = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          _showLocationSettingsDialog(
            'Lokasi Wajib Aktif',
            'Aktifkan layanan lokasi/GPS agar posisi bisa dibaca.',
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
            'Berikan izin lokasi agar posisi bisa dibaca.',
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
            desiredAccuracy: LocationAccuracy.best,
            timeLimit: const Duration(seconds: 10),
          );

      if (!mounted) return;
      setState(() {
        _position = pos;
        _isLocating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLocating = false;
        _locationError = e.toString();
      });
    }
  }
  Future<void> _submitReport() async {
    if (_isSaving) return;
    setState(() => _formError = null);

    final kapal = _kapalName.trim();
    if (kapal.isEmpty) {
      setState(() => _formError = 'Nama kapal tidak tersedia di profil.');
      return;
    }
    if (_selectedMaster == null) {
      setState(() => _formError = 'Pilih master movement terlebih dahulu.');
      return;
    }

    setState(() => _isSaving = true);
    await _refreshConnectivity();

    final timestamp = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    final keterangan = _keteranganController.text.trim();
    final payload = BargeMovementEntry(
      id: _editingId ?? _generateId(),
      timestamp: timestamp,
      movementId: _selectedMaster!.id,
      movementName: _selectedMaster!.name,
      latitude: _position?.latitude,
      longitude: _position?.longitude,
      nik: _nik,
      nama: _nama,
      jabatan: _jabatan,
      namaKapal: kapal,
      keterangan: keterangan,
      synced: false,
      serverId: _findEntry(_editingId ?? '')?.serverId,
    );

    final entry = payload.copyWith(
      timestamp: payload.timestamp ?? _now,
    );

    final updatedList = List<BargeMovementEntry>.from(_entries);
    final existingIndex = updatedList.indexWhere((e) => e.id == entry.id);
    if (existingIndex >= 0) {
      updatedList[existingIndex] = entry;
    } else {
      updatedList.insert(0, entry);
    }

    bool synced = false;
    String? serverId;
    if (_isOnline) {
      final result = await _syncEntry(entry);
      synced = result.synced;
      serverId = result.serverId;
    }

    final savedEntry = entry.copyWith(synced: synced, serverId: serverId);
    if (existingIndex >= 0) {
      updatedList[existingIndex] = savedEntry;
    } else {
      updatedList[0] = savedEntry;
    }

    _entries = updatedList;
    await _saveEntries();
    if (!mounted) return;
    setState(() {
      _isSaving = false;
      _editingId = null;
      _resetReportDateTime();
    });

    _showMessage(
      synced
          ? 'Report berhasil dikirim.'
          : 'Report tersimpan offline.',
      isSuccess: synced,
    );
  }

  Future<_SyncResult> _syncEntry(BargeMovementEntry entry) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) throw ApiException('Sesi habis, silakan login ulang');

      final payload = {
        'nik': entry.nik,
        'nama': entry.nama,
        'jabatan': entry.jabatan,
        'nama_kapal': entry.namaKapal,
        'movement_id': entry.movementId,
        'movement_name': entry.movementName,
        'tanggal': DateFormat('yyyy-MM-dd').format(entry.timestamp),
        'jam': DateFormat('HH:mm:ss').format(entry.timestamp),
        'latitude': entry.latitude,
        'longitude': entry.longitude,
        'keterangan': entry.keterangan,
      };

      dynamic response;
      if (entry.serverId != null && entry.serverId!.isNotEmpty) {
        response = await ApiService().put(
          '/api/barge-movement/reports/${entry.serverId}',
          body: payload,
          token: token,
        );
      } else {
        response = await ApiService().post(
          '/api/barge-movement/reports',
          body: payload,
          token: token,
        );
      }

      String? serverId;
      if (response is Map) {
        final id = response['id'] ?? response['data']?['id'];
        if (id != null) {
          serverId = id.toString();
        }
      }
      return _SyncResult(synced: true, serverId: serverId);
    } catch (_) {
      return const _SyncResult(synced: false, serverId: null);
    }
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

  String _generateId() =>
      DateTime.now().millisecondsSinceEpoch.toString();

  BargeMovementEntry? _findEntry(String id) {
    if (id.isEmpty) return null;
    return _entries.firstWhere(
      (e) => e.id == id,
      orElse: () => BargeMovementEntry.empty(),
    );
  }

  void _showMessage(String message, {bool isSuccess = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess ? Colors.green : Colors.orange.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  List<BargeMovementEntry> _filteredEntries() {
    final entries = _applyKapalFilter(List<BargeMovementEntry>.from(_entries));
    if (entries.isEmpty) return entries;
    if (_filterMode == _FilterMode.daily) {
      return entries.where((e) => _isSameDay(e.timestamp, _filterDate)).toList();
    }
    if (_filterMode == _FilterMode.hourly) {
      return entries
          .where(
            (e) =>
                _isSameDay(e.timestamp, _filterDate) &&
                e.timestamp.hour == _filterHour.hour,
          )
          .toList();
    }
    return entries
        .where(
          (e) =>
              e.timestamp.year == _filterDate.year &&
              e.timestamp.month == _filterDate.month,
        )
        .toList();
  }

  List<BargeMovementEntry> _applyKapalFilter(
    List<BargeMovementEntry> entries,
  ) {
    final kapal = _kapalName.trim();
    if (kapal.isEmpty) return entries;
    return entries.where((e) => e.namaKapal == kapal).toList();
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _pickFilterDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _filterDate = picked);
    }
  }

  Future<void> _pickReportDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickReportTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  void _resetReportDateTime() {
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _selectedTime = TimeOfDay(hour: now.hour, minute: now.minute);
    _keteranganController.clear();
  }

  Future<void> _pickFilterHour() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _filterHour,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _filterHour = picked);
    }
  }

  Future<void> _startEdit(BargeMovementEntry entry) async {
    setState(() {
      _editingId = entry.id;
      _selectedDate =
          DateTime(entry.timestamp.year, entry.timestamp.month, entry.timestamp.day);
      _selectedTime = TimeOfDay(
        hour: entry.timestamp.hour,
        minute: entry.timestamp.minute,
      );
      _selectedMaster = _masters.firstWhere(
        (m) => m.id == entry.movementId,
        orElse: () => _masters.isNotEmpty ? _masters.first : entry.toMaster(),
      );
      _keteranganController.text = entry.keterangan;
    });
  }

  Future<void> _deleteEntry(BargeMovementEntry entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus report?'),
        content: const Text(
          'Data yang dihapus tidak bisa dikembalikan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() {
      _entries.removeWhere((e) => e.id == entry.id);
    });
    await _saveEntries();
  }

  Future<void> _syncPending() async {
    await _refreshConnectivity();
    if (!_isOnline) {
      _showMessage('Tidak ada koneksi internet.');
      return;
    }
    final pending = _entries.where((e) => !e.synced).toList();
    if (pending.isEmpty) return;
    for (final entry in pending) {
      final result = await _syncEntry(entry);
      if (result.synced) {
        final index = _entries.indexWhere((e) => e.id == entry.id);
        if (index >= 0) {
          _entries[index] =
              entry.copyWith(synced: true, serverId: result.serverId);
        }
      }
    }
    await _saveEntries();
    if (!mounted) return;
    setState(() {});
  }
  @override
  Widget build(BuildContext context) {
    final filteredEntries = _filteredEntries();
    final entriesWithLocation = _applyKapalFilter(_entries)
        .where((e) => e.latitude != null && e.longitude != null)
        .toList();
    final hasPending = _entries.any((e) => !e.synced);
    final todayEntries = _applyKapalFilter(_entries)
        .where((e) => _isSameDay(e.timestamp, DateTime.now()))
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        title: const Text('Barge Movement Report'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        actions: [
          IconButton(
            onPressed: _refreshConnectivity,
            icon: Icon(
              _isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _refreshConnectivity();
          if (_isOnline) {
            await _loadRemoteReports();
          }
          await _loadMasterMovements();
          await _resolveLocation();
        },
        child: ListView(
          padding: const EdgeInsets.all(20),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _buildStatusBanner(),
            const SizedBox(height: 20),
            _buildFormCard(),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'History Report',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _openFullMap(entriesWithLocation),
                  icon: const Icon(Icons.map_rounded, size: 16),
                  label: const Text('Lihat Peta'),
                ),
                if (todayEntries.isNotEmpty)
                  TextButton.icon(
                    onPressed: _shareTodayPdf,
                    icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                    label: const Text('Share PDF'),
                  ),
                if (hasPending)
                  TextButton.icon(
                    onPressed: _syncPending,
                    icon: const Icon(Icons.sync_rounded, size: 16),
                    label: const Text('Sync Offline'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _buildFilterCard(),
            const SizedBox(height: 12),
            if (filteredEntries.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Belum ada report pada filter ini.',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              ...filteredEntries.map(_buildHistoryCard),
          ],
        ),
      ),
    );
  }

  Widget _buildMapSection(List<BargeMovementEntry> entries) {
    final palette = [
      Colors.indigo,
      Colors.teal,
      Colors.deepOrange,
      Colors.purple,
      Colors.blueGrey,
      Colors.green,
    ];
    final grouped = <String, List<BargeMovementEntry>>{};
    for (final entry in entries) {
      final key = _normalizeKapal(entry.namaKapal);
      grouped.putIfAbsent(key, () => []).add(entry);
    }

    final polylines = <Polyline>[];
    final markers = <Marker>[];
    final legendItems = <MapEntry<String, Color>>[];
    var colorIndex = 0;

    for (final kapal in grouped.keys) {
      final kapalEntries = grouped[kapal]!
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      final lastThree = kapalEntries.length <= 3
          ? kapalEntries
          : kapalEntries.sublist(kapalEntries.length - 3);
      final color = palette[colorIndex % palette.length];
      colorIndex += 1;
      legendItems.add(MapEntry(kapal, color));

      final points = _distinctPoints(
        lastThree
            .where((e) => e.latitude != null && e.longitude != null)
            .map((e) => LatLng(e.latitude!, e.longitude!))
            .toList(),
      );
      if (points.length > 1) {
        polylines.add(
          Polyline(
            points: points,
            strokeWidth: 3,
            color: color.withOpacity(0.75),
          ),
        );
      }
      for (final entry in lastThree) {
        markers.add(_buildMovementMarker(entry, color: color));
      }
      if (points.isNotEmpty) {
        markers.add(
          Marker(
            width: 140,
            height: 36,
            point: points.last,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.35),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: color.withOpacity(0.5)),
                  ),
                  child: Text(
                    kapal,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    if (_position != null) {
      markers.add(
        Marker(
          width: 40,
          height: 40,
          point: LatLng(_position!.latitude, _position!.longitude),
          child: Tooltip(
            message: 'Lokasi Anda',
            waitDuration: const Duration(milliseconds: 200),
            child: const Icon(
              Icons.my_location_rounded,
              color: Colors.redAccent,
              size: 26,
            ),
          ),
        ),
      );
    }

    final allPoints = _distinctPoints(
      entries
          .where((e) => e.latitude != null && e.longitude != null)
          .map((e) => LatLng(e.latitude!, e.longitude!))
          .toList(),
    );
    final center =
        allPoints.isNotEmpty ? allPoints.last : const LatLng(0, 0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Peta Pergerakan',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Menampilkan 3 titik terakhir per kapal.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 240,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 12,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.gtime.app',
                    maxZoom: 18,
                  ),
                  TileLayer(
                    urlTemplate:
                        'https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.gtime.app',
                    maxZoom: 18,
                    tileProvider: NetworkTileProvider(),
                  ),
                  if (polylines.isNotEmpty)
                    PolylineLayer(polylines: polylines),
                  if (markers.isNotEmpty) MarkerLayer(markers: markers),
                ],
              ),
            ),
          ),
          if (legendItems.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: legendItems
                  .map(
                    (item) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: item.value.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: item.value.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: item.value,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            item.key,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            'Track ditampilkan berdasarkan 3 titik terakhir per kapal.',
            style: TextStyle(fontSize: 11, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Marker _buildMovementMarker(BargeMovementEntry entry, {Color? color}) {
    final lat = entry.latitude;
    final lng = entry.longitude;
    if (lat == null || lng == null) {
      return const Marker(
        point: LatLng(0, 0),
        width: 0,
        height: 0,
        child: SizedBox.shrink(),
      );
    }
    final markerColor = color ?? (entry.synced ? Colors.green : Colors.orange);
    return Marker(
      width: 16,
      height: 16,
      point: LatLng(lat, lng),
      child: Container(
        decoration: BoxDecoration(
          color: markerColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: markerColor.withOpacity(0.35),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }

  String _buildTooltipMessage(BargeMovementEntry entry) {
    final dateLabel = DateFormat('dd MMM yyyy').format(entry.timestamp);
    final timeLabel = DateFormat('HH:mm').format(entry.timestamp);
    return '${entry.movementName}\n'
        'Tanggal: $dateLabel\n'
        'Jam: $timeLabel\n'
        'Kapal: ${entry.namaKapal}\n'
        'Oleh: ${entry.nama} (${entry.nik})';
  }

  void _showEntryDetail(BargeMovementEntry entry) {
    final dateLabel = DateFormat('dd MMM yyyy').format(entry.timestamp);
    final timeLabel = DateFormat('HH:mm').format(entry.timestamp);
    final location = entry.latitude == null
        ? '-'
        : '${entry.latitude!.toStringAsFixed(5)}, ${entry.longitude!.toStringAsFixed(5)}';
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.movementName,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text('Tanggal: $dateLabel'),
            Text('Jam: $timeLabel'),
            Text('Kapal: ${entry.namaKapal}'),
            Text('Lokasi: $location'),
            if (entry.keterangan.isNotEmpty)
              Text('Keterangan: ${entry.keterangan}'),
            Text('Oleh: ${entry.nama} (${entry.nik}) - ${entry.jabatan}'),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _openFullMap(List<BargeMovementEntry> entries) async {
    final targetDate = _filterDate;
    final dailyEntries = entries
        .where((e) => _isSameDay(e.timestamp, targetDate))
        .toList();
    final remoteEntries = await _fetchMapEntries(targetDate);
    final mapEntries = remoteEntries.isNotEmpty ? remoteEntries : dailyEntries;
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _BargeMovementMapScreen(
          entries: mapEntries,
          dateLabel: DateFormat('dd MMM yyyy').format(targetDate),
        ),
      ),
    );
  }

  Future<void> _shareTodayPdf() async {
    final today = DateTime.now();
    final data = _applyKapalFilter(_entries)
        .where((e) => _isSameDay(e.timestamp, today))
        .toList();
    if (data.isEmpty) {
      _showMessage('Belum ada report hari ini.');
      return;
    }

    final doc = pw.Document();
    final dateLabel = DateFormat('dd MMM yyyy').format(today);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text(
            'Barge Movement Report - $dateLabel',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 12),
          pw.Table.fromTextArray(
            headers: [
              'Jam',
              'Movement',
              'Kapal',
              'Keterangan',
              'Lokasi',
              'Oleh',
            ],
            data: data
                .map(
                  (e) => [
                    DateFormat('HH:mm').format(e.timestamp),
                    e.movementName,
                    e.namaKapal,
                    e.keterangan.isEmpty ? '-' : e.keterangan,
                    e.latitude == null
                        ? '-'
                        : '${e.latitude!.toStringAsFixed(5)}, ${e.longitude!.toStringAsFixed(5)}',
                    '${e.nama} (${e.nik})',
                  ],
                )
                .toList(),
            cellStyle: const pw.TextStyle(fontSize: 10),
            headerStyle: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.centerLeft,
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'barge_movement_$dateLabel.pdf',
    );
  }

  Widget _buildStatusBanner() {
    final label = _isOnline ? 'Online' : 'Offline';
    final color = _isOnline ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
            _isOnline ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _isOnline
                  ? 'Koneksi aktif, report akan dikirim otomatis.'
                  : 'Mode offline, report disimpan di perangkat.',
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard() {
    final dateLabel = _dateFormat.format(_selectedDate);
    final timeLabel = _selectedTime.format(context);
    final locationLabel = _position == null
        ? (_locationError ?? 'Lokasi belum tersedia.')
        : '${_position!.latitude.toStringAsFixed(6)}, ${_position!.longitude.toStringAsFixed(6)}';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _editingId == null ? 'Input Report' : 'Edit Report',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          _buildIdentityRow(),
          const SizedBox(height: 16),
          _InfoTile(
            label: 'Nama Kapal',
            value: _kapalName.isEmpty ? 'Belum terdaftar' : _kapalName,
            icon: Icons.directions_boat_filled_rounded,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _InfoTile(
                  label: 'Tanggal',
                  value: dateLabel,
                  icon: Icons.calendar_month_rounded,
                  onTap: _pickReportDate,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _InfoTile(
                  label: 'Jam',
                  value: timeLabel,
                  icon: Icons.access_time_rounded,
                  onTap: _pickReportTime,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildMasterDropdown(),
          const SizedBox(height: 16),
          _buildKeteranganField(),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _InfoTile(
                  label: 'Lokasi Aktual',
                  value: _isLocating ? 'Mencari lokasi...' : locationLabel,
                  icon: Icons.my_location_rounded,
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                onPressed: _resolveLocation,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          if (_formError != null) ...[
            const SizedBox(height: 12),
            Text(
              _formError!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ],
          const SizedBox(height: 20),
          if (_kapalName.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Akun ini belum memiliki kapal. Input report tidak dapat dilakukan.',
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isSaving || _kapalName.isEmpty
                      ? null
                      : _submitReport,
                  icon: _isSaving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_rounded, size: 18),
                  label: Text(
                    _isSaving
                        ? 'Menyimpan...'
                        : _editingId == null
                            ? 'Simpan Report'
                            : 'Update Report',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: Colors.indigo,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              if (_editingId != null) ...[
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () => setState(() {
                    _editingId = null;
                    _resetReportDateTime();
                  }),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Batal'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityRow() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 18,
            backgroundColor: Color(0xFFE8EAF6),
            child: Icon(Icons.person_rounded, color: Colors.indigo),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _nama,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  'NIK: $_nik | Jabatan: $_jabatan',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMasterDropdown() {
    final selectedLabel = _selectedMaster?.name ?? 'Pilih master movement';
    return InkWell(
      onTap: _masters.isEmpty ? null : _openMasterPicker,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Master Movement',
          prefixIcon: const Icon(Icons.swap_horiz_rounded),
          helperText: _masterError,
          helperStyle: const TextStyle(color: Colors.red, fontSize: 11),
          suffixIcon: _isLoadingMaster
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : const Icon(Icons.arrow_drop_down_rounded),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(
          selectedLabel,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: _selectedMaster == null ? Colors.black54 : Colors.black87,
          ),
        ),
      ),
    );
  }

  List<String> _keteranganSuggestions() {
    if (_entries.isEmpty) return const [];
    final seen = <String>{};
    final suggestions = <String>[];
    for (final entry in _entries) {
      final value = entry.keterangan.trim();
      if (value.isEmpty) continue;
      final key = value.toLowerCase();
      if (seen.add(key)) {
        suggestions.add(value);
      }
    }
    return suggestions;
  }

  Widget _buildKeteranganField() {
    final suggestions = _keteranganSuggestions();
    return RawAutocomplete<String>(
      textEditingController: _keteranganController,
      focusNode: _keteranganFocusNode,
      optionsBuilder: (TextEditingValue textEditingValue) {
        final query = textEditingValue.text.trim().toLowerCase();
        if (suggestions.isEmpty) {
          return const Iterable<String>.empty();
        }
        final filtered = query.isEmpty
            ? suggestions
            : suggestions.where(
                (option) => option.toLowerCase().contains(query),
              );
        return filtered.take(8);
      },
      onSelected: (value) {
        _keteranganController.text = value;
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          minLines: 1,
          maxLines: 2,
          textInputAction: TextInputAction.newline,
          decoration: InputDecoration(
            labelText: 'Keterangan',
            hintText: 'Tulis keterangan (opsional)',
            prefixIcon: const Icon(Icons.notes_rounded),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final list = options.toList();
        if (list.isEmpty) {
          return const SizedBox.shrink();
        }
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 6),
                shrinkWrap: true,
                itemCount: list.length,
                itemBuilder: (context, index) {
                  final option = list[index];
                  return ListTile(
                    dense: true,
                    title: Text(option),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openMasterPicker() async {
    _masterSearchController.text = '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final query = _masterSearchController.text.trim().toLowerCase();
            final filtered = _masters.where((m) {
              if (query.isEmpty) return true;
              return m.name.toLowerCase().contains(query) ||
                  m.id.toLowerCase().contains(query);
            }).toList();

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _masterSearchController,
                    onChanged: (_) => setModalState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Cari master movement...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 320,
                    child: filtered.isEmpty
                        ? const Center(
                            child: Text(
                              'Master movement tidak ditemukan.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = filtered[index];
                              final isSelected =
                                  _selectedMaster?.id == item.id;
                              return ListTile(
                                title: Text(item.name),
                                subtitle: Text('ID: ${item.id}'),
                                trailing: isSelected
                                    ? const Icon(Icons.check_circle_rounded,
                                        color: Colors.indigo)
                                    : null,
                                onTap: () {
                                  setState(() => _selectedMaster = item);
                                  Navigator.pop(context);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFilterCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Filter History',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Harian'),
                selected: _filterMode == _FilterMode.daily,
                onSelected: (_) => setState(() => _filterMode = _FilterMode.daily),
              ),
              ChoiceChip(
                label: const Text('Jam'),
                selected: _filterMode == _FilterMode.hourly,
                onSelected: (_) =>
                    setState(() => _filterMode = _FilterMode.hourly),
              ),
              ChoiceChip(
                label: const Text('Bulan'),
                selected: _filterMode == _FilterMode.monthly,
                onSelected: (_) =>
                    setState(() => _filterMode = _FilterMode.monthly),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _FilterTile(
                  label: _filterMode == _FilterMode.monthly
                      ? 'Bulan'
                      : 'Tanggal',
                  value: DateFormat(
                    _filterMode == _FilterMode.monthly ? 'MMMM yyyy' : 'dd MMM yyyy',
                  ).format(_filterDate),
                  icon: Icons.calendar_month_rounded,
                  onTap: _pickFilterDate,
                ),
              ),
              if (_filterMode == _FilterMode.hourly) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _FilterTile(
                    label: 'Jam',
                    value: _filterHour.format(context),
                    icon: Icons.access_time_rounded,
                    onTap: _pickFilterHour,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(BargeMovementEntry entry) {
    final statusColor = entry.synced ? Colors.green : Colors.orange;
    final dateLabel = DateFormat('dd MMM yyyy').format(entry.timestamp);
    final timeLabel = DateFormat('HH:mm').format(entry.timestamp);
    final location = entry.latitude == null
        ? '-'
        : '${entry.latitude!.toStringAsFixed(5)}, ${entry.longitude!.toStringAsFixed(5)}';
    final canEdit = _kapalName.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
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
              Expanded(
                child: Text(
                  entry.movementName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Chip(
                label: Text(entry.synced ? 'Synced' : 'Offline'),
                backgroundColor: statusColor.withOpacity(0.15),
                labelStyle: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Tanggal: $dateLabel | Jam: $timeLabel',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 6),
          Text(
            'Kapal: ${entry.namaKapal}',
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
          if (entry.keterangan.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Keterangan: ${entry.keterangan}',
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'Lokasi: $location',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton.icon(
                onPressed: canEdit ? () => _startEdit(entry) : null,
                icon: const Icon(Icons.edit_rounded, size: 16),
                label: const Text('Edit'),
              ),
              TextButton.icon(
                onPressed: canEdit ? () => _deleteEntry(entry) : null,
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                label: const Text('Hapus'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  const _InfoTile({
    required this.label,
    required this.value,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(icon, size: 18, color: Colors.indigo),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  const _FilterTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.indigo),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 11)),
                  Text(
                    value,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MovementMaster {
  final String id;
  final String name;

  MovementMaster({required this.id, required this.name});

  factory MovementMaster.fromJson(Map<String, dynamic> json) {
    return MovementMaster(
      id: (json['id'] ?? json['movement_id'] ?? '').toString(),
      name: (json['name'] ?? json['nama'] ?? json['movement_name'] ?? '-')
          .toString(),
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

class BargeMovementEntry {
  final String id;
  final DateTime timestamp;
  final String movementId;
  final String movementName;
  final double? latitude;
  final double? longitude;
  final String nik;
  final String nama;
  final String jabatan;
  final String namaKapal;
  final String keterangan;
  final bool synced;
  final String? serverId;

  const BargeMovementEntry({
    required this.id,
    required this.timestamp,
    required this.movementId,
    required this.movementName,
    required this.latitude,
    required this.longitude,
    required this.nik,
    required this.nama,
    required this.jabatan,
    required this.namaKapal,
    required this.keterangan,
    required this.synced,
    required this.serverId,
  });

  factory BargeMovementEntry.fromJson(Map<String, dynamic> json) {
    return BargeMovementEntry(
      id: (json['id'] ?? '').toString(),
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      movementId: (json['movement_id'] ?? '').toString(),
      movementName: (json['movement_name'] ?? '').toString(),
      latitude: _toDouble(json['latitude']),
      longitude: _toDouble(json['longitude']),
      nik: (json['nik'] ?? '-').toString(),
      nama: (json['nama'] ?? '-').toString(),
      jabatan: (json['jabatan'] ?? '-').toString(),
      namaKapal: (json['nama_kapal'] ?? '-').toString(),
      keterangan: (json['keterangan'] ?? '').toString(),
      synced: json['synced'] == true,
      serverId: json['server_id']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'movement_id': movementId,
        'movement_name': movementName,
        'latitude': latitude,
        'longitude': longitude,
        'nik': nik,
        'nama': nama,
        'jabatan': jabatan,
        'nama_kapal': namaKapal,
        'keterangan': keterangan,
        'synced': synced,
        'server_id': serverId,
      };

  BargeMovementEntry copyWith({
    DateTime? timestamp,
    String? keterangan,
    bool? synced,
    String? serverId,
  }) {
    return BargeMovementEntry(
      id: id,
      timestamp: timestamp ?? this.timestamp,
      movementId: movementId,
      movementName: movementName,
      latitude: latitude,
      longitude: longitude,
      nik: nik,
      nama: nama,
      jabatan: jabatan,
      namaKapal: namaKapal,
      keterangan: keterangan ?? this.keterangan,
      synced: synced ?? this.synced,
      serverId: serverId ?? this.serverId,
    );
  }

  MovementMaster toMaster() => MovementMaster(id: movementId, name: movementName);

  static BargeMovementEntry empty() => BargeMovementEntry(
        id: '',
        timestamp: DateTime.now(),
        movementId: '',
        movementName: '',
        latitude: null,
        longitude: null,
        nik: '-',
        nama: '-',
        jabatan: '-',
        namaKapal: '-',
        keterangan: '',
        synced: false,
        serverId: null,
      );

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return double.tryParse(text.replaceAll(',', '.'));
  }
}

class _SyncResult {
  final bool synced;
  final String? serverId;

  const _SyncResult({required this.synced, required this.serverId});
}

enum _FilterMode { daily, hourly, monthly }

class _BargeMovementMapScreen extends StatelessWidget {
  final List<BargeMovementEntry> entries;
  final String dateLabel;

  const _BargeMovementMapScreen({
    required this.entries,
    required this.dateLabel,
  });

  String _normalizeKapal(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? '-' : trimmed.toUpperCase();
  }

  List<LatLng> _spreadPoints(List<LatLng> points) {
    if (points.length <= 1) return points;
    final counts = <String, int>{};
    final spread = <LatLng>[];
    for (final point in points) {
      final key =
          '${point.latitude.toStringAsFixed(6)},${point.longitude.toStringAsFixed(6)}';
      final index = counts[key] ?? 0;
      counts[key] = index + 1;
      if (index == 0) {
        spread.add(point);
        continue;
      }
      final ring = index ~/ 12;
      final step = index % 12;
      final angle = step * 30 * math.pi / 180;
      final radius = 0.00008 * (1 + ring);
      final latOffset = radius * math.cos(angle);
      final lngOffset =
          radius * math.sin(angle) / math.cos(point.latitude * math.pi / 180);
      spread.add(LatLng(point.latitude + latOffset, point.longitude + lngOffset));
    }
    return spread;
  }

  @override
  Widget build(BuildContext context) {
    final palette = [
      Colors.indigo,
      Colors.teal,
      Colors.deepOrange,
      Colors.purple,
      Colors.blueGrey,
      Colors.green,
    ];
    final grouped = <String, List<BargeMovementEntry>>{};
    for (final entry in entries) {
      final key = _normalizeKapal(entry.namaKapal);
      grouped.putIfAbsent(key, () => []).add(entry);
    }

    final polylines = <Polyline>[];
    final markers = <Marker>[];
    final legendItems = <MapEntry<String, Color>>[];
    var colorIndex = 0;
    final allDisplayPoints = <LatLng>[];

    for (final kapal in grouped.keys) {
      final kapalEntries = grouped[kapal]!
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      final color = palette[colorIndex % palette.length];
      colorIndex += 1;
      legendItems.add(MapEntry(kapal, color));

      final points = kapalEntries
          .where((e) => e.latitude != null && e.longitude != null)
          .map((e) => LatLng(e.latitude!, e.longitude!))
          .toList();
      final displayPoints = _spreadPoints(points);
      allDisplayPoints.addAll(displayPoints);
      if (displayPoints.length > 1) {
        polylines.add(
          Polyline(
            points: displayPoints,
            strokeWidth: 4,
            color: color.withOpacity(0.75),
          ),
        );
      }
      for (final point in displayPoints) {
        markers.add(
          Marker(
            width: 10,
            height: 10,
            point: point,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      }
      if (displayPoints.isNotEmpty) {
        markers.add(
          Marker(
            width: 140,
            height: 36,
            point: displayPoints.last,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.35),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: color.withOpacity(0.5)),
                  ),
                  child: Text(
                    kapal,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    final allPoints = allDisplayPoints;
    final center =
        allPoints.isNotEmpty ? allPoints.last : const LatLng(0, 0);
    final bounds = allPoints.length > 1
        ? LatLngBounds.fromPoints(allPoints)
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        title: Text('Peta Pergerakan ($dateLabel)'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: Column(
        children: [
          Expanded(
            child: allPoints.isEmpty
                ? Center(
                    child: Text(
                      'Map data not available',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  )
                : FlutterMap(
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: 12,
                      initialCameraFit: bounds != null
                          ? CameraFit.bounds(
                              bounds: bounds,
                              padding: const EdgeInsets.all(48),
                            )
                          : null,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.gtime.app',
                        maxZoom: 18,
                      ),
                      TileLayer(
                        urlTemplate:
                            'https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.gtime.app',
                        maxZoom: 18,
                        tileProvider: NetworkTileProvider(),
                      ),
                      if (polylines.isNotEmpty)
                        PolylineLayer(polylines: polylines),
                      if (markers.isNotEmpty) MarkerLayer(markers: markers),
                    ],
                  ),
          ),
          if (legendItems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: legendItems
                    .map(
                      (item) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: item.value.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                          border:
                              Border.all(color: item.value.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: item.value,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              item.key,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

List<LatLng> _distinctPointsGlobal(List<LatLng> points) {
  if (points.length <= 1) return points;
  final unique = <LatLng>[];
  for (final point in points) {
    if (unique.isEmpty) {
      unique.add(point);
      continue;
    }
    final last = unique.last;
    if (last.latitude != point.latitude || last.longitude != point.longitude) {
      unique.add(point);
    }
  }
  return unique;
}
