import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:ui'; // Untuk BackdropFilter

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:gtime/screens/login_screen.dart';
import 'package:gtime/services/api_service.dart';
import 'package:mime/mime.dart';
import 'package:http_parser/http_parser.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:gtime/services/biometric_service.dart';
import 'package:gtime/services/secure_storage_service.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:uuid/uuid.dart';

import 'package:gtime/theme.dart' as theme;
import 'package:gtime/widgets/premium_widgets.dart';

// --- CONSTANTS COLORS ---
class AppColors {
  static const Color primaryBlue = theme.primaryBlue;
  static const Color accentOrange = theme.secondaryOrange;
  static const Color background = theme.lightGray;
  static const Color textDark = theme.darkGray;
  static const Color textMuted = theme.textGray;

  static LinearGradient headerGradient = LinearGradient(
    colors: [primaryBlue, primaryBlue.withOpacity(0.82)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  // Gradient untuk E-SIMPER (Metallic Blue/Grey)
  static const LinearGradient simperGradient = LinearGradient(
    colors: [Color(0xFF37474F), Color(0xFF263238)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  static const MethodChannel _installerChannel = MethodChannel(
    'shiftcorner.indexim.installer',
  );

  // --- State User ---
  String? _namaLengkap;
  String? _username; // NIK
  String? _posisi;
  String? _depart;
  String? _profileImageUrl;
  String? _tempPhotoPath;

  String? _lastLogin;
  String? _unitToday;
  bool? _fingerEnabled;
  bool _isUpdatingFinger = false;

  final ImagePicker _picker = ImagePicker();
  bool _isUploading = false;
  bool _isChangingPassword = false;

  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final String _baseUrl = ApiService.baseUrl;

  // --- Update / Version state ---
  String? _localVersion;
  String? _serverVersion;
  String? _downloadUrl;
  bool _checkingUpdate = false;
  bool _downloadingUpdate = false;
  double _downloadProgress = 0.0;
  late AnimationController _entryController;
  late AnimationController _ambientController;
  late Animation<double> _floatAnimation;
  late Animation<double> _tiltAnimation;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
    _floatAnimation = Tween<double>(begin: -4, end: 4).animate(
      CurvedAnimation(parent: _ambientController, curve: Curves.easeInOut),
    );
    _tiltAnimation = Tween<double>(begin: -0.02, end: 0.02).animate(
      CurvedAnimation(parent: _ambientController, curve: Curves.easeInOut),
    );
    _loadProfile();
    _initVersionCheck();
  }

  @override
  void dispose() {
    _entryController.dispose();
    _ambientController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // --- LOGIC FUNCTIONS (SAME AS BEFORE) ---
  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _namaLengkap = prefs.getString('nama_lengkap');
      _username = prefs.getString('username');
      _posisi = prefs.getString('posisi');
      _depart = prefs.getString('depart');
      _profileImageUrl =
          prefs.getString('avatar') ?? prefs.getString('profile_image_url');
      _lastLogin = prefs.getString('last_login');
    });

    try {
      final token = prefs.getString('auth_token');
      if (token != null && token.isNotEmpty) {
        final unitRes = await ApiService().get(
          '/api/user/unit-today',
          token: token,
        );
        if (unitRes is Map && unitRes['has_unit'] == true) {
          if (!mounted) return;
          setState(() {
            _unitToday = (unitRes['unit'] ?? '').toString();
          });
        }
        await _fetchFingerprintStatus(token);
      }
    } catch (e) {
      // ignore error
    }
  }

  Future<void> _fetchFingerprintStatus([String? token]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final effectiveToken = token ?? prefs.getString('auth_token');
      if (effectiveToken == null) return;

      final res = await ApiService().get(
        '/api/user/fingerprint',
        token: effectiveToken,
      );
      if (res is Map && res.containsKey('enabled')) {
        final enabled = res['enabled'] == true;
        await prefs.setBool('biometric_enabled', enabled);
        if (!enabled) {
          await SecureStorageService.delete('biometric_secret');
          await prefs.remove('biometric_username');
        }
        if (!mounted) return;
        setState(() {
          _fingerEnabled = enabled;
        });
      }
    } catch (_) {
      // diamkan saja, tidak blokir UI
    }
  }

