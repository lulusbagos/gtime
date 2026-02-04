import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../services/api_service.dart';

class RevisiAbsenScreen extends StatefulWidget {
  const RevisiAbsenScreen({super.key});

  @override
  State<RevisiAbsenScreen> createState() => _RevisiAbsenScreenState();
}

class _RevisiAbsenScreenState extends State<RevisiAbsenScreen> {
  DateTime? _selectedDate;
  TimeOfDay? _jamMasuk;
  TimeOfDay? _jamKeluar;
  final TextEditingController _reasonController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  XFile? _proofFile;

  bool _isSubmitting = false;
  bool _isLoadingHistory = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _history = [];

  final DateFormat _displayDateFormat = DateFormat('EEEE, dd MMM yyyy');
  final DateFormat _apiDateFormat = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoadingHistory = true;
      _errorMessage = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) throw Exception('Token tidak ditemukan');
      final response = await ApiService().get('/api/revisi-absen', token: token);
      final List<dynamic> data = response is List
          ? response
          : (response is Map && response['data'] is List)
              ? response['data'] as List<dynamic>
              : const [];
      setState(() {
        _history = data
            .whereType<Map>()
            .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
            .toList();
      });
    } catch (e) {
      setState(() => _errorMessage = 'Gagal memuat data: $e');
    } finally {
      setState(() => _isLoadingHistory = false);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
      helpText: 'Pilih tanggal revisi',
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
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime({required bool isIn}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isIn ? (_jamMasuk ?? TimeOfDay.now()) : (_jamKeluar ?? TimeOfDay.now()),
      helpText: isIn ? 'Jam masuk revisi' : 'Jam keluar revisi',
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isIn) {
          _jamMasuk = picked;
        } else {
          _jamKeluar = picked;
        }
      });
    }
  }

  Future<void> _pickProof() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      setState(() => _proofFile = file);
    }
  }

  Future<void> _submit() async {
    if (_selectedDate == null) {
      _showSnackBar('Tanggal wajib dipilih');
      return;
    }
    if ((_jamMasuk == null || _jamKeluar == null) && _reasonController.text.trim().isEmpty) {
      _showSnackBar('Isi jam masuk/keluar atau keterangan revisi');
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) throw Exception('Token tidak ditemukan');

      final uri = Uri.parse('${ApiService.baseUrl}/api/revisi-absen');
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['tanggal'] = _apiDateFormat.format(_selectedDate!);
      if (_jamMasuk != null) {
        request.fields['jam_in'] = _formatTime(_jamMasuk!);
      }
      if (_jamKeluar != null) {
        request.fields['jam_out'] = _formatTime(_jamKeluar!);
      }
      request.fields['keterangan'] = _reasonController.text.trim();

      if (_proofFile != null) {
        request.files.add(
          await http.MultipartFile.fromPath('lampiran', _proofFile!.path),
        );
      }

      final response = await request.send();
      final body = await response.stream.bytesToString();
      if (response.statusCode == 201) {
        _showSnackBar('Pengajuan revisi dikirim', success: true);
        _resetForm();
        await _loadHistory();
      } else {
        throw Exception(body.isNotEmpty ? body : 'Gagal mengirim revisi');
      }
    } catch (e) {
      _showSnackBar('Gagal: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _resetForm() {
    setState(() {
      _selectedDate = null;
      _jamMasuk = null;
      _jamKeluar = null;
      _reasonController.clear();
      _proofFile = null;
    });
  }

  String _formatDate(DateTime? date) =>
      date == null ? '-' : _displayDateFormat.format(date);

  String _formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  void _showSnackBar(String message, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Revisi Absensi'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: RefreshIndicator(
        onRefresh: _loadHistory,
        child: ListView(
          padding: const EdgeInsets.all(20),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _buildInfoBanner(),
            const SizedBox(height: 20),
            _buildFormCard(),
            const SizedBox(height: 32),
            _buildHistorySection(),
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
              'Isi jam masuk/keluar atau keterangan revisi. Lampiran bersifat opsional.',
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
                  label: 'Tanggal',
                  value: _formatDate(_selectedDate),
                  icon: Icons.calendar_month_rounded,
                  onTap: _pickDate,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _DateTimeTile(
                  label: 'Jam Masuk',
                  value: _jamMasuk != null ? _formatTime(_jamMasuk!) : '-',
                  icon: Icons.login_rounded,
                  onTap: () => _pickTime(isIn: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DateTimeTile(
                  label: 'Jam Keluar',
                  value: _jamKeluar != null ? _formatTime(_jamKeluar!) : '-',
                  icon: Icons.logout_rounded,
                  onTap: () => _pickTime(isIn: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _reasonController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Keterangan',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildAttachmentRow(),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _submit,
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
                _isSubmitting ? 'Mengirim...' : 'Kirim Revisi',
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

  Widget _buildAttachmentRow() {
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: _pickProof,
          icon: const Icon(Icons.attach_file, size: 18),
          label: const Text('Lampiran'),
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _proofFile != null
                ? File(_proofFile!.path).path.split('/').last
                : 'Belum ada lampiran',
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (_proofFile != null)
          IconButton(
            onPressed: () => setState(() => _proofFile = null),
            icon: const Icon(Icons.close, color: Colors.red),
          ),
      ],
    );
  }

  Widget _buildHistorySection() {
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        );
    if (_isLoadingHistory) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          _errorMessage!,
          style: const TextStyle(color: Colors.red),
        ),
      );
    }
    if (_history.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'Belum ada pengajuan revisi.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Riwayat Pengajuan', style: titleStyle),
        const SizedBox(height: 12),
        ..._history.map(_buildHistoryCard),
      ],
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> item) {
    final tanggal = DateTime.tryParse(item['tanggal']?.toString() ?? '');
    final createdAt = DateTime.tryParse(item['created_at']?.toString() ?? '');
    final jamIn = (item['jam_in'] ?? '').toString();
    final jamOut = (item['jam_out'] ?? '').toString();
    final keterangan = (item['keterangan'] ?? '').toString();
    final approval = item['approval'] == true;
    final urlPath = (item['url_path'] ?? '').toString();

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
                  tanggal != null ? _displayDateFormat.format(tanggal) : '-',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              Chip(
                label: Text(approval ? 'Disetujui' : 'Menunggu'),
                backgroundColor:
                    (approval ? Colors.green : Colors.orange).withOpacity(0.15),
                labelStyle: TextStyle(
                  color: approval ? Colors.green : Colors.orange,
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
                '${jamIn.isNotEmpty ? jamIn : '--:--'} - ${jamOut.isNotEmpty ? jamOut : '--:--'}',
                style: const TextStyle(color: Colors.black87),
              ),
            ],
          ),
          if (keterangan.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(keterangan, style: const TextStyle(color: Colors.black87)),
          ],
          if (urlPath.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Lampiran: $urlPath',
              style: TextStyle(color: Colors.blue[600], fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            createdAt != null
                ? 'Diajukan: ${DateFormat('dd MMM yyyy HH:mm').format(createdAt)}'
                : 'Diajukan: -',
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
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(icon, size: 20, color: Colors.indigo),
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
