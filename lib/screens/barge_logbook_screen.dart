import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:gtime/models/barge_logbook_entry.dart';
import 'package:gtime/services/barge_logbook_service.dart';
import 'package:gtime/screens/barge_logbook_history_screen.dart';

class BargeLogbookScreen extends StatefulWidget {
  const BargeLogbookScreen({super.key});

  @override
  State<BargeLogbookScreen> createState() => _BargeLogbookScreenState();
}

class _BargeLogbookScreenState extends State<BargeLogbookScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tugboatController = TextEditingController();
  final _bargeController = TextEditingController();
  final _captainController = TextEditingController();
  final _crewCountController = TextEditingController();
  final _departureController = TextEditingController();
  final _arrivalController = TextEditingController();
  final _routeController = TextEditingController();
  final _weatherController = TextEditingController();
  final _seaStateController = TextEditingController();
  final _windController = TextEditingController();
  final _fuelUsedController = TextEditingController();
  final _distanceController = TextEditingController();
  final _speedController = TextEditingController();
  final _engineMainHoursController = TextEditingController();
  final _engineGenHoursController = TextEditingController();
  final _cargoTypeController = TextEditingController();
  final _cargoTonnageController = TextEditingController();
  final _noteController = TextEditingController();
  final List<BargeLogbookEntry> _history = [];

  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  double _fuelLevel = 70;
  bool _engineMain = true;
  bool _engineGen = true;
  bool _navLights = true;
  bool _radio = true;
  bool _safetyGear = true;
  bool _hullCheck = true;
  bool _crewReady = true;

  @override
  void dispose() {
    _tugboatController.dispose();
    _bargeController.dispose();
    _captainController.dispose();
    _crewCountController.dispose();
    _departureController.dispose();
    _arrivalController.dispose();
    _routeController.dispose();
    _weatherController.dispose();
    _seaStateController.dispose();
    _windController.dispose();
    _fuelUsedController.dispose();
    _distanceController.dispose();
    _speedController.dispose();
    _engineMainHoursController.dispose();
    _engineGenHoursController.dispose();
    _cargoTypeController.dispose();
    _cargoTonnageController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadLocalHistory();
  }

  Future<void> _loadLocalHistory() async {
    final entries = await BargeLogbookService.loadEntries();
    if (mounted) {
      setState(() => _history
        ..clear()
        ..addAll(entries));
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null && mounted) {
      setState(() => _selectedTime = picked);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_engineMain ||
        !_engineGen ||
        !_navLights ||
        !_radio ||
        !_safetyGear ||
        !_hullCheck ||
        !_crewReady) {
      if (mounted) {
        _showValidationDialog(
          'Safety Check Belum Lengkap',
          'Lengkapi seluruh item safety sebelum menyimpan logbook.',
        );
      }
      return;
    }
    final time24 =
        '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}';
    final entry = BargeLogbookEntry(
      localId: DateTime.now().millisecondsSinceEpoch.toString(),
      tugboatName: _tugboatController.text.trim(),
      bargeName: _bargeController.text.trim(),
      captainName: _captainController.text.trim(),
      crewCount: int.tryParse(_crewCountController.text.trim()) ?? 0,
      departurePort: _departureController.text.trim(),
      arrivalPort: _arrivalController.text.trim(),
      route: _routeController.text.trim(),
      weather: _weatherController.text.trim(),
      seaState: _seaStateController.text.trim(),
      wind: _windController.text.trim(),
      note: _noteController.text.trim(),
      date: DateFormat('yyyy-MM-dd').format(_selectedDate),
      time: time24,
      fuelLevel: _fuelLevel.round(),
      fuelUsed: int.tryParse(_fuelUsedController.text.trim()) ?? 0,
      distanceNm: double.tryParse(_distanceController.text.trim()) ?? 0,
      speedKnots: double.tryParse(_speedController.text.trim()) ?? 0,
      engineHoursMain:
          double.tryParse(_engineMainHoursController.text.trim()) ?? 0,
      engineHoursGen:
          double.tryParse(_engineGenHoursController.text.trim()) ?? 0,
      cargoType: _cargoTypeController.text.trim(),
      cargoTonnage: double.tryParse(_cargoTonnageController.text.trim()) ?? 0,
      engineMain: _engineMain,
      engineGen: _engineGen,
      navLights: _navLights,
      radio: _radio,
      safetyGear: _safetyGear,
      hullCheck: _hullCheck,
      crewReady: _crewReady,
      synced: false,
    );

    setState(() {
      _history.insert(0, entry);
      if (_history.length > 50) _history.removeLast();
    });
    await BargeLogbookService.saveEntries(_history);

    await _syncToApi(entry);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Logbook harian disimpan.'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _syncToApi(BargeLogbookEntry entry) async {
    final ok = await BargeLogbookService.syncEntry(entry);
    if (!ok) return;
    final index = _history.indexWhere((e) => e.localId == entry.localId);
    if (index >= 0 && mounted) {
      setState(() {
        _history[index] = entry.copyWith(synced: true);
      });
      await BargeLogbookService.saveEntries(_history);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateText = DateFormat('dd MMM yyyy').format(_selectedDate);
    final timeText = _selectedTime.format(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tugboat Logbook'),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Riwayat',
            icon: const Icon(Icons.history_rounded),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const BargeLogbookHistoryScreen(),
                ),
              );
            },
          ),
        ],
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
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _HeaderCard(dateText: dateText, timeText: timeText),
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'Identitas Tugboat',
                  icon: Icons.directions_boat_filled_rounded,
                  child: Column(
                    children: [
                      _TextField(
                        controller: _tugboatController,
                        label: 'Nama Tugboat',
                        hint: 'Contoh: TB. Anugerah 07',
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Nama tugboat wajib diisi'
                                : null,
                      ),
                      const SizedBox(height: 12),
                      _TextField(
                        controller: _bargeController,
                        label: 'Nama Barge',
                        hint: 'Contoh: BG. Prima 01',
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Nama barge wajib diisi'
                                : null,
                      ),
                      const SizedBox(height: 12),
                      _TextField(
                        controller: _captainController,
                        label: 'Nama Kapten',
                        hint: 'Nama kapten/pengemudi',
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Nama kapten wajib diisi'
                                : null,
                      ),
                      const SizedBox(height: 12),
                      _TextField(
                        controller: _crewCountController,
                        label: 'Jumlah Kru',
                        hint: 'Contoh: 6',
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          final parsed = int.tryParse(value ?? '');
                          if (parsed == null || parsed <= 0) {
                            return 'Jumlah kru wajib diisi';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'Voyage',
                  icon: Icons.route_rounded,
                  child: Column(
                    children: [
                      _TextField(
                        controller: _departureController,
                        label: 'Departure Port',
                        hint: 'Pelabuhan keberangkatan',
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Departure wajib diisi'
                                : null,
                      ),
                      const SizedBox(height: 12),
                      _TextField(
                        controller: _arrivalController,
                        label: 'Arrival Port',
                        hint: 'Pelabuhan tujuan',
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Arrival wajib diisi'
                                : null,
                      ),
                      const SizedBox(height: 12),
                      _TextField(
                        controller: _routeController,
                        label: 'Rute / Area Operasi',
                        hint: 'Contoh: Jetty - Anchorage',
                      ),
                      const SizedBox(height: 12),
                      _TextField(
                        controller: _distanceController,
                        label: 'Jarak Tempuh (NM)',
                        hint: 'Contoh: 12.5',
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                      ),
                      const SizedBox(height: 12),
                      _TextField(
                        controller: _speedController,
                        label: 'Kecepatan (knots)',
                        hint: 'Contoh: 6.8',
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'Muatan',
                  icon: Icons.inventory_2_rounded,
                  child: Column(
                    children: [
                      _TextField(
                        controller: _cargoTypeController,
                        label: 'Jenis Muatan',
                        hint: 'Contoh: Batubara',
                      ),
                      const SizedBox(height: 12),
                      _TextField(
                        controller: _cargoTonnageController,
                        label: 'Tonase Muatan (ton)',
                        hint: 'Contoh: 3200',
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'Cuaca & Kondisi',
                  icon: Icons.waves_rounded,
                  child: Column(
                    children: [
                      _TextField(
                        controller: _weatherController,
                        label: 'Kondisi Cuaca',
                        hint: 'Cerah / Berawan / Hujan',
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Cuaca wajib diisi'
                                : null,
                      ),
                      const SizedBox(height: 12),
                      _TextField(
                        controller: _seaStateController,
                        label: 'Sea State',
                        hint: 'Contoh: Calm / Slight / Moderate',
                      ),
                      const SizedBox(height: 12),
                      _TextField(
                        controller: _windController,
                        label: 'Angin',
                        hint: 'Contoh: 10 knot NE',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'Operasi Mesin',
                  icon: Icons.settings_rounded,
                  child: Column(
                    children: [
                      _TextField(
                        controller: _engineMainHoursController,
                        label: 'Jam Mesin Utama',
                        hint: 'Contoh: 4.5',
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        validator: (value) {
                          final parsed = double.tryParse(value ?? '');
                          if (parsed == null) {
                            return 'Jam mesin utama wajib diisi';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      _TextField(
                        controller: _engineGenHoursController,
                        label: 'Jam Generator',
                        hint: 'Contoh: 4.0',
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'Waktu & Cuaca',
                  icon: Icons.schedule_rounded,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _InfoButton(
                              label: 'Tanggal',
                              value: dateText,
                              icon: Icons.calendar_today_rounded,
                              onTap: _pickDate,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _InfoButton(
                              label: 'Jam',
                              value: timeText,
                              icon: Icons.access_time_rounded,
                              onTap: _pickTime,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'Fuel & Operasi',
                  icon: Icons.local_gas_station_rounded,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Level BBM (${_fuelLevel.toStringAsFixed(0)}%)',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2A3443),
                        ),
                      ),
                      Slider(
                        value: _fuelLevel,
                        min: 0,
                        max: 100,
                        divisions: 20,
                        label: '${_fuelLevel.toStringAsFixed(0)}%',
                        onChanged: (value) =>
                            setState(() => _fuelLevel = value),
                      ),
                      const SizedBox(height: 6),
                      _TextField(
                        controller: _fuelUsedController,
                        label: 'BBM Terpakai (liter)',
                        hint: 'Contoh: 120',
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      _StatusRow(
                        label: 'Mesin Utama',
                        value: _engineMain,
                        onChanged: (v) => setState(() => _engineMain = v),
                      ),
                      _StatusRow(
                        label: 'Generator',
                        value: _engineGen,
                        onChanged: (v) => setState(() => _engineGen = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'Safety Check',
                  icon: Icons.shield_rounded,
                  child: Column(
                    children: [
                      _StatusRow(
                        label: 'Lampu Navigasi',
                        value: _navLights,
                        onChanged: (v) => setState(() => _navLights = v),
                      ),
                      _StatusRow(
                        label: 'Radio Komunikasi',
                        value: _radio,
                        onChanged: (v) => setState(() => _radio = v),
                      ),
                      _StatusRow(
                        label: 'Peralatan Keselamatan',
                        value: _safetyGear,
                        onChanged: (v) => setState(() => _safetyGear = v),
                      ),
                      _StatusRow(
                        label: 'Cek Lambung',
                        value: _hullCheck,
                        onChanged: (v) => setState(() => _hullCheck = v),
                      ),
                      _StatusRow(
                        label: 'Kesiapan Kru',
                        value: _crewReady,
                        onChanged: (v) => setState(() => _crewReady = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'Catatan',
                  icon: Icons.notes_rounded,
                  child: _TextField(
                    controller: _noteController,
                    label: 'Catatan Harian',
                    hint: 'Temuan, kondisi khusus, atau tindakan',
                    maxLines: 4,
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Simpan Logbook'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D47A1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
                const SizedBox(height: 24),
                _SectionCard(
                  title: 'Riwayat Terbaru',
                  icon: Icons.history_rounded,
                  child: _history.isEmpty
                      ? const Text(
                          'Belum ada logbook yang tersimpan.',
                          style: TextStyle(color: Color(0xFF7A8699)),
                        )
                      : Column(
                          children: _history
                              .take(3)
                              .map((entry) => _LogHistoryTile(entry: entry))
                              .toList(),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showValidationDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(color: Colors.redAccent)),
        content: Text(message),
        actions: [
          TextButton(
            child: const Text('OK'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }
}

class _LogHistoryTile extends StatelessWidget {
  const _LogHistoryTile({required this.entry});

  final BargeLogbookEntry entry;

  @override
  Widget build(BuildContext context) {
    final statusColor = entry.synced ? Colors.green : Colors.orange;
    final statusText = entry.synced ? 'SYNC' : 'LOCAL';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE1E6EE)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.directions_boat_rounded,
              color: statusColor,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                    fontSize: 11,
                    color: Color(0xFF7A8699),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.dateText, required this.timeText});

  final String dateText;
  final String timeText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D47A1), Color(0xFF1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D47A1).withOpacity(0.2),
            blurRadius: 18,
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
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.menu_book_rounded, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Daily Check Tugboat',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Checklist dan catatan harian',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                dateText,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                timeText,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E9F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF4FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: const Color(0xFF0D47A1), size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2A3443),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF7F9FC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE1E6EE)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF0D47A1)),
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF2A3443),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: const Color(0xFF0D47A1),
        ),
      ],
    );
  }
}

class _InfoButton extends StatelessWidget {
  const _InfoButton({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F9FC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE1E6EE)),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF0D47A1), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF7A8699),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2A3443),
                    ),
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
