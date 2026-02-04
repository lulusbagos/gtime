import 'package:flutter/material.dart';
import 'package:gtime/models/barge_logbook_entry.dart';
import 'package:gtime/services/barge_logbook_service.dart';

class BargeLogbookHistoryScreen extends StatefulWidget {
  const BargeLogbookHistoryScreen({super.key});

  @override
  State<BargeLogbookHistoryScreen> createState() =>
      _BargeLogbookHistoryScreenState();
}

class _BargeLogbookHistoryScreenState extends State<BargeLogbookHistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<BargeLogbookEntry> _entries = [];
  List<BargeLogbookEntry> _filtered = [];
  DateTime? _filterDate;
  bool? _filterSynced;
  final Set<String> _syncingIds = {};

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final entries = await BargeLogbookService.loadEntries();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _filtered = List.of(entries);
    });
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = _entries.where((e) {
      final matchVessel =
          e.tugboatName.toLowerCase().contains(query) ||
          e.bargeName.toLowerCase().contains(query);
      final matchDate =
          _filterDate == null ||
          (e.date ==
              '${_filterDate!.year.toString().padLeft(4, '0')}-${_filterDate!.month.toString().padLeft(2, '0')}-${_filterDate!.day.toString().padLeft(2, '0')}');
      final matchSync =
          _filterSynced == null || e.synced == _filterSynced;
      return matchVessel && matchDate && matchSync;
    }).toList();

    setState(() => _filtered = filtered);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() => _filterDate = picked);
      _applyFilter();
    }
  }

  Future<void> _syncEntry(BargeLogbookEntry entry) async {
    setState(() => _syncingIds.add(entry.localId));
    final ok = await BargeLogbookService.syncEntry(entry);
    if (ok) {
      final index = _entries.indexWhere((e) => e.localId == entry.localId);
      if (index >= 0) {
        _entries[index] = entry.copyWith(synced: true);
        await BargeLogbookService.saveEntries(_entries);
      }
    }
    if (!mounted) return;
    setState(() {
      _syncingIds.remove(entry.localId);
    });
    _applyFilter();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Sync berhasil.' : 'Sync gagal. Coba lagi.'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showDetail(BargeLogbookEntry entry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                const Icon(Icons.menu_book_rounded, color: Color(0xFF0D47A1)),
                const SizedBox(width: 8),
                Text(
                  '${entry.tugboatName} / ${entry.bargeName}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                _StatusBadge(synced: entry.synced),
              ],
            ),
            const SizedBox(height: 12),
            _DetailRow(label: 'Tanggal', value: entry.date),
            _DetailRow(label: 'Jam', value: entry.time),
            _DetailRow(label: 'Kapten', value: entry.captainName),
            _DetailRow(
              label: 'Jumlah Kru',
              value: entry.crewCount.toString(),
            ),
            _DetailRow(label: 'Departure', value: entry.departurePort),
            _DetailRow(label: 'Arrival', value: entry.arrivalPort),
            _DetailRow(label: 'Rute', value: entry.route),
            _DetailRow(
              label: 'Jarak (NM)',
              value: entry.distanceNm.toStringAsFixed(1),
            ),
            _DetailRow(
              label: 'Kecepatan',
              value: '${entry.speedKnots.toStringAsFixed(1)} kt',
            ),
            _DetailRow(label: 'Cuaca', value: entry.weather),
            _DetailRow(label: 'Sea State', value: entry.seaState),
            _DetailRow(label: 'Angin', value: entry.wind),
            _DetailRow(label: 'BBM', value: '${entry.fuelLevel}%'),
            _DetailRow(
              label: 'BBM Terpakai',
              value: '${entry.fuelUsed} L',
            ),
            _DetailRow(
              label: 'Jam Mesin Utama',
              value: entry.engineHoursMain.toStringAsFixed(1),
            ),
            _DetailRow(
              label: 'Jam Generator',
              value: entry.engineHoursGen.toStringAsFixed(1),
            ),
            _DetailRow(label: 'Muatan', value: entry.cargoType),
            _DetailRow(
              label: 'Tonase',
              value: entry.cargoTonnage.toStringAsFixed(1),
            ),
            const Divider(height: 24),
            _DetailRow(
              label: 'Mesin Utama',
              value: entry.engineMain ? 'OK' : 'Tidak',
            ),
            _DetailRow(
              label: 'Generator',
              value: entry.engineGen ? 'OK' : 'Tidak',
            ),
            _DetailRow(
              label: 'Lampu Navigasi',
              value: entry.navLights ? 'OK' : 'Tidak',
            ),
            _DetailRow(
              label: 'Radio',
              value: entry.radio ? 'OK' : 'Tidak',
            ),
            _DetailRow(
              label: 'Safety Gear',
              value: entry.safetyGear ? 'OK' : 'Tidak',
            ),
            _DetailRow(
              label: 'Cek Lambung',
              value: entry.hullCheck ? 'OK' : 'Tidak',
            ),
            _DetailRow(
              label: 'Kesiapan Kru',
              value: entry.crewReady ? 'OK' : 'Tidak',
            ),
            const Divider(height: 24),
            _DetailRow(
              label: 'Catatan',
              value: entry.note.isEmpty ? '-' : entry.note,
              multiline: true,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Tugboat Logbook'),
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF6F8FB), Color(0xFFEFF3F8)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Cari nama kapal...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickDate,
                            icon: const Icon(Icons.calendar_today_rounded),
                            label: Text(
                              _filterDate == null
                                  ? 'Semua Tanggal'
                                  : '${_filterDate!.day.toString().padLeft(2, '0')}/${_filterDate!.month.toString().padLeft(2, '0')}/${_filterDate!.year}',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (_filterDate != null)
                          IconButton(
                            onPressed: () {
                              setState(() => _filterDate = null);
                              _applyFilter();
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        _FilterChip(
                          label: 'Semua',
                          selected: _filterSynced == null,
                          onTap: () {
                            setState(() => _filterSynced = null);
                            _applyFilter();
                          },
                        ),
                        _FilterChip(
                          label: 'SYNC',
                          selected: _filterSynced == true,
                          onTap: () {
                            setState(() => _filterSynced = true);
                            _applyFilter();
                          },
                        ),
                        _FilterChip(
                          label: 'LOCAL',
                          selected: _filterSynced == false,
                          onTap: () {
                            setState(() => _filterSynced = false);
                            _applyFilter();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _filtered.isEmpty
                    ? const Center(
                        child: Text(
                          'Tidak ada data logbook.',
                          style: TextStyle(color: Color(0xFF7A8699)),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                        itemBuilder: (context, index) {
                          final entry = _filtered[index];
                          final isSyncing = _syncingIds.contains(entry.localId);
                          return InkWell(
                            onTap: () => _showDetail(entry),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFE1E6EE),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEEF4FF),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.directions_boat_rounded,
                                      color: Color(0xFF0D47A1),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${entry.tugboatName} / ${entry.bargeName}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF2A3443),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${entry.date} - ${entry.time} - BBM ${entry.fuelLevel}%',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF7A8699),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                    children: [
                                      _StatusBadge(synced: entry.synced),
                                      const SizedBox(height: 8),
                                      if (!entry.synced)
                                        SizedBox(
                                          height: 28,
                                          child: OutlinedButton(
                                            onPressed: isSyncing
                                                ? null
                                                : () => _syncEntry(entry),
                                            child: isSyncing
                                                ? const SizedBox(
                                                    width: 14,
                                                    height: 14,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                                  )
                                                : const Text('Sync'),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 12),
                        itemCount: _filtered.length,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF0D47A1) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFF0D47A1) : const Color(0xFFE1E6EE),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF2A3443),
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.synced});

  final bool synced;

  @override
  Widget build(BuildContext context) {
    final color = synced ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        synced ? 'SYNC' : 'LOCAL',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.multiline = false,
  });

  final String label;
  final String value;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment:
            multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF7A8699),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF2A3443),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
