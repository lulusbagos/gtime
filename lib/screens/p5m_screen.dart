import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gtime/services/api_service.dart';

// --- KONSTANTA WARNA (Sesuai Tema Global) ---
class AppColors {
  static const Color primaryBlue = Color(0xFF0D47A1);
  static const Color accentOrange = Color(0xFFFF6F00);
  static const Color background = Color(0xFFF5F7FA);
  static const Color textDark = Color(0xFF1A1F36);
  static const Color successGreen = Color(0xFF43A047);
  static const Color warningYellow = Color(0xFFFFB300);
  static const Color errorRed = Color(0xFFE53935);
}

class P5MScreen extends StatelessWidget {
  const P5MScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(
            'P5M & Safety Check',
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
            labelColor: AppColors.primaryBlue,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppColors.accentOrange,
            indicatorWeight: 3,
            labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            tabs: const [
              Tab(text: 'Evaluasi Hari Ini'),
              Tab(text: 'Riwayat & Analisa'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            P5MQuestionTab(), // Diubah menjadi Stateful
            P5MHistoryTab(),
          ],
        ),
      ),
    );
  }
}

// --- TAB 1: PERTANYAAN (INTERAKTIF) ---
class P5MQuestionTab extends StatefulWidget {
  const P5MQuestionTab({super.key});

  @override
  State<P5MQuestionTab> createState() => _P5MQuestionTabState();
}

class _P5MQuestionTabState extends State<P5MQuestionTab> {
  Map<String, dynamic>? _p5m;
  List<Map<String, dynamic>> _questions = [];
  bool _isLoading = true;
  String? _error;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadActiveP5M();
  }

  Future<void> _loadActiveP5M() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) throw Exception('Token tidak ditemukan.');

      final res = await ApiService().get('/api/p5m/active', token: token);
      if (res is Map) {
        final p5m = res['p5m'] as Map? ?? {};
        final qs = (res['questions'] as List? ?? [])
            .map<Map<String, dynamic>>((e) {
          final m = (e as Map).map((k, v) => MapEntry(k.toString(), v));
          m['ans'] = null;
          return m;
        }).toList();
        setState(() {
          _p5m = p5m.map((k, v) => MapEntry(k.toString(), v));
          _questions = qs;
        });
      } else {
        _error = 'Format data tidak sesuai.';
      }
    } catch (e) {
      _error = 'Gagal memuat P5M: $e';
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }
    if (_p5m == null || _questions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Tidak ada P5M aktif saat ini.',
            style: GoogleFonts.poppins(color: Colors.grey[600]),
          ),
        ),
      );
    }

    return Column(
      children: [
        // Header info P5M
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
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
              Text(
                _p5m!['judul']?.toString() ?? 'P5M',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _p5m!['deskripsi']?.toString() ?? '',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: _questions.length,
            itemBuilder: (context, index) {
              final item = _questions[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Poin ${item['nomor_urut'] ?? (index + 1)}',
                      style: TextStyle(
                        color: AppColors.primaryBlue.withOpacity(0.6),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item['pertanyaan']?.toString() ?? '',
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _buildOptionButton(index, 'A', "Ya, Aman"),
                        const SizedBox(width: 12),
                        _buildOptionButton(index, 'B', "Tidak"),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        // Tombol Submit
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submitAnswers,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      'KIRIM LAPORAN',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOptionButton(int index, String value, String label) {
    final isSelected = _questions[index]['ans'] == value;
    final color = value == 'A' ? AppColors.successGreen : AppColors.errorRed;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _questions[index]['ans'] = value;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? color : Colors.grey.shade300,
              width: 1.5,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.poppins(
                color: isSelected ? Colors.white : Colors.grey.shade600,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- LOGIC SUBMIT P5M ---
extension P5MSubmitExtension on _P5MQuestionTabState {
  Future<void> _submitAnswers() async {
    if (_p5m == null) return;
    final unanswered =
        _questions.where((q) => q['ans'] == null).length;
    if (unanswered > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Masih ada $unanswered soal yang belum dijawab.'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) throw Exception('Token tidak ditemukan.');

      final answers = _questions
          .map((q) => {
                'question_id': q['question_id'],
                'jawaban_user': q['ans'],
              })
          .toList();

      final body = {
        'p5m_id': _p5m!['p5m_id'],
        'answers': answers,
      };

      final res = await ApiService().post(
        '/api/p5m/submit',
        body: body,
        token: token,
      );

      if (!mounted) return;

      if (res is Map) {
        final nilai = (res['nilai_persen'] ?? 0).toString();
        final lulus = res['lulus'] == true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'P5M tersimpan. Nilai: $nilai%. ${lulus ? 'Lulus' : 'Belum lulus.'}',
            ),
            backgroundColor:
                lulus ? AppColors.successGreen : AppColors.warningYellow,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('P5M tersimpan.'),
            backgroundColor: AppColors.successGreen,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal menyimpan P5M: $e'),
          backgroundColor: AppColors.errorRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}

// --- TAB 2: RIWAYAT (VISUAL & STATISTIK) ---
class P5MHistoryTab extends StatelessWidget {
  const P5MHistoryTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const _P5MHistoryBody();
  }
}

class _P5MHistoryBody extends StatefulWidget {
  const _P5MHistoryBody();

  @override
  State<_P5MHistoryBody> createState() => _P5MHistoryBodyState();
}

class _P5MHistoryBodyState extends State<_P5MHistoryBody> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) throw Exception('Token tidak ditemukan.');

      final res = await ApiService().get(
        '/api/p5m/history',
        token: token,
      );
      if (res is List) {
        _items = res
            .map((e) => (e as Map).map((k, v) => MapEntry(k.toString(), v)))
            .cast<Map<String, dynamic>>()
            .toList();
      } else {
        _error = 'Format data tidak sesuai.';
      }
    } catch (e) {
      _error = 'Gagal memuat riwayat P5M: $e';
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Belum ada riwayat P5M.',
            style: GoogleFonts.poppins(color: Colors.grey[600]),
          ),
        ),
      );
    }

    final avgScore = _items.isEmpty
        ? 0.0
        : _items
                .map((e) => (e['nilai_persen'] as num?)?.toDouble() ?? 0)
                .fold<double>(0, (a, b) => a + b) /
            _items.length;

    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primaryBlue, Color(0xFF1976D2)],
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
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  'Rata-rata Skor',
                  '${avgScore.toStringAsFixed(1)}%',
                  Icons.analytics,
                ),
                Container(width: 1, height: 40, color: Colors.white24),
                _buildStatItem(
                  'Total Laporan',
                  _items.length.toString(),
                  Icons.assignment,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            "Riwayat Laporan",
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 12),
          ..._items.map(_buildHistoryCard),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> item) {
    final score = (item['nilai_persen'] as num?)?.toDouble() ?? 0;
    Color scoreColor;
    if (score >= 90) {
      scoreColor = AppColors.successGreen;
    } else if (score >= 70) {
      scoreColor = AppColors.warningYellow;
    } else {
      scoreColor = AppColors.errorRed;
    }

    final submitted = item['submitted_at']?.toString();
    String dateLabel;
    try {
      final d = DateTime.parse(submitted ?? '');
      dateLabel = DateFormat('dd MMM yyyy, HH:mm').format(d);
    } catch (_) {
      dateLabel = submitted ?? '-';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: scoreColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                score.toStringAsFixed(0),
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  color: scoreColor,
                  fontSize: 16,
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
                  dateLabel,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Skor: ${score.toStringAsFixed(1)}%',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: Colors.grey[300]),
        ],
      ),
    );
  }
}
