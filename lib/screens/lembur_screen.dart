import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gtime/services/api_service.dart';

class LemburScreen extends StatefulWidget {
  const LemburScreen({super.key});

  @override
  State<LemburScreen> createState() => _LemburScreenState();
}

class _LemburScreenState extends State<LemburScreen> {
  DateTime? _tanggalAwal;
  DateTime? _tanggalAkhir;
  TimeOfDay? _jamAwal;
  TimeOfDay? _jamAkhir;
  final TextEditingController _keteranganController = TextEditingController();

  bool _isSubmitting = false;
  bool _isLoadingList = false;
  String? _listError;
  List<LemburRequest> _requests = [];

  final DateFormat _displayDateFormat = DateFormat('EEEE, dd MMM yyyy');
  final DateFormat _apiDateFormat = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    _tanggalAwal = DateTime.now();
    _tanggalAkhir = DateTime.now();
    _fetchRequests();
  }

  @override
  void dispose() {
    _keteranganController.dispose();
    super.dispose();
  }

  Future<void> _fetchRequests() async {
    setState(() {
      _isLoadingList = true;
      _listError = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) throw ApiException('Sesi habis, silakan login ulang');

      final response =
          await ApiService().get('/api/lembur?limit=50', token: token);
      if (response is Map) {
        final List list = response['data'] as List? ?? [];
        setState(() {
          _requests = list
              .map((e) => LemburRequest.fromJson(e as Map<String, dynamic>))
              .toList();
        });
      } else {
        setState(() {
          _listError = 'Format response tidak dikenal';
        });
      }
    } catch (e) {
      setState(() {
        _listError = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingList = false;
        });
      }
    }
  }

  Future<void> _pickTanggal({required bool isStart}) async {
    final initialDate = isStart
        ? _tanggalAwal ?? DateTime.now()
        : _tanggalAkhir ?? _tanggalAwal ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      helpText: isStart ? 'Pilih tanggal awal lembur' : 'Pilih tanggal akhir',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _tanggalAwal = picked;
          if (_tanggalAkhir == null || _tanggalAkhir!.isBefore(picked)) {
            _tanggalAkhir = picked;
          }
        } else {
          _tanggalAkhir = picked;
          if (_tanggalAwal != null && picked.isBefore(_tanggalAwal!)) {
            _tanggalAwal = picked;
          }
        }
      });
    }
  }

  Future<void> _pickTime({required bool isStart}) async {
    final initialTime = isStart
        ? _jamAwal ?? TimeOfDay.now()
        : _jamAkhir ?? _jamAwal ?? TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      helpText: isStart ? 'Jam mulai lembur' : 'Jam selesai lembur',
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _jamAwal = picked;
        } else {
          _jamAkhir = picked;
        }
      });
    }
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  String _formatDate(DateTime? date) =>
      date == null ? '-' : _displayDateFormat.format(date);

  String _formatTime(TimeOfDay? time) =>
      time == null ? '-' : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  Future<void> _submitRequest() async {
    if (_isSubmitting) return;
    if (_tanggalAwal == null ||
        _tanggalAkhir == null ||
        _jamAwal == null ||
        _jamAkhir == null) {
      _showMessage('Lengkapi tanggal dan jam lembur terlebih dahulu');
      return;
    }

    final start = _dateOnly(_tanggalAwal!);
    final end = _dateOnly(_tanggalAkhir!);
    final diffDays = end.difference(start).inDays;

    if (diffDays < 0 || diffDays > 1) {
      _showMessage('Jarak tanggal awal dan akhir maksimal 1 hari');
      return;
    }

    final today = _dateOnly(DateTime.now());
    if (start.isAfter(today)) {
      _showMessage('Pengajuan sebelum hari H tidak diperbolehkan');
      return;
    }

    final diffFromToday = today.difference(start).inDays;
    if (diffFromToday > 3) {
      _showMessage('Pengajuan hanya diperbolehkan maksimal H+3');
      return;
    }

    if (diffDays == 0) {
      final startMinutes = _jamAwal!.hour * 60 + _jamAwal!.minute;
      final endMinutes = _jamAkhir!.hour * 60 + _jamAkhir!.minute;
      if (endMinutes <= startMinutes) {
        _showMessage('Jam selesai harus lebih besar dari jam mulai');
        return;
      }
    }

    setState(() => _isSubmitting = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) throw ApiException('Sesi habis, silakan login ulang');

      final payload = {
        'tanggal_awal': _apiDateFormat.format(start),
        'tanggal_akhir': _apiDateFormat.format(end),
        'jam_awal': _formatTime(_jamAwal),
        'jam_akhir': _formatTime(_jamAkhir),
        'keterangan': _keteranganController.text.trim(),
      };

      final result =
          await ApiService().post('/api/lembur', body: payload, token: token);

      if (!mounted) return;
      _showMessage(
        result is Map && result['message'] != null
            ? result['message'] as String
            : 'Pengajuan lembur berhasil dikirim',
        isSuccess: true,
      );

      _keteranganController.clear();
      await _fetchRequests();
    } catch (e) {
      if (!mounted) return;
      _showMessage('Gagal mengirim pengajuan: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showMessage(String message, {bool isSuccess = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess ? Colors.green : Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengajuan Lembur'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: RefreshIndicator(
        onRefresh: _fetchRequests,
        child: ListView(
          padding: const EdgeInsets.all(20),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _buildInfoBanner(),
            const SizedBox(height: 20),
            _buildFormCard(),
            const SizedBox(height: 32),
            Text(
              'Riwayat Pengajuan',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            if (_isLoadingList)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_listError != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  _listError!,
                  style: const TextStyle(color: Colors.red),
                ),
              )
            else if (_requests.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Belum ada pengajuan lembur.',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              ..._requests.map(_buildRequestTile),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.info_outline, color: Colors.blue),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              '• Pengajuan lembur hanya dapat dilakukan pada H sampai H+3.\n'
              '• Tidak diperkenankan mengajukan sebelum hari lembur berlangsung.\n'
              '• Selisih tanggal awal dan akhir maksimal 1 hari.',
              style: TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _DateTimeTile(
                  label: 'Tanggal Awal',
                  value: _formatDate(_tanggalAwal),
                  icon: Icons.calendar_month_rounded,
                  onTap: () => _pickTanggal(isStart: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DateTimeTile(
                  label: 'Tanggal Akhir',
                  value: _formatDate(_tanggalAkhir),
                  icon: Icons.event_available_rounded,
                  onTap: () => _pickTanggal(isStart: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _DateTimeTile(
                  label: 'Jam Mulai',
                  value: _formatTime(_jamAwal),
                  icon: Icons.access_time_rounded,
                  onTap: () => _pickTime(isStart: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DateTimeTile(
                  label: 'Jam Selesai',
                  value: _formatTime(_jamAkhir),
                  icon: Icons.schedule_rounded,
                  onTap: () => _pickTime(isStart: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _keteranganController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Keterangan (opsional)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _submitRequest,
              icon: _isSubmitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(
                _isSubmitting ? 'Mengirim...' : 'Ajukan Lembur',
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
        ],
      ),
    );
  }

  Widget _buildRequestTile(LemburRequest request) {
    final dateRange = request.tanggalAkhir != null &&
            request.tanggalAkhir!.difference(request.tanggalAwal).inDays > 0
        ? '${_displayDateFormat.format(request.tanggalAwal)} - ${_displayDateFormat.format(request.tanggalAkhir!)}'
        : _displayDateFormat.format(request.tanggalAwal);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
                  dateRange,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              Chip(
                label: Text(request.statusLabel),
                backgroundColor: request.statusColor.withOpacity(0.15),
                labelStyle: TextStyle(
                  color: request.statusColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.schedule_rounded, size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              Text(
                '${request.jamAwal} - ${request.jamAkhir}',
                style: const TextStyle(color: Colors.black87),
              ),
            ],
          ),
          if (request.keterangan != null && request.keterangan!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              request.keterangan!,
              style: const TextStyle(color: Colors.black87),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Diajukan: ${DateFormat('dd MMM yyyy HH:mm').format(request.createdAt)}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _DateTimeTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  const _DateTimeTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
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
                Icon(icon, size: 20, color: Colors.indigo),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
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

class LemburRequest {
  final String id;
  final DateTime tanggalAwal;
  final DateTime? tanggalAkhir;
  final String jamAwal;
  final String jamAkhir;
  final bool approval;
  final String? keterangan;
  final DateTime createdAt;

  LemburRequest({
    required this.id,
    required this.tanggalAwal,
    required this.tanggalAkhir,
    required this.jamAwal,
    required this.jamAkhir,
    required this.approval,
    required this.keterangan,
    required this.createdAt,
  });

  factory LemburRequest.fromJson(Map<String, dynamic> json) {
    final tanggalAwal = DateTime.tryParse(json['tanggal_awal'] ?? '');
    final tanggalAkhir = DateTime.tryParse(json['tanggal_akhir'] ?? '');
    return LemburRequest(
      id: (json['id'] ?? '').toString(),
      tanggalAwal: tanggalAwal ?? DateTime.now(),
      tanggalAkhir: tanggalAkhir,
      jamAwal: (json['jam_awal'] ?? '--:--').toString(),
      jamAkhir: (json['jam_akhir'] ?? '--:--').toString(),
      approval: json['approval'] == true,
      keterangan: json['keterangan'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
    );
  }

  String get statusLabel => approval ? 'Disetujui' : 'Menunggu';

  Color get statusColor => approval ? Colors.green : Colors.orange;
}
