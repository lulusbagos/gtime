import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';

// --- KONSTANTA WARNA ---
class AppColors {
  static const Color primaryBlue = Color(0xFF0D47A1);
  static const Color accentOrange = Color(0xFFFF6F00);
  static const Color background = Color(0xFFF5F7FA);
  static const Color textDark = Color(0xFF1A1F36);
  static const LinearGradient blueGradient = LinearGradient(
    colors: [Color(0xFF42A5F5), Color(0xFF1976D2)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

// --- DATA MODEL ---
class SmartLearningContent {
  final LearningHighlight highlight;
  final List<String> categories;
  final List<LearningVideo> videos;
  final List<LearningDocument> documents;

  SmartLearningContent({
    required this.highlight,
    required this.categories,
    required this.videos,
    required this.documents,
  });

  factory SmartLearningContent.fromApi(dynamic json) {
    Map<String, dynamic> data = {};
    if (json is Map<String, dynamic>) {
      data = json;
    } else if (json is String) {
      try {
        final decoded = jsonDecode(json);
        if (decoded is Map<String, dynamic>) data = decoded;
      } catch (_) {}
    }

    final videosRaw = data['videos'] ?? data['materials'] ?? data['data'] ?? [];
    final docsRaw = data['documents'] ?? data['docs'] ?? [];
    final highlightRaw = data['highlight'] ??
        data['featured'] ??
        (videosRaw is List && videosRaw.isNotEmpty ? videosRaw.first : {});

    final videos = _mapList(videosRaw, LearningVideo.fromJson);
    final documents = _mapList(docsRaw, LearningDocument.fromJson);
    final extractedCategories = <String>{};
    for (final v in videos) {
      if (v.category.isNotEmpty) extractedCategories.add(v.category);
    }

    final categoriesRaw = data['categories'];
    final categories = <String>{
      'All',
      if (categoriesRaw is List)
        ...categoriesRaw.whereType<String>().map((e) => e.trim()).where(
              (e) => e.isNotEmpty,
            ),
      ...extractedCategories,
    }.toList();

    return SmartLearningContent(
      highlight: LearningHighlight.fromJson(highlightRaw),
      categories: categories,
      videos: videos,
      documents: documents,
    );
  }

  static List<T> _mapList<T>(
    dynamic source,
    T Function(Map<String, dynamic>) builder,
  ) {
    if (source is List) {
      return source
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .map(builder)
          .toList();
    }
    return [];
  }
}

class LearningHighlight {
  final String title;
  final String description;
  final String tag;
  final String imageUrl;

  LearningHighlight({
    required this.title,
    required this.description,
    required this.tag,
    required this.imageUrl,
  });

  factory LearningHighlight.fromJson(dynamic json) {
    if (json is Map<String, dynamic>) {
      return LearningHighlight(
        title: (json['title'] ?? json['name'] ?? 'Smart Learning Zone')
            .toString(),
        description:
            (json['description'] ?? json['caption'] ?? '').toString(),
        tag: (json['tag'] ?? json['category'] ?? 'NEW').toString(),
        imageUrl: (json['image'] ?? json['thumbnail'] ?? '').toString(),
      );
    }
    return LearningHighlight(
      title: 'Smart Learning Zone',
      description: 'Portal materi pembelajaran dan SOP perusahaan.',
      tag: 'NEW',
      imageUrl: '',
    );
  }
}

class LearningVideo {
  final String id;
  final String title;
  final String duration;
  final String category;
  final String thumbnailUrl;
  final Color accentColor;

  LearningVideo({
    required this.id,
    required this.title,
    required this.duration,
    required this.category,
    required this.thumbnailUrl,
    required this.accentColor,
  });

  factory LearningVideo.fromJson(Map<String, dynamic> json) {
    return LearningVideo(
      id: (json['id'] ?? json['uuid'] ?? '').toString(),
      title: (json['title'] ?? json['name'] ?? 'Materi').toString(),
      duration: (json['duration'] ?? json['length'] ?? 'Video').toString(),
      category: (json['category'] ?? json['tag'] ?? '').toString(),
      thumbnailUrl:
          (json['thumbnail'] ?? json['image'] ?? json['cover'] ?? '').toString(),
      accentColor: _parseColor(json['color'], fallback: Colors.blueAccent),
    );
  }
}

class LearningDocument {
  final String id;
  final String title;
  final String size;
  final String type;
  final String fileUrl;

  LearningDocument({
    required this.id,
    required this.title,
    required this.size,
    required this.type,
    required this.fileUrl,
  });

  factory LearningDocument.fromJson(Map<String, dynamic> json) {
    return LearningDocument(
      id: (json['id'] ?? json['uuid'] ?? '').toString(),
      title: (json['title'] ?? json['name'] ?? 'Dokumen').toString(),
      size: (json['size'] ?? json['file_size'] ?? '-').toString(),
      type: (json['type'] ?? json['file_type'] ?? 'PDF').toString(),
      fileUrl: (json['url'] ?? json['file'] ?? '').toString(),
    );
  }
}

Color _parseColor(dynamic value, {Color fallback = Colors.blueAccent}) {
  if (value is int) return Color(value);
  if (value is String) {
    var hex = value.replaceAll('#', '').trim();
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length == 8) {
      try {
        return Color(int.parse(hex, radix: 16));
      } catch (_) {}
    }
  }
  return fallback;
}

class SmartZoneScreen extends StatefulWidget {
  const SmartZoneScreen({super.key});

  @override
  State<SmartZoneScreen> createState() => _SmartZoneScreenState();
}

class _SmartZoneScreenState extends State<SmartZoneScreen> {
  static const String _endpoint = '/api/smart-learning-zone';

  final ApiService _api = ApiService();
  SmartLearningContent? _content;
  bool _isLoading = true;
  String? _error;
  String _selectedCategory = 'All';

  @override
  void initState() {
    super.initState();
    _fetchContent();
  }

  Future<void> _fetchContent() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final data = await _api.get(_endpoint, token: token);
      final parsed = SmartLearningContent.fromApi(data);
      setState(() {
        _content = parsed;
        _isLoading = false;
        _selectedCategory =
            parsed.categories.isNotEmpty ? parsed.categories.first : 'All';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  List<LearningVideo> get _filteredVideos {
    if (_content == null) return [];
    if (_selectedCategory == 'All') return _content!.videos;
    return _content!.videos
        .where(
          (v) => v.category.toLowerCase() == _selectedCategory.toLowerCase(),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Smart Learning Zone',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchContent,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _buildError()
                : _buildContent(),
      ),
    );
  }

  Widget _buildError() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        Icon(Icons.error_outline, color: Colors.red.shade400, size: 48),
        const SizedBox(height: 12),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              _error ?? 'Gagal memuat data',
              style: const TextStyle(
                color: AppColors.textDark,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: ElevatedButton.icon(
            onPressed: _fetchContent,
            icon: const Icon(Icons.refresh),
            label: const Text('Coba Lagi'),
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    final highlight = _content?.highlight;
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (highlight != null) _buildFeaturedBanner(highlight),
          const SizedBox(height: 20),
          _buildCategoryChips(),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Video Pembelajaran",
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
                Text(
                  "Tarik untuk refresh",
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildVideoGrid(context),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              "Dokumen & SOP",
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildDocumentList(context),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildFeaturedBanner(LearningHighlight highlight) {
    return Container(
      margin: const EdgeInsets.all(20),
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: AppColors.blueGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
        image: highlight.imageUrl.isNotEmpty
            ? DecorationImage(
                image: NetworkImage(highlight.imageUrl),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.black.withOpacity(0.25),
                  BlendMode.darken,
                ),
              )
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Positioned(
              right: -20,
              bottom: -30,
              child: Icon(
                Icons.school,
                size: 160,
                color: Colors.white.withOpacity(0.1),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accentOrange,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      highlight.tag.isEmpty ? "NEW" : highlight.tag,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    highlight.title,
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    highlight.description.isEmpty
                        ? "Materi terbaru siap dipelajari."
                        : highlight.description,
                    style: GoogleFonts.poppins(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "Mulai Belajar",
                      style: GoogleFonts.poppins(
                        color: AppColors.primaryBlue,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
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

  Widget _buildCategoryChips() {
    final categories =
        _content?.categories.isNotEmpty == true ? _content!.categories : ['All'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: categories.map((cat) {
          final isSelected = cat == _selectedCategory;
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedCategory = cat;
              });
            },
            child: Container(
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primaryBlue : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? Colors.transparent : Colors.grey.shade300,
                ),
              ),
              child: Text(
                cat,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey.shade600,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildVideoGrid(BuildContext context) {
    final videos = _filteredVideos;
    if (videos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: _buildEmptyState(
          "Belum ada video pada kategori ini.",
          icon: Icons.play_circle_outline,
        ),
      );
    }

    return SizedBox(
      height: 200,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: videos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final vid = videos[index];
          return Container(
            width: 220,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: vid.accentColor.withOpacity(0.2),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      image: vid.thumbnailUrl.isNotEmpty
                          ? DecorationImage(
                              image: NetworkImage(vid.thumbnailUrl),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: Center(
                      child: Icon(
                        Icons.play_circle_fill_rounded,
                        size: 40,
                        color: vid.accentColor,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vid.title,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "${vid.duration} - Video",
                        style: GoogleFonts.poppins(
                          color: Colors.grey,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDocumentList(BuildContext context) {
    final docs = _content?.documents ?? [];
    if (docs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: _buildEmptyState(
          "Belum ada dokumen yang tersedia.",
          icon: Icons.picture_as_pdf_outlined,
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final doc = docs[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade100),
          ),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.picture_as_pdf,
                color: Colors.red,
                size: 24,
              ),
            ),
            title: Text(
              doc.title,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            subtitle: Text(
              "${doc.size} - ${doc.type}",
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey),
            ),
            trailing: const Icon(Icons.download_rounded, color: Colors.grey),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Mengunduh ${doc.title}...')),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(String message, {required IconData icon}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey.shade500),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.textDark,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