  Future<String> _resolveDeviceId() async {
    try {
      if (kIsWeb) return 'web';
      final plugin = DeviceInfoPlugin();
      if (defaultTargetPlatform == TargetPlatform.android) {
        final info = await plugin.androidInfo;
        final manufacturer = (info.manufacturer ?? '').trim();
        final model = (info.model ?? '').trim();
        final combined = '$manufacturer $model'.trim();
        return combined.isEmpty ? 'Android Device' : combined;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final info = await plugin.iosInfo;
        final name = (info.name ?? '').trim();
        final model = (info.model ?? '').trim();
        final resolved = name.isNotEmpty ? name : model;
        return resolved.isEmpty ? 'iOS Device' : resolved;
      }
      if (defaultTargetPlatform == TargetPlatform.windows) {
        final info = await plugin.windowsInfo;
        final computerName = (info.computerName ?? '').trim();
        return computerName.isEmpty ? 'Windows Device' : computerName;
      }
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        final info = await plugin.macOsInfo;
        final deviceName = (info.computerName ?? '').trim();
        return deviceName.isEmpty ? 'macOS Device' : deviceName;
      }
      if (defaultTargetPlatform == TargetPlatform.linux) {
        final info = await plugin.linuxInfo;
        final name = (info.name ?? '').trim();
        return name.isEmpty ? 'Linux Device' : name;
      }
    } catch (_) {}
    return 'unknown-device';
  }

  Future<void> _pickAndUploadPhoto() async {
    final XFile? file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 70,
    );
    if (file != null) {
      setState(() {
        _isUploading = true;
        _tempPhotoPath = file.path;
      });
      try {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('auth_token');
        final mimeType = lookupMimeType(file.path);
        final contentType = mimeType != null ? MediaType.parse(mimeType) : null;

        final uri = Uri.parse('$_baseUrl/api/user/upload-avatar');
        var request = http.MultipartRequest('POST', uri)
          ..headers['Authorization'] = 'Bearer $token'
          ..files.add(
            await http.MultipartFile.fromPath(
              'avatar',
              file.path,
              filename: p.basename(file.path),
              contentType: contentType,
            ),
          );

        final response = await request.send();
        final respStr = await response.stream.bytesToString();

        if (response.statusCode == 200) {
          final data = jsonDecode(respStr);
          final newUrlPath = data['data']['avatar'] as String;
          final fullUrl = newUrlPath.startsWith('http')
              ? newUrlPath
              : _resolveImageUrl(newUrlPath);
          await prefs.setString('avatar', fullUrl);
          setState(() {
            _profileImageUrl = fullUrl;
            _tempPhotoPath = null;
          });
        }
      } catch (e) {
        // ignore error
      } finally {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Konfirmasi Logout'),
        content: const Text('Anda yakin ingin keluar?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Ya, Logout',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      final rememberLogin = prefs.getBool('remember_login') ?? false;
      final rememberedUsername = prefs.getString('remembered_username');
      final rememberedPassword = prefs.getString('remembered_password');
      final biometricEnabled = prefs.getBool('biometric_enabled') ?? false;
      final biometricUsername = prefs.getString('biometric_username');

      await prefs.clear();

      await prefs.setBool('remember_login', rememberLogin);
      if (rememberedUsername != null) {
        await prefs.setString('remembered_username', rememberedUsername);
      }
      if (rememberedPassword != null) {
        await prefs.setString('remembered_password', rememberedPassword);
      }
      await prefs.setBool('biometric_enabled', biometricEnabled);
      if (biometricUsername != null) {
        await prefs.setString('biometric_username', biometricUsername);
      }
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  // --- DIALOGS ---
  void _showAboutAppDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.verified_user_rounded,
                color: AppColors.primaryBlue,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "Tentang Aplikasi",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const Text(
              "Versi 1.0.0 (Internal Build)",
              style: TextStyle(
                fontWeight: FontWeight.normal,
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Divider(),
              const SizedBox(height: 8),
              RichText(
                textAlign: TextAlign.left,
                text: TextSpan(
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 13,
                    height: 1.5,
                    fontFamily: 'Poppins',
                  ),
                  children: [
                    const TextSpan(
                      text:
                          "Aplikasi ini merupakan properti intelektual eksklusif milik ",
                    ),
                    const TextSpan(
                      text: "PT Indexim Coalindo",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const TextSpan(
                      text: ", dikembangkan dan dikelola sepenuhnya oleh ",
                    ),
                    const TextSpan(
                      text: "Departemen System Integrasi",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                    const TextSpan(text: ".\n\n"),
                    const TextSpan(
                      text:
                          "Perangkat lunak ini didesain khusus untuk mendukung operasional internal perusahaan PELAYARAN GANESHA LAUT JAYA dan Sister Company PT INDEXIM COALINDO. Segala bentuk penyalinan, modifikasi, rekayasa balik (reverse engineering), atau distribusi tanpa izin tertulis dari manajemen adalah pelanggaran hukum dan tata tertib perusahaan.\n\n",
                    ),
                    const TextSpan(
                      text: "Data yang dimuat bersifat Rahasia (Confidential).",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.redAccent,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  children: const [
                    Text(
                      "© 2025 PT Indexim Coalindo",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      "All Rights Reserved",
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "Tutup",
              style: TextStyle(color: AppColors.primaryBlue),
            ),
          ),
        ],
      ),
    );
  }

  void _showNikQrDialog() {
    final nik = _username ?? '-';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'QR Code NIK',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 200,
              height: 200,
              child: QrImageView(
                data: nik,
                version: QrVersions.auto,
                size: 200,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              nik,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog() {
    _oldPasswordController.clear();
    _newPasswordController.clear();
    _confirmPasswordController.clear();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Ganti Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _oldPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password Lama',
                icon: Icon(Icons.lock_outline),
              ),
            ),
            TextField(
              controller: _newPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password Baru',
                icon: Icon(Icons.lock),
              ),
            ),
            TextField(
              controller: _confirmPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Konfirmasi',
                icon: Icon(Icons.lock_clock),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: _submitChangePassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
            ),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _showSnackbar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  void _showErrorDialog(String title, String content) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            child: const Text('OK'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }

  Future<void> _initVersionCheck() async {
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() {
        _localVersion = '${info.version}+${info.buildNumber}';
      });
      await _checkUpdate(quiet: true);
    } catch (e) {
      _showSnackbar('Gagal membaca versi lokal: $e', Colors.red);
    }
  }

  Future<void> _checkUpdate({bool quiet = false}) async {
    setState(() {
      _checkingUpdate = true;
    });
    try {
      final res = await ApiService().get('/api/app-version');
      if (res is Map) {
        final serverV = (res['version'] ?? res['app_version'] ?? '')
            .toString()
            .trim();
        final dl = (res['download_url'] ?? res['apk_url'] ?? '')
            .toString()
            .trim();
        setState(() {
          _serverVersion = serverV.isNotEmpty ? serverV : null;
          _downloadUrl = dl.isNotEmpty ? dl : null;
        });
      }
    } catch (e) {
      if (!quiet) {
        _showSnackbar('Gagal cek update: $e', Colors.red);
      }
    } finally {
      setState(() {
        _checkingUpdate = false;
      });
    }
  }

  bool get _updateAvailable {
    if (_serverVersion == null || _localVersion == null) return false;
    return _serverVersion!.trim() != _localVersion!.trim();
  }

  String _updateStatusText() {
    if (_checkingUpdate) return 'Memeriksa pembaruan...';
    if (_updateAvailable) {
      return 'Versi baru: ${_serverVersion ?? '-'} (lokal ${_localVersion ?? '-'})';
    }
    return 'Up to date (${_localVersion ?? '-'})';
  }

  Future<void> _downloadUpdate() async {
    if (_downloadingUpdate) return;
    final urlRaw = _downloadUrl;
    if (urlRaw == null || urlRaw.isEmpty) {
      _showSnackbar('URL unduhan tidak tersedia', Colors.red);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null || token.isEmpty) {
      _showSnackbar('Token tidak ditemukan, silakan login ulang', Colors.red);
      return;
    }

    final url = urlRaw.startsWith('http')
        ? urlRaw
        : '${ApiService.baseUrl}$urlRaw';

    setState(() {
      _downloadingUpdate = true;
      _downloadProgress = 0;
    });

    try {
      final client = http.Client();
      final req = http.Request('GET', Uri.parse(url));
      req.headers['Authorization'] = 'Bearer $token';

      final res = await client.send(req);
      if (res.statusCode != 200) {
        log(
          'Download APK gagal: HTTP ${res.statusCode} ${res.reasonPhrase ?? ''}',
          name: 'ProfileScreen._downloadUpdate',
        );
        throw Exception('HTTP ${res.statusCode}');
      }

      final total = res.contentLength ?? 0;
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'shiftcorner-update.apk'));
      final sink = file.openWrite();
      int received = 0;

      await res.stream.listen((chunk) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0) {
          setState(() {
            _downloadProgress = received / total;
          });
        }
      }).asFuture();

      await sink.close();
      final installMessage = Platform.isAndroid
          ? 'Unduhan selesai, installer akan terbuka otomatis'
          : 'Unduhan selesai: ${file.path}';

      if (Platform.isAndroid) {
        await _openInstaller(file.path);
      } else {
        await OpenFilex.open(file.path);
      }
      _showSnackbar(installMessage, Colors.green);
    } catch (e, stackTrace) {
      log(
        'Unduhan APK gagal',
        name: 'ProfileScreen._downloadUpdate',
        error: e,
        stackTrace: stackTrace,
      );
      _showSnackbar('Gagal mengunduh update: $e', Colors.red);
    } finally {
      setState(() {
        _downloadingUpdate = false;
      });
    }
  }

  Future<void> _openInstaller(String apkPath) async {
    try {
      await _installerChannel.invokeMethod('installApk', {'path': apkPath});
    } on PlatformException catch (err, stackTrace) {
      log(
        'Installer intent gagal',
        name: 'ProfileScreen._openInstaller',
        error: err,
        stackTrace: stackTrace,
      );
      _showSnackbar(
        'Unduhan selesai, silakan buka APK secara manual',
        Colors.orange,
      );
    } catch (err, stackTrace) {
      log(
        'Tanpa exception installer',
        name: 'ProfileScreen._openInstaller',
        error: err,
        stackTrace: stackTrace,
      );
      _showSnackbar(
        'Unduhan selesai, silakan buka APK secara manual',
        Colors.orange,
      );
    }
  }

  Widget _buildDownloadOverlay() {
    final percentage = (_downloadProgress * 100).clamp(0.0, 100.0);
    final showPercent = _downloadProgress > 0 && _downloadProgress <= 1;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.7),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 24,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Mengunduh pembaruan',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: showPercent ? _downloadProgress : null,
                  minHeight: 6,
                ),
                const SizedBox(height: 12),
                Text(
                  showPercent
                      ? 'Progress ${percentage.toStringAsFixed(0)}%'
                      : 'Menunggu data...',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Installer bakal terbuka otomatis setelah selesai.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showFingerprintSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final current = _fingerEnabled;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 50,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Status Login Biometrik',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 4),
              const Text(
                'Pilih aktif/nonaktif. Saat mengaktifkan, Anda akan diminta verifikasi biometrik.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              RadioListTile<bool>(
                value: true,
                groupValue: current,
                onChanged: _isUpdatingFinger
                    ? null
                    : (val) {
                        Navigator.pop(ctx);
                        if (val != null) _updateFingerprint(val);
                      },
                title: const Text('Aktif'),
                subtitle: const Text(
                  'Gunakan fingerprint/biometrik untuk login',
                ),
              ),
              RadioListTile<bool>(
                value: false,
                groupValue: current,
                onChanged: _isUpdatingFinger
                    ? null
                    : (val) {
                        Navigator.pop(ctx);
                        if (val != null) _updateFingerprint(val);
                      },
                title: const Text('Nonaktif'),
                subtitle: const Text('Matikan login biometrik untuk akun ini'),
              ),
              const SizedBox(height: 8),
              if (_isUpdatingFinger)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: CircularProgressIndicator(),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _updateFingerprint(bool enabled) async {
    if (_isUpdatingFinger) return;

    // Saat mengaktifkan, wajib verifikasi biometrik dulu
    if (enabled) {
      final availabilityIssue = await BiometricService.getAvailabilityIssue();
      if (availabilityIssue != null) {
        _showErrorDialog('Gagal', availabilityIssue);
        return;
      }
      final ok = await BiometricService.authenticate();
      if (!ok) {
        _showErrorDialog(
          'Gagal',
          'Verifikasi biometrik dibatalkan atau gagal. Pastikan layar memakai PIN/pola dan sidik jari aktif.',
        );
        return;
      }
    }

    setState(() => _isUpdatingFinger = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null || token.isEmpty) {
        _showErrorDialog(
          'Error',
          'Token tidak ditemukan. Silakan login ulang.',
        );
        return;
      }

      if (enabled) {
        final deviceId = await _resolveDeviceId();
        final secret = const Uuid().v4();
        await ApiService().patch(
          '/api/user/biometric',
          token: token,
          body: {'enabled': true, 'device_id': deviceId, 'secret': secret},
        );
        await SecureStorageService.write('biometric_secret', secret);
        await prefs.setBool('biometric_enabled', true);
        final username = _username ?? prefs.getString('username') ?? '';
        if (username.isNotEmpty) {
          await prefs.setString('biometric_username', username);
        }
        setState(() => _fingerEnabled = true);
      } else {
        await ApiService().patch(
          '/api/user/biometric',
          token: token,
          body: {'enabled': false},
        );
        await prefs.setBool('biometric_enabled', false);
        await prefs.remove('biometric_username');
        await SecureStorageService.delete('biometric_secret');
        setState(() => _fingerEnabled = false);
      }
      _showSnackbar(
        enabled
            ? 'Biometrik diaktifkan. Anda bisa login tanpa password.'
            : 'Biometrik dinonaktifkan.',
        Colors.green,
      );
    } catch (e) {
      _showErrorDialog('Error', e.toString());
    } finally {
      if (mounted) setState(() => _isUpdatingFinger = false);
    }
  }

  ImageProvider _buildAvatarImage() {
    if (_tempPhotoPath != null) return FileImage(File(_tempPhotoPath!));
    if (_profileImageUrl != null && _profileImageUrl!.isNotEmpty) {
      return NetworkImage(
        _profileImageUrl!.startsWith('http')
            ? _profileImageUrl!
            : _resolveImageUrl(_profileImageUrl!),
      );
    }
    return const AssetImage('assets/images/default_avatar.png');
  }

  String _resolveImageUrl(String raw) {
    if (raw.startsWith('http')) return raw;
    final base = ApiService.baseUrl;
    final baseNormalized =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final path = raw.startsWith('/') ? raw : '/$raw';
    return '$baseNormalized$path';
  }

  // ===========================================================================
  // === UI BUILDER ===
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          _buildBackground(),
          SingleChildScrollView(
            child: Column(
              children: [
                // --- 1. HEADER PROFILE: Premium gradient + Avatar ---
                _buildAnimatedSection(0.0, _buildProfileHeader(context)),

                const SizedBox(height: 16),

                // --- 2. INFO STRIP (1 garis) ---
                _buildAnimatedSection(0.08, _buildInfoStrip()),

                const SizedBox(height: 24),

                // --- 3. STATUS PERANGKAT ---
                // Dihapus: Status Perangkat dan Smartwatch
                const SizedBox(height: 24),

                // --- 4. SETTINGS MENU ---
                _buildAnimatedSection(
                  0.16,
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                        child: Row(
                          children: const [
                            Icon(
                              Icons.tune_rounded,
                              size: 18,
                              color: AppColors.primaryBlue,
                            ),
                            SizedBox(width: 8),
                            Text(
                              "Pengaturan Akun",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: PremiumCard(
                          padding: EdgeInsets.zero,
                          borderRadius: 20,
                          child: Column(
                            children: [
                              _buildSettingsRow(
                                icon: Icons.fingerprint_rounded,
                                iconColor: const Color(0xFF5E35B1),
                                title: 'Login Biometrik',
                                subtitle: _fingerEnabled == null
                                    ? 'Memeriksa status...'
                                    : _fingerEnabled == true
                                    ? 'Aktif'
                                    : 'Nonaktif',
                                onTap: _showFingerprintSheet,
                              ),
                              const Divider(
                                height: 1,
                                indent: 72,
                                endIndent: 16,
                              ),
                              _buildSettingsRow(
                                icon: Icons.lock_reset_rounded,
                                iconColor: AppColors.primaryBlue,
                                title: 'Ganti Password',
                                onTap: _showChangePasswordDialog,
                              ),
                              const Divider(
                                height: 1,
                                indent: 72,
                                endIndent: 16,
                              ),
                              _buildSettingsRow(
                                icon: Icons.system_update_alt_rounded,
                                iconColor: AppColors.accentOrange,
                                title: _updateAvailable
                                    ? 'Update tersedia'
                                    : 'Versi aplikasi',
                                subtitle: _updateStatusText(),
                                trailing: _downloadingUpdate
                                    ? SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          value:
                                              _downloadProgress > 0 &&
                                                  _downloadProgress < 1
                                              ? _downloadProgress
                                              : null,
                                        ),
                                      )
                                    : TextButton(
                                        onPressed: _updateAvailable
                                            ? _downloadUpdate
                                            : () => _checkUpdate(),
                                        child: Text(
                                          _updateAvailable ? 'Download' : 'Cek',
                                        ),
                                      ),
                                onTap: _updateAvailable
                                    ? _downloadUpdate
                                    : () => _checkUpdate(),
                              ),
                              const Divider(
                                height: 1,
                                indent: 72,
                                endIndent: 16,
                              ),
                              _buildSettingsRow(
                                icon: Icons.info_outline_rounded,
                                iconColor: const Color(0xFF009688),
                                title: 'Tentang Aplikasi',
                                subtitle: 'Lisensi & Hak Cipta',
                                onTap: _showAboutAppDialog,
                              ),
                              const Divider(
                                height: 1,
                                indent: 72,
                                endIndent: 16,
                              ),
                              _buildSettingsRow(
                                icon: Icons.logout_rounded,
                                iconColor: Colors.redAccent,
                                title: 'Keluar Akun',
                                subtitle: 'Logout dan hapus sesi di perangkat',
                                onTap: _logout,
                                isDanger: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),
                _buildAnimatedSection(
                  0.24,
                  Column(
                    children: const [
                      Text(
                        "© 2025 PT Indexim Coalindo",
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      SizedBox(height: 20),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_downloadingUpdate) _buildDownloadOverlay(),
        ],
      ),
    );
  }

  // --- Helper Widgets ---

  Widget _buildProfileHeader(BuildContext context) {
    return SizedBox(
      height: 300,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 210,
            decoration: BoxDecoration(
              gradient: AppColors.headerGradient,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryBlue.withOpacity(0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Profil Karyawan',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    IconButton(
                      onPressed: _showNikQrDialog,
                      icon: const Icon(
                        Icons.qr_code_rounded,
                        color: Colors.white,
                      ),
                      tooltip: 'QR NIK',
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 210,
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
                child: CustomPaint(
                  painter: _BatikPainter(
                    primary: Colors.white.withOpacity(0.14),
                    accent: AppColors.accentOrange.withOpacity(0.18),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 86,
            left: 0,
            right: 0,
            child: Column(
              children: [
                GestureDetector(
                  onTap: _pickAndUploadPhoto,
                  child: AnimatedBuilder(
                    animation: _ambientController,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, _floatAnimation.value),
                        child: Transform.rotate(
                          angle: _tiltAnimation.value,
                          child: child,
                        ),
                      );
                    },
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          top: -10,
                          left: -10,
                          right: -10,
                          bottom: -10,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.accentOrange.withOpacity(0.35),
                                  AppColors.primaryBlue.withOpacity(0.15),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      AppColors.accentOrange.withOpacity(0.25),
                                  blurRadius: 26,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                          ),
                        ),
                        AnimatedScale(
                          duration: const Duration(milliseconds: 200),
                          scale: _isUploading ? 0.98 : 1.0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.primaryBlue.withOpacity(0.35),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.06),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 54,
                              backgroundColor: theme.lightGray,
                              backgroundImage: _buildAvatarImage(),
                              onBackgroundImageError: (_, __) {},
                              child:
                                  (_profileImageUrl == null &&
                                      _tempPhotoPath == null)
                                  ? const Icon(
                                      Icons.person,
                                      size: 60,
                                      color: theme.textGray,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 2,
                          right: 2,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.accentOrange,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      AppColors.accentOrange.withOpacity(0.25),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: _isUploading
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.camera_alt_rounded,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                          ),
                        ),
                        if (_fingerEnabled == true)
                          Positioned(
                            top: -2,
                            right: -2,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color:
                                      AppColors.primaryBlue.withOpacity(0.15),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.06),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.fingerprint_rounded,
                                color: AppColors.primaryBlue,
                                size: 20,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _namaLengkap ?? 'Loading...',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppColors.primaryBlue.withOpacity(0.12),
                    ),
                  ),
                  child: Text(
                    _posisi ?? 'Employee',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textDark,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoStrip() {
    final items = <_InfoItem>[
      _InfoItem(Icons.badge_outlined, 'NIK', _username ?? '-'),
      _InfoItem(Icons.business_rounded, 'Departemen', _depart ?? '-'),
      _InfoItem(
        Icons.schedule_rounded,
        'Terakhir Login',
        _formatDateLabel(_lastLogin),
      ),
      if (_unitToday != null)
        _InfoItem(Icons.directions_car_filled_rounded, 'Unit', _unitToday!),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        height: 92,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final item = items[index];

            // Staggered: tiap card muncul sedikit terlambat biar modern.
            final start = (0.10 + (index * 0.06)).clamp(0.0, 0.9);
            final anim = CurvedAnimation(
              parent: _entryController,
              curve: Interval(start, 1.0, curve: Curves.easeOutCubic),
            );

            return FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.08, 0),
                  end: Offset.zero,
                ).animate(anim),
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.98, end: 1.0).animate(anim),
                  child: _PressableScale(
                    child: SizedBox(
                      width: 210,
                      child: PremiumCard(
                        borderRadius: 18,
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    AppColors.primaryBlue.withOpacity(0.14),
                                    AppColors.primaryBlue.withOpacity(0.06),
                                  ],
                                ),
                                border: Border.all(
                                  color: AppColors.primaryBlue.withOpacity(
                                    0.12,
                                  ),
                                ),
                              ),
                              child: Icon(
                                item.icon,
                                color: AppColors.primaryBlue,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    item.label,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textMuted,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item.value,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textDark,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // dihapus: Widget _buildSmartwatchStatusCard()

  Widget _buildBackground() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [theme.lightGray, Color(0xFFE9F0FF)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            Positioned(
              top: -80,
              right: -60,
              child: _buildGlowCircle(
                180,
                AppColors.primaryBlue.withOpacity(0.08),
              ),
            ),
            Positioned(
              bottom: 120,
              left: -50,
              child: _buildGlowCircle(
                140,
                AppColors.accentOrange.withOpacity(0.08),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlowCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _buildAnimatedSection(double start, Widget child) {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: _entryController,
        curve: Interval(start, 1.0, curve: Curves.easeOut),
      ),
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
            .animate(
              CurvedAnimation(
                parent: _entryController,
                curve: Interval(start, 1.0, curve: Curves.easeOut),
              ),
            ),
        child: child,
      ),
    );
  }

  Widget _buildSettingsRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    bool isDanger = false,
    Widget? trailing,
  }) {
    return _PressableScale(
      onTap: onTap,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                iconColor.withOpacity(0.18),
                iconColor.withOpacity(0.06),
              ],
            ),
            border: Border.all(color: iconColor.withOpacity(0.18)),
          ),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: isDanger ? Colors.redAccent : AppColors.textDark,
          ),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
        trailing:
            trailing ??
            Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textMuted.withOpacity(0.6),
            ),
      ),
    );
  }

  String _formatDateLabel(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    try {
      final dt = DateTime.parse(raw);
      return DateFormat('dd MMM yyyy, HH:mm').format(dt);
    } catch (_) {
      return raw;
    }
  }

  void _submitChangePassword() async {
    if (_isChangingPassword) return;
    final oldPass = _oldPasswordController.text.trim();
    final newPass = _newPasswordController.text.trim();
    final confirmPass = _confirmPasswordController.text.trim();
    if (oldPass.isEmpty || newPass.isEmpty || confirmPass.isEmpty) {
      _showSnackbar('Semua kolom harus diisi', Colors.red);
      return;
    }
    if (newPass != confirmPass) {
      _showSnackbar('Password baru dan konfirmasi tidak sama', Colors.red);
      return;
    }
    setState(() {
      _isChangingPassword = true;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) throw Exception('Token tidak ditemukan');
      final res = await ApiService().post(
        '/api/user/change-password',
        token: token,
        body: {'old_password': oldPass, 'new_password': newPass},
      );
      if (res is Map && res['success'] == true) {
        Navigator.pop(context);
        _showSnackbar('Password berhasil diganti', Colors.green);
      } else {
        final msg = res is Map
            ? (res['message'] ?? 'Gagal ganti password')
            : 'Gagal ganti password';
        _showSnackbar(msg, Colors.red);
      }
    } catch (e) {
      _showSnackbar('Error: $e', Colors.red);
    } finally {
      setState(() {
        _isChangingPassword = false;
      });
    }
  }
}

class _InfoItem {
  final IconData icon;
  final String label;
  final String value;

  _InfoItem(this.icon, this.label, this.value);
}

class _PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _PressableScale({required this.child, this.onTap});

  @override
  State<_PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<_PressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() {
      _pressed = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: widget.onTap,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          scale: _pressed ? 0.985 : 1.0,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            opacity: _pressed ? 0.98 : 1.0,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _BatikPainter extends CustomPainter {
  final Color primary;
  final Color accent;

  _BatikPainter({required this.primary, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    const double tile = 52;
    final primaryPaint = Paint()
      ..color = primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    final accentPaint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (double y = -tile; y < size.height + tile; y += tile) {
      for (double x = -tile; x < size.width + tile; x += tile) {
        final center = Offset(x + tile / 2, y + tile / 2);
        const double r = 8;
        canvas.drawCircle(center.translate(-r, 0), r, primaryPaint);
        canvas.drawCircle(center.translate(r, 0), r, primaryPaint);
        canvas.drawCircle(center.translate(0, -r), r, primaryPaint);
        canvas.drawCircle(center.translate(0, r), r, primaryPaint);
        final diamond = Path()
          ..moveTo(center.dx, center.dy - r)
          ..lineTo(center.dx + r, center.dy)
          ..lineTo(center.dx, center.dy + r)
          ..lineTo(center.dx - r, center.dy)
          ..close();
        canvas.drawPath(diamond, accentPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BatikPainter oldDelegate) {
    return oldDelegate.primary != primary || oldDelegate.accent != accent;
  }
}
