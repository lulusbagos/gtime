import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gtime/services/api_service.dart';

// --- KONSTANTA WARNA ---
class AppColors {
  static const Color primaryBlue = Color(0xFF0D47A1);
  static const Color accentOrange = Color(0xFFFF6F00);
  static const Color background = Color(0xFFF5F7FA);
  static const Color textDark = Color(0xFF1A1F36);
  static const Color textGrey = Color(0xFF697386);
}

class HeregistrasiScreen extends StatefulWidget {
  const HeregistrasiScreen({super.key});

  @override
  State<HeregistrasiScreen> createState() => _HeregistrasiScreenState();
}

class _HeregistrasiScreenState extends State<HeregistrasiScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _data;
  late TabController _tabController;
  String? _todayShiftStatus;
  String? _todayShiftDesc;
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _domisiliAddressController;
  late final TextEditingController _domisiliCityController;
  late final TextEditingController _domisiliProvinceController;
  late final TextEditingController _domisiliPostalController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _emergencyNameController;
  late final TextEditingController _emergencyPhoneController;
  late final TextEditingController _notesController;
  String _domisiliStatus = 'Tetap';
  bool _isSubmitting = false;
  final List<_FamilyMemberFormData> _familyMembers = [];
  List<Map<String, dynamic>> _submissionHistory = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _domisiliAddressController = TextEditingController();
    _domisiliCityController = TextEditingController();
    _domisiliProvinceController = TextEditingController();
    _domisiliPostalController = TextEditingController();
    _phoneController = TextEditingController();
    _emailController = TextEditingController();
    _emergencyNameController = TextEditingController();
    _emergencyPhoneController = TextEditingController();
    _notesController = TextEditingController();
    _familyMembers.add(_FamilyMemberFormData());
    _loadProfile();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _domisiliAddressController.dispose();
    _domisiliCityController.dispose();
    _domisiliProvinceController.dispose();
    _domisiliPostalController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    _notesController.dispose();
    for (final member in _familyMembers) {
      member.dispose();
    }
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) {
        setState(() => _error = 'Token tidak ditemukan.');
        return;
      }
      final res =
          await ApiService().get('/api/heregistrasi/profile', token: token);
      if (res is Map) {
        final profileRaw = res['profile'];
        final submissionsRaw = res['submissions'];
        if (profileRaw is Map) {
          _data =
              profileRaw.map((key, value) => MapEntry(key.toString(), value));
          _prefillForm();
        }
        if (submissionsRaw is List) {
          _submissionHistory = submissionsRaw
              .whereType<Map>()
              .map((row) => row.map(
                    (key, value) => MapEntry(key.toString(), value),
                  ))
              .cast<Map<String, dynamic>>()
              .toList();
        } else {
          _submissionHistory = [];
        }
        await _loadTodayShift(token);
      } else {
        _error = 'Format data tidak sesuai.';
      }
    } catch (e) {
      _error = 'Gagal memuat: $e';
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadTodayShift(String token) async {
    try {
      final res =
          await ApiService().get('/api/calendar-roster', token: token);
      if (res is List) {
        final today = DateTime.now();
        final todayKey =
            '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

        for (final raw in res) {
          final row = raw as Map;
          final dateRaw = row['working_date'];
          if (dateRaw == null) continue;
          final dateStr = dateRaw.toString().substring(0, 10);
          if (dateStr != todayKey) continue;

          setState(() {
            _todayShiftStatus = (row['status'] ?? '').toString();
            _todayShiftDesc = row['keterangan']?.toString();
          });
          break;
        }
      }
    } catch (_) {
      // Abaikan error shift, jangan ganggu halaman utama
    }
  }

  void _prefillForm() {
    final source = _data;
    if (source == null) return;
    _domisiliAddressController.text =
        (source['alamat_domisili'] ?? '').toString();
    _domisiliCityController.text = (source['kota_domisili'] ?? '').toString();
    _domisiliProvinceController.text =
        (source['provinsi_domisili'] ?? '').toString();
    _domisiliPostalController.text =
        (source['kodepos_domisili'] ?? '').toString();
    _phoneController.text = (source['no_hp'] ?? '').toString();
    _emailController.text = (source['email'] ?? '').toString();
    _emergencyNameController.text =
        (source['kontak_darurat'] ?? '').toString();
    _emergencyPhoneController.text =
        (source['kontak_darurat_telp'] ?? '').toString();
  }

  void _addFamilyMember() {
    setState(() {
      _familyMembers.add(_FamilyMemberFormData());
    });
  }

  void _removeFamilyMember(_FamilyMemberFormData member) {
    if (_familyMembers.length == 1) {
      member.reset();
      return;
    }
    setState(() {
      member.dispose();
      _familyMembers.remove(member);
    });
  }

  Future<void> _pickBirthDate(_FamilyMemberFormData member) async {
    final now = DateTime.now();
    final initialDate = now.subtract(const Duration(days: 3650));
    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1950),
      lastDate: now,
    );
    if (selected != null) {
      member.dobController.text = DateFormat('dd MMM yyyy').format(selected);
      member.dobIso = DateFormat('yyyy-MM-dd').format(selected);
    }
  }

  String _formatDate(dynamic value) {
    if (value == null) return '-';
    try {
      final d = DateTime.parse(value.toString());
      return DateFormat('d MMMM yyyy').format(d);
    } catch (_) {
      return value.toString();
    }
  }

  // --- UI BUILD ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Data Karyawan',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textDark),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primaryBlue,
          unselectedLabelColor: Colors.grey,
          indicatorColor: AppColors.primaryBlue,
          indicatorWeight: 3,
          labelStyle: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          tabs: const [
            Tab(text: "Pribadi"),
            Tab(text: "Pekerjaan"),
            Tab(text: "Lainnya"),
            Tab(text: "Perubahan"),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _tabController.animateTo(3);
        },
        backgroundColor: AppColors.primaryBlue,
        child: const Icon(Icons.edit_rounded),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryBlue),
            )
          : _error != null
          ? Center(
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            )
          : _data == null
          ? const Center(child: Text("Data tidak tersedia"))
          : Column(
              children: [
                const SizedBox(height: 20),
                // Header Profile (Tetap terlihat walau ganti tab)
                _buildProfileHeader(),
                const SizedBox(height: 20),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildPersonalInfoTab(),
                      _buildJobInfoTab(),
                      _buildOtherInfoTab(),
                      _buildUpdateFormTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildProfileHeader() {
    final name = (_data!['nama_lengkap'] ?? 'Nama Karyawan').toString();
    final posisi = (_data!['posisi'] ?? 'Posisi').toString();
    final nik = (_data!['no_nik'] ?? '-').toString();
    final shiftStatus = _todayShiftStatus ?? '-';
    final shiftDesc = _todayShiftDesc;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryBlue, Color(0xFF1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: CircleAvatar(
              radius: 32,
              backgroundColor: Colors.grey[200],
              child: Text(
                name.isNotEmpty ? name[0] : "U",
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryBlue,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  posisi,
                  style: GoogleFonts.poppins(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    "NIK: $nik",
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    shiftDesc != null && shiftDesc.trim().isNotEmpty
                        ? "Shift hari ini: $shiftStatus ($shiftDesc)"
                        : "Shift hari ini: $shiftStatus",
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalInfoTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        _buildInfoTile(
          "Klasifikasi",
          _data!['klasifikasi'],
          Icons.category_rounded,
        ),
        _buildInfoTile("Jenis Kelamin", _data!['jk'], Icons.male_rounded),
        _buildInfoTile(
          "Tempat Lahir",
          _data!['tmp_lahir'],
          Icons.location_city_rounded,
        ),
        _buildInfoTile(
          "Tanggal Lahir",
          _formatDate(_data!['tgl_lahir']),
          Icons.cake_rounded,
        ),
        _buildInfoTile(
          "Usia",
          "${_data!['usia']} Tahun",
          Icons.timelapse_rounded,
        ),
        _buildInfoTile(
          "Agama",
          _data!['agama'],
          Icons.mosque_rounded,
        ), // Ikon bisa disesuaikan
        _buildInfoTile(
          "Status Nikah",
          _data!['status_nikah'],
          Icons.family_restroom_rounded,
        ),
      ],
    );
  }

  Widget _buildJobInfoTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        _buildInfoTile(
          "Perusahaan",
          _data!['nama_perusahaan'],
          Icons.business_rounded,
        ),
        _buildInfoTile("Departemen", _data!['depart'], Icons.domain_rounded),
        _buildInfoTile("Section", _data!['section'], Icons.layers_rounded),
        _buildInfoTile("Posisi", _data!['posisi'], Icons.work_rounded),
        _buildInfoTile("Level", _data!['level'], Icons.star_rounded),
        _buildInfoTile("Lokasi Kerja", _data!['lokker'], Icons.map_rounded),
        _buildInfoTile(
          "Tanggal Masuk",
          _formatDate(_data!['tgl_masuk']),
          Icons.login_rounded,
        ),
        _buildInfoTile(
          "Lama Bekerja",
          _data!['lama_bekerja'],
          Icons.access_time_filled_rounded,
        ),
      ],
    );
  }

  Widget _buildOtherInfoTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        _buildInfoTile(
          "Status Karyawan",
          _data!['status_karyawan'],
          Icons.badge_rounded,
        ),
        _buildInfoTile("No. KTP", _data!['no_ktp'], Icons.credit_card_rounded),
        _buildInfoTile("Alamat KTP", _data!['alamat_ktp'], Icons.home_rounded),
        _buildInfoTile(
          "Alamat Domisili",
          _data!['alamat_domisili'],
          Icons.home_work_rounded,
        ),
        _buildInfoTile("No. HP", _data!['no_hp'], Icons.phone_android_rounded),
        _buildInfoTile("Email", _data!['email'], Icons.email_rounded),
        _buildInfoTile("NPWP", _data!['npwp'], Icons.receipt_long_rounded),
        _buildInfoTile(
          "BPJS Kesehatan",
          _data!['bpjs_kes'],
          Icons.health_and_safety_rounded,
        ),
        _buildInfoTile("BPJS TK", _data!['bpjs_tk'], Icons.security_rounded),
      ],
    );
  }

  Widget _buildUpdateFormTab() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          _sectionCard(
            title: "Kontak & Darurat",
            child: Column(
              children: [
                _buildTextField(
                  controller: _phoneController,
                  label: "Nomor HP",
                  icon: Icons.phone_android_rounded,
                  keyboardType: TextInputType.phone,
                  validator: (val) =>
                      val == null || val.trim().isEmpty ? 'Nomor HP wajib diisi' : null,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _emailController,
                  label: "Email Pribadi",
                  icon: Icons.email_rounded,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _emergencyNameController,
                  label: "Nama Kontak Darurat",
                  icon: Icons.person_rounded,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _emergencyPhoneController,
                  label: "No. Kontak Darurat",
                  icon: Icons.phone,
                  keyboardType: TextInputType.phone,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _sectionCard(
            title: "Alamat Domisili",
            child: Column(
              children: [
                _buildTextField(
                  controller: _domisiliAddressController,
                  label: "Alamat Lengkap",
                  icon: Icons.home_work_rounded,
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _domisiliCityController,
                  label: "Kota/Kabupaten",
                  icon: Icons.location_city_rounded,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _domisiliProvinceController,
                  label: "Provinsi",
                  icon: Icons.map_rounded,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _domisiliPostalController,
                  label: "Kode Pos",
                  icon: Icons.local_post_office_rounded,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _domisiliStatus,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.house_rounded),
                    labelText: 'Status Tempat Tinggal',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Tetap', child: Text('Tetap / Milik sendiri')),
                    DropdownMenuItem(value: 'Kontrak', child: Text('Kontrak / Sewa')),
                    DropdownMenuItem(value: 'Keluarga', child: Text('Menumpang keluarga')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _domisiliStatus = value);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _sectionCard(
            title: "Penambahan Keluarga / Anak",
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ..._familyMembers.map(_buildFamilyMemberCard),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _addFamilyMember,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Tambah Anggota'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _sectionCard(
            title: "Catatan Tambahan",
            child: Column(
              children: [
                TextFormField(
                  controller: _notesController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Keterangan tambahan / alasan perubahan',
                    prefixIcon: const Icon(Icons.notes_rounded),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_submissionHistory.isNotEmpty)
            _sectionCard(
              title: 'Riwayat Pengajuan',
              child: _buildHistoryList(),
            ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _submitHeregistrasi,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(
                _isSubmitting ? 'Mengirim...' : 'Kirim Pengajuan',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.primaryBlue),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Widget _buildFamilyMemberCard(_FamilyMemberFormData member) {
    final index = _familyMembers.indexOf(member) + 1;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withOpacity(0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primaryBlue.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Anggota #$index',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => _removeFamilyMember(member),
                icon: const Icon(Icons.close_rounded, color: Colors.redAccent),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildTextField(
            controller: member.nameController,
            label: "Nama Lengkap",
            icon: Icons.person_rounded,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: member.relation,
            decoration: InputDecoration(
              labelText: 'Hubungan',
              prefixIcon: const Icon(Icons.family_restroom_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            items: const [
              DropdownMenuItem(value: 'Anak', child: Text('Anak')),
              DropdownMenuItem(value: 'Suami/Istri', child: Text('Suami/Istri')),
              DropdownMenuItem(value: 'Orang Tua', child: Text('Orang Tua')),
              DropdownMenuItem(value: 'Lainnya', child: Text('Lainnya')),
            ],
            onChanged: (val) {
              if (val != null) setState(() => member.relation = val);
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: member.dobController,
            readOnly: true,
            decoration: InputDecoration(
              labelText: 'Tanggal Lahir',
              prefixIcon: const Icon(Icons.cake_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onTap: () => _pickBirthDate(member),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: member.notesController,
            decoration: InputDecoration(
              labelText: 'Catatan (opsional)',
              prefixIcon: const Icon(Icons.event_note_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList() {
    final format = DateFormat('dd MMM yyyy HH:mm');
    return Column(
      children: _submissionHistory.map((row) {
        DateTime? created;
        final createdRaw = row['created_at'];
        if (createdRaw != null) {
          created = DateTime.tryParse(createdRaw.toString());
        }
        final subtitle =
            created != null ? format.format(created.toLocal()) : '-';
        final status = (row['status'] ?? '').toString().toUpperCase();
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: AppColors.primaryBlue.withOpacity(0.1),
            child: const Icon(Icons.description_rounded, color: AppColors.primaryBlue),
          ),
          title: Text(
            row['submission_type']?.toString() ?? 'Pengajuan',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(subtitle),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: status == 'APPROVED'
                  ? Colors.green.withOpacity(0.1)
                  : status == 'REJECTED'
                      ? Colors.red.withOpacity(0.1)
                      : Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              status,
              style: TextStyle(
                color: status == 'APPROVED'
                    ? Colors.green
                    : status == 'REJECTED'
                        ? Colors.red
                        : Colors.orange.shade800,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _submitHeregistrasi() async {
    if (_formKey.currentState?.validate() != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lengkapi form terlebih dahulu.')),
      );
      return;
    }
    final families = _familyMembers
        .where((member) => member.nameController.text.trim().isNotEmpty)
        .map(
          (member) => {
            'name': member.nameController.text.trim(),
            'relation': member.relation,
            'birth_date': member.dobIso ?? member.dobController.text.trim(),
            'notes': member.notesController.text.trim(),
          },
        )
        .toList();

    final body = {
      'submissionType': 'DATA_UPDATE',
      'contactUpdate': {
        'phone': _phoneController.text.trim(),
        'email': _emailController.text.trim(),
        'emergency': {
          'name': _emergencyNameController.text.trim(),
          'phone': _emergencyPhoneController.text.trim(),
        },
      },
      'domicileUpdate': {
        'address': _domisiliAddressController.text.trim(),
        'city': _domisiliCityController.text.trim(),
        'province': _domisiliProvinceController.text.trim(),
        'postal_code': _domisiliPostalController.text.trim(),
        'status': _domisiliStatus,
      },
      'familyUpdates': families,
      'additionalInfo': {
        'notes': _notesController.text.trim(),
      },
    };

    setState(() => _isSubmitting = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) {
        throw ApiException('Token tidak ditemukan. Silakan login ulang.');
      }
      await ApiService().post(
        '/api/heregistrasi',
        body: body,
        token: token,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pengajuan dikirim. Tim HR akan meninjau.'),
          backgroundColor: Colors.green,
        ),
      );
      await _loadProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mengirim: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _buildInfoTile(String label, dynamic value, IconData icon) {
    final displayValue =
        (value == null ||
            value.toString().isEmpty ||
            value.toString() == 'null')
        ? '-'
        : value.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primaryBlue, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: AppColors.textGrey,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  displayValue,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FamilyMemberFormData {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController dobController = TextEditingController();
  final TextEditingController notesController = TextEditingController();
  String relation = 'Anak';
  String? dobIso;

  void reset() {
    nameController.clear();
    dobController.clear();
    notesController.clear();
    dobIso = null;
    relation = 'Anak';
  }

  void dispose() {
    nameController.dispose();
    dobController.dispose();
    notesController.dispose();
  }
}
