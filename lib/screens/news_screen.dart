import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gtime/services/api_service.dart';

// --- MODEL DATA (TETAP) ---
class NewsItem {
  final String id;
  final String title;
  final String subtitle;
  final String? content;
  final String? imageUrl;
  final DateTime? publishedAt;

  NewsItem({
    required this.id,
    required this.title,
    required this.subtitle,
    this.content,
    this.imageUrl,
    this.publishedAt,
  });

  factory NewsItem.fromJson(Map<String, dynamic> json) {
    return NewsItem(
      id: json['news_id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'No Title',
      subtitle: json['subtitle']?.toString() ?? 'No Subtitle',
      content: json['content'] as String?,
      imageUrl: json['image_url'] as String?,
      publishedAt: json['published_at'] != null
          ? DateTime.parse(json['published_at'] as String)
          : null,
    );
  }
}

// --- CONSTANTS COLORS ---
class AppColors {
  static const Color primaryBlue = Color(0xFF0D47A1);
  static const Color background = Color(0xFFF5F7FA);
  static const Color textDark = Color(0xFF1A1F36);
  static const Color textGrey = Color(0xFF697386);
}

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  bool _isLoading = true;
  String? _error;
  List<NewsItem> _newsList = [];

  @override
  void initState() {
    super.initState();
    _fetchNews();
  }

  // --- LOGIC FETCH (TIDAK BERUBAH) ---
  Future<void> _fetchNews() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) throw Exception('Auth required');

      final response = await ApiService().get('/news', token: token);
      final List<dynamic> data;
      if (response is List) {
        data = response;
      } else if (response is Map && response['data'] is List) {
        data = response['data'] as List<dynamic>;
      } else {
        data = const [];
      }

      setState(() {
        _newsList = data
            .whereType<Map>()
            .map((json) => NewsItem.fromJson(json.cast<String, dynamic>()))
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      log("Error News: $e");
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return DateFormat('d MMMM yyyy').format(date);
  }

  void _navigateToDetail(NewsItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => NewsDetailPage(item: item)),
    );
  }

  // ===========================================================================
  // === BAGIAN UI YANG DIPERBARUI (MODERN & CLEAN) ===
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Berita Terkini',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textDark),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryBlue),
      );
    }
    if (_error != null) {
      return Center(
        child: Text(
          'Gagal memuat: $_error',
          style: const TextStyle(color: Colors.red),
        ),
      );
    }
    if (_newsList.isEmpty) {
      return const Center(
        child: Text(
          'Belum ada berita terbaru.',
          style: TextStyle(color: AppColors.textGrey),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _newsList.length,
      itemBuilder: (context, index) {
        final item = _newsList[index];
        return _buildNewsCard(item, index);
      },
    );
  }

  Widget _buildNewsCard(NewsItem item, int index) {
    // Highlight berita pertama dengan ukuran lebih besar
    final bool isFeatured = index == 0;

    return GestureDetector(
      onTap: () => _navigateToDetail(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Image ---
            SizedBox(
              height: isFeatured ? 220 : 160,
              width: double.infinity,
              child: _buildNewsImage(item.imageUrl),
            ),

            // --- Content ---
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tag / Tanggal
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isFeatured ? 'HEADLINE' : 'NEWS',
                          style: const TextStyle(
                            color: AppColors.primaryBlue,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatDate(item.publishedAt),
                        style: const TextStyle(
                          color: AppColors.textGrey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    item.title,
                    style: TextStyle(
                      fontSize: isFeatured ? 18 : 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textGrey.withOpacity(0.8),
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewsImage(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return Container(
        color: Colors.grey[200],
        child: const Icon(Icons.image, color: Colors.grey),
      );
    }
    return Image.network(
      imageUrl.startsWith('http') ? imageUrl : '${ApiService.baseUrl}$imageUrl',
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: Colors.grey[200],
        child: const Icon(Icons.broken_image, color: Colors.grey),
      ),
    );
  }
}

// --- DETAIL PAGE (PREMIUM IMMERSIVE STYLE) ---
class NewsDetailPage extends StatelessWidget {
  final NewsItem item;
  const NewsDetailPage({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          // --- 1. Immersive App Bar ---
          SliverAppBar(
            expandedHeight: 320.0,
            pinned: true,
            backgroundColor: Colors.white,
            elevation: 0,
            leading: Container(
              margin: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: const BackButton(color: Colors.black),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  _buildDetailImage(item.imageUrl),
                  // Gradient Overlay agar teks putih terbaca (jika ada teks di atas gambar)
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black54],
                        stops: [0.6, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // --- 2. Konten Berita ---
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Meta Data
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_rounded,
                        size: 16,
                        color: AppColors.textGrey,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat(
                          'd MMMM yyyy',
                        ).format(item.publishedAt ?? DateTime.now()),
                        style: const TextStyle(
                          color: AppColors.textGrey,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Judul Besar
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                      height: 1.2,
                      letterSpacing: -0.5,
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Divider(height: 1),
                  const SizedBox(height: 24),

                  // Isi Berita (Typography yang nyaman)
                  Text(
                    item.content ?? item.subtitle,
                    style: const TextStyle(
                      fontSize: 16,
                      height:
                          1.8, // Line height yang nyaman untuk membaca panjang
                      color: Color(
                        0xFF374151,
                      ), // Abu-abu gelap yang lembut di mata
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailImage(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return Container(color: AppColors.primaryBlue.withOpacity(0.1));
    }
    return Image.network(
      imageUrl.startsWith('http') ? imageUrl : '${ApiService.baseUrl}$imageUrl',
      fit: BoxFit.cover,
    );
  }
}
