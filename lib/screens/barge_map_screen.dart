import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gtime/screens/barge_movement_report_screen.dart';

class BargeMapScreen extends StatefulWidget {
  const BargeMapScreen({super.key});

  @override
  State<BargeMapScreen> createState() => _BargeMapScreenState();
}

class _BargeMapScreenState extends State<BargeMapScreen> {
  static const String _entriesKey = 'barge_movement_reports';

  List<BargeMovementEntry> _entries = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_entriesKey);
      if (raw == null || raw.trim().isEmpty) {
        setState(() {
          _entries = [];
        });
        return;
      }
      final List data = jsonDecode(raw) as List;
      final items = data
          .whereType<Map>()
          .map((e) => BargeMovementEntry.fromJson(e.cast<String, dynamic>()))
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      setState(() {
        _entries = items;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
    for (final entry in _entries) {
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
      final color = palette[colorIndex % palette.length];
      colorIndex += 1;
      legendItems.add(MapEntry(kapal, color));

      final points = _distinctPoints(
        kapalEntries
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
      if (points.isNotEmpty) {
        markers.add(
          Marker(
            width: 16,
            height: 16,
            point: points.last,
            child: Container(
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
          ),
        );
      }
    }

    final allPoints = _distinctPoints(
      _entries
          .where((e) => e.latitude != null && e.longitude != null)
          .map((e) => LatLng(e.latitude!, e.longitude!))
          .toList(),
    );
    final center = allPoints.isNotEmpty ? allPoints.last : const LatLng(0, 0);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        title: const Text('Map Movement Barge'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: RefreshIndicator(
        onRefresh: _loadEntries,
        child: ListView(
          padding: const EdgeInsets.all(20),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Container(
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
                    'Histori Pergerakan Kapal',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Data diambil dari report barge movement (offline cache).',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_error != null)
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    )
                  else if (allPoints.isEmpty)
                    const Text(
                      'Belum ada titik pergerakan.',
                      style: TextStyle(color: Colors.grey),
                    )
                  else
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        height: 320,
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
                            if (markers.isNotEmpty)
                              MarkerLayer(markers: markers),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  if (legendItems.isNotEmpty)
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
                  const SizedBox(height: 8),
                  const Text(
                    'Track dipisahkan per kapal dengan warna berbeda.',
                    style: TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Marker _buildMarker(BargeMovementEntry entry) {
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
    final color = entry.synced ? Colors.green : Colors.orange;
    return Marker(
      width: 40,
      height: 40,
      point: LatLng(lat, lng),
      child: Tooltip(
        message: _tooltip(entry),
        waitDuration: const Duration(milliseconds: 200),
        child: GestureDetector(
          onTap: () => _showDetail(entry),
          child: Icon(Icons.location_on_rounded, color: color, size: 32),
        ),
      ),
    );
  }

  String _tooltip(BargeMovementEntry entry) {
    final dateLabel = DateFormat('dd MMM yyyy').format(entry.timestamp);
    final timeLabel = DateFormat('HH:mm').format(entry.timestamp);
    return '${entry.movementName}\n'
        'Tanggal: $dateLabel\n'
        'Jam: $timeLabel\n'
        'Kapal: ${entry.namaKapal}\n'
        'Oleh: ${entry.nama} (${entry.nik})';
  }

  void _showDetail(BargeMovementEntry entry) {
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
            Text('Oleh: ${entry.nama} (${entry.nik}) - ${entry.jabatan}'),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
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
}
