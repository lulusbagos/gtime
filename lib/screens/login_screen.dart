import 'dart:developer' as dev;
import 'dart:ui'; // Diperlukan untuk BackdropFilter
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/gestures.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';
import 'package:gtime/services/api_service.dart';
import 'package:gtime/services/biometric_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:gtime/services/push_service.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:gtime/services/secure_storage_service.dart';

// --- DEFINISI WARNA PREMIUM (Blue, Orange, White Theme) ---
class LoginColors {
  static const Color primaryBlue = Color(0xFF1565C0); // Corporate Blue
  static const Color darkBlue = Color(0xFF0D47A1); // Deep Blue
  static const Color accentOrange = Color(0xFFFF6F00); // Energetic Orange
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFF5F7FA); // Very light greyish blue
  static const Color textDark = Color(0xFF2D3748);
  static const Color textLight = Color(0xFF718096);
  static const Color inputFill = Color(0xFFF8FAFC);

  static const LinearGradient blueGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1976D2), Color(0xFF0D47A1)],
  );

  static const LinearGradient orangeGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFA726), Color(0xFFFF6F00)],
  );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
        // Tidak perlu controller khusus untuk GIF jika hanya pakai Image.asset
        with
        SingleTickerProviderStateMixin {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscureText = true;
  bool _rememberLogin = false;
  bool _canUseBiometric = false;
  bool _biometricEnabled = false;
  String? _biometricUsername;
  String? _errorMessage;
  String _deviceName = '';

  // Animation
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _loadRememberedUser();
    _initDeviceName();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        );

    _animController.forward();
    _initBiometric();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _animController.dispose();
    super.dispose();
  }

  // --- LOGIC SECTION (TETAP SAMA DENGAN KODE ASLI) ---

  Future<void> _initBiometric() async {
    final available = await BiometricService.isBiometricAvailable();
    if (!mounted) return;
    setState(() {
      _canUseBiometric = available;
    });
    await _loadBiometricPreference();
  }

  Future<void> _loadBiometricPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('biometric_enabled') ?? false;
    final username = prefs.getString('biometric_username');
    if (!mounted) return;
    setState(() {
      _biometricEnabled = enabled && (username?.isNotEmpty ?? false);
      _biometricUsername = username;
    });
  }

  Future<void> _initDeviceName() async {
    final resolved = await _detectDeviceName();
    if (!mounted) return;
    setState(() => _deviceName = resolved);
  }

  Future<String> _detectDeviceName() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (kIsWeb) return 'Web Browser';
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
    } catch (e) {
      dev.log('Gagal membaca info device: $e');
    }
    return 'Unknown Device';
  }

  Future<String> _ensureDeviceName() async {
    final cached = _deviceName.trim();
    if (cached.isNotEmpty) return cached;
    final resolved = await _detectDeviceName();
    if (!mounted) return resolved;
    setState(() => _deviceName = resolved);
    return resolved;
  }

  Future<void> _persistSession(String token, Map<String, dynamic> userData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    final username = (userData['username'] ?? '').toString();
    await prefs.setString('username', username.isNotEmpty ? username : '-');
    await prefs.setString(
      'nama_lengkap',
      (userData['nama_lengkap'] ?? userData['username'] ?? '-') as String,
    );
    await prefs.setString('posisi', userData['posisi']?.toString() ?? '-');
    await prefs.setString('depart', userData['depart']?.toString() ?? '-');
    await prefs.setString('avatar', userData['avatar']?.toString() ?? '');
    await prefs.setString('kapal', userData['kapal']?.toString() ?? '');
    await prefs.setString(
      'last_login',
      userData['last_login']?.toString() ?? userData['lastLogin']?.toString() ?? '',
    );
    await prefs.setBool('server_biometric_flag', userData['finger'] == true);
    await PushService.syncTokenAfterLogin();
  }

  void _navigateHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  Future<void> _handleBiometricLogin() async {
    if (_isLoading) return;
    if (!_canUseBiometric) {
      _showErrorSnackbar('Perangkat ini tidak mendukung biometrik.');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('biometric_enabled') ?? false;
    final username = prefs.getString('biometric_username');
    final secret = await SecureStorageService.read('biometric_secret');

    if (!enabled || username == null || secret == null) {
      _showErrorSnackbar(
        'Biometrik belum diaktifkan. Silakan aktifkan dari menu profil.',
      );
      return;
    }

    final availabilityIssue = await BiometricService.getAvailabilityIssue();
    if (availabilityIssue != null) {
      _showErrorSnackbar(availabilityIssue);
      return;
    }

    final ok = await BiometricService.authenticate();
    if (!ok) {
      _showErrorSnackbar('Autentikasi biometrik dibatalkan atau gagal.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final deviceName = await _ensureDeviceName();
      final info = await PackageInfo.fromPlatform();
      final response = await ApiService().post(
        '/auth/biometric-login',
        body: {
          'username': username,
          'secret': secret,
          'appVersion': '${info.version}+${info.buildNumber}',
          'device': deviceName,
        },
      );

      if (response is! Map<String, dynamic>) {
        throw ApiException('Respons biometrik tidak valid.');
      }
      final token = response['token'] as String?;
      final userData = response['user'] as Map<String, dynamic>?;
      if (token == null || userData == null) {
        throw ApiException('Data login biometrik tidak lengkap.');
      }

      await _persistSession(token, userData);
      await _loadBiometricPreference();
      if (!mounted) return;
      _navigateHome();
    } catch (e) {
      _showErrorSnackbar('Gagal login biometrik: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadRememberedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final storedUsername = prefs.getString('remembered_username') ?? '';
    final storedPassword = prefs.getString('remembered_password') ?? '';
    final shouldRemember = prefs.getBool('remember_login') ?? false;
    if (!mounted) return;
    setState(() {
      _rememberLogin = shouldRemember;
      if (shouldRemember &&
          storedUsername.isNotEmpty &&
          storedPassword.isNotEmpty) {
        _usernameController.text = storedUsername;
        _passwordController.text = storedPassword;
      }
    });
  }

  Future<void> _signIn() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final deviceName = await _ensureDeviceName();
      if (deviceName.trim().isEmpty) {
        throw ApiException('Gagal membaca nama perangkat. Coba ulangi lagi.');
      }
      final info = await PackageInfo.fromPlatform();
      final localVersion = '${info.version}+${info.buildNumber}';

      final response = await ApiService().post(
        '/login',
        body: {
          'username': _usernameController.text,
          'password': _passwordController.text,
          'appVersion': localVersion,
          'device': deviceName,
        },
      );
      if (response is Map<String, dynamic>) {
        final token = response['token'] as String?;
        final userData = response['user'] as Map<String, dynamic>?;
        if (token == null || userData == null) {
          if (!mounted) return;
          _showErrorSnackbar('Data tidak valid.');
          return;
        }
        await _persistSession(token, userData);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('remember_login', _rememberLogin);
        if (_rememberLogin) {
          await prefs.setString(
            'remembered_username',
            _usernameController.text.trim(),
          );
          await prefs.setString(
            'remembered_password',
            _passwordController.text,
          );
        } else {
          await prefs.remove('remembered_username');
          await prefs.remove('remembered_password');
        }

        await _loadBiometricPreference();
        if (!mounted) return;
        _navigateHome();
      } else {
        if (!mounted) return;
        _errorMessage = 'Format response salah.';
        _showErrorSnackbar(_errorMessage!);
      }
    } catch (e) {
      if (!mounted) return;
      String message;
      if (e is ApiException) {
        message = e.message;
        if (message.contains('Unauthorized')) {
          message = 'Kredensial tidak valid.';
        }
        if (message.toLowerCase().contains('perangkat lain') ||
            message.toLowerCase().contains('24 jam')) {
          message =
              'Login ditolak. Tunggu 24 jam agar bisa login dari perangkat berbeda.';
        }
      } else {
        message = 'Gagal login: $e';
      }
      setState(() {
        _errorMessage = message;
      });
      _showErrorSnackbar(message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade800,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showForgotPasswordSheet() {
    // ... (Logic lupa password tetap sama, hanya UI disesuaikan sedikit jika perlu)
    final nikController = TextEditingController();
    final dobController = TextEditingController();
    DateTime? selectedDate;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 24,
          right: 24,
          top: 24,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "Recovery Access",
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: LoginColors.textDark,
              ),
            ),
            Text(
              "Verifikasi identitas Anda untuk reset password.",
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: LoginColors.textLight,
              ),
            ),
            const SizedBox(height: 24),
            // Reusing modern text field style manually here for simplicity
            TextField(
              controller: nikController,
              decoration: InputDecoration(
                labelText: 'NIK Karyawan',
                prefixIcon: const Icon(
                  Icons.badge_outlined,
                  color: LoginColors.primaryBlue,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: dobController,
              readOnly: true,
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime(1990),
                  firstDate: DateTime(1950),
                  lastDate: DateTime.now(),
                  builder: (context, child) {
                    return Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: const ColorScheme.light(
                          primary: LoginColors.primaryBlue,
                          onPrimary: Colors.white,
                          onSurface: LoginColors.textDark,
                        ),
                      ),
                      child: child!,
                    );
                  },
                );
                if (picked != null) {
                  selectedDate = picked;
                  dobController.text = DateFormat(
                    'dd MMMM yyyy',
                  ).format(picked);
                }
              },
              decoration: InputDecoration(
                labelText: 'Tanggal Lahir',
                prefixIcon: const Icon(
                  Icons.calendar_today_outlined,
                  color: LoginColors.primaryBlue,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () async {
                  // Logic kirim reset password (copy dari kode asli)
                  final nik = nikController.text.trim();
                  if (nik.isEmpty || selectedDate == null) {
                    _showErrorSnackbar('NIK dan tanggal lahir wajib diisi.');
                    return;
                  }
                  final dobForApi = DateFormat(
                    'yyyy-MM-dd',
                  ).format(selectedDate!);
                  try {
                    await ApiService().post(
                      '/forgot-password',
                      body: {'nik': nik, 'tanggal_lahir': dobForApi},
                    );
                    if (!mounted) return;
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Permintaan reset terkirim.'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    _showErrorSnackbar('Gagal: $e');
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: LoginColors.primaryBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  "Kirim Permintaan",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // --- UI SECTION (PROFESSIONAL & PREMIUM) ---

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: LoginColors.background,
      body: Stack(
        children: [
          Positioned(
            top: -80,
            right: -60,
            child: _buildGlowCircle(180, LoginColors.primaryBlue.withOpacity(0.08)),
          ),
          Positioned(
            bottom: 120,
            left: -60,
            child: _buildGlowCircle(160, LoginColors.accentOrange.withOpacity(0.08)),
          ),
          // 1. Background Curve Decoration (Top)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: size.height * 0.35,
            child: CustomPaint(
              painter: _HeaderCurvePainter(),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    const SizedBox(height: 18),
                    _buildStaggered(
                      0.0,
                      Center(
                        child: Image.asset(
                          'icon/logoputih.png',
                          height: 48,
                          width: 48,
                          errorBuilder: (_, __, ___) => Image.asset(
                            'icon/logoputih.png',
                            height: 36,
                            width: 36,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _buildStaggered(
                      0.06,
                      Center(
                        child: Text(
                          "Time-People-System",
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildStaggered(
                      0.12,
                      Center(
                        child: Image.asset(
                          'animation/Ship.gif',
                          height: 180,
                          width: 320,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 2. Main Login Card
          Positioned(
            top: size.height * 0.30,
            left: 0,
            right: 0,
            bottom: 0,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: LoginColors.surfaceWhite,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: LoginColors.darkBlue.withOpacity(0.08),
                              blurRadius: 24,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Header Login Form
                            _buildStaggered(
                              0.2,
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "Login",
                                    style: GoogleFonts.poppins(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w600,
                                      color: LoginColors.textDark,
                                    ),
                                  ),
                                  if (_canUseBiometric)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: LoginColors.accentOrange
                                            .withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.security,
                                            size: 12,
                                            color: LoginColors.accentOrange,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            "Secured",
                                            style: GoogleFonts.poppins(
                                              fontSize: 10,
                                              color: LoginColors.accentOrange,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (_canUseBiometric)
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 16, bottom: 8),
                                child: _buildStaggered(
                                  0.24,
                                  _buildBiometricQuickAccess(),
                                ),
                              ),
                            const SizedBox(height: 24),

                            // Input Fields
                            _buildStaggered(
                              0.28,
                              _buildPremiumTextField(
                                controller: _usernameController,
                                label: "Username / NIK",
                                icon: Icons.person_rounded,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildStaggered(
                              0.32,
                              _buildPremiumTextField(
                                controller: _passwordController,
                                label: "Password",
                                icon: Icons.lock_rounded,
                                isPassword: true,
                              ),
                            ),

                            const SizedBox(height: 12),
                            _buildStaggered(
                              0.36,
                              Row(
                                children: [
                                  Checkbox(
                                    value: _rememberLogin,
                                    onChanged: (val) {
                                      if (val == null) return;
                                      setState(() => _rememberLogin = val);
                                    },
                                    activeColor: LoginColors.primaryBlue,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      "Ingat login saya",
                                      style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        color: LoginColors.textDark,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Error Message
                            if (_errorMessage != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _errorMessage!,
                                  style: TextStyle(
                                    color: Colors.red.shade800,
                                    fontSize: 12,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],

                            // Forgot Password
                            _buildStaggered(
                              0.4,
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _showForgotPasswordSheet,
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.only(right: 0),
                                    foregroundColor: LoginColors.accentOrange,
                                  ),
                                  child: Text(
                                    "Forgot Password?",
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // LOGIN BUTTON (Blue Gradient)
                            _buildStaggered(
                              0.44,
                              Container(
                                height: 54,
                                decoration: BoxDecoration(
                                  gradient: LoginColors.blueGradient,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: LoginColors.primaryBlue
                                          .withOpacity(0.4),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _signIn,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          height: 24,
                                          width: 24,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              "SIGN IN",
                                              style: GoogleFonts.poppins(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white,
                                                letterSpacing: 1,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            const Icon(
                                              Icons.arrow_forward_rounded,
                                              color: Colors.white,
                                              size: 20,
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 16),

                            // OR DIVIDER
                            if (_canUseBiometric) ...[
                              // Divider OR
                              Row(
                                children: [
                                  const Expanded(
                                    child: Divider(color: Color(0xFFE2E8F0)),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    child: Text(
                                      "OR",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade400,
                                      ),
                                    ),
                                  ),
                                  const Expanded(
                                    child: Divider(color: Color(0xFFE2E8F0)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // BIOMETRIC BUTTON & KETERANGAN
                              Column(
                                children: [
                                  SizedBox(
                                    width: double.infinity,
                                    height: 52,
                                    child: OutlinedButton.icon(
                                      onPressed: _isLoading ? null : _handleBiometricLogin,
                                      icon: const Icon(
                                        Icons.fingerprint_rounded,
                                        size: 26,
                                        color: Colors.deepPurple,
                                      ),
                                      label: Text(
                                        "Login dengan Biometrik",
                                        style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                          color: Colors.deepPurple,
                                        ),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.deepPurple,
                                        side: BorderSide(
                                          color: Colors.deepPurple.withOpacity(0.25),
                                          width: 1.5,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        backgroundColor: Colors.white,
                                        elevation: 0,
                                        shadowColor: Colors.transparent,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    "Akses cepat & aman menggunakan sidik jari atau wajah.",
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: Colors.deepPurple,
                                      fontWeight: FontWeight.w400,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 30),
                      Text(
                        "© 2025 System Integrations with ❤️",
                        style: GoogleFonts.poppins(
                          color: Colors.grey.shade400,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- CUSTOM TEXT FIELD WIDGET ---
  Widget _buildPremiumTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: LoginColors.textLight,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: LoginColors.inputFill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.transparent),
          ),
          child: TextField(
            controller: controller,
            obscureText: isPassword && _obscureText,
            style: GoogleFonts.poppins(
              color: LoginColors.textDark,
              fontWeight: FontWeight.w500,
              fontSize: 15,
            ),
            decoration: InputDecoration(
              hintText: "Enter your ${label.toLowerCase()}",
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
              prefixIcon: Icon(
                icon,
                color: LoginColors.primaryBlue.withOpacity(0.6),
                size: 20,
              ),
              suffixIcon: isPassword
                  ? IconButton(
                      icon: Icon(
                        _obscureText
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        color: Colors.grey.shade400,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscureText = !_obscureText),
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                  color: LoginColors.primaryBlue,
                  width: 1.5,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBiometricQuickAccess() {
    final enabled = _biometricEnabled && _biometricUsername != null;
    final statusColor = enabled ? Colors.green : Colors.orange;
    final subtitle = enabled
        ? 'Biometrik aktif untuk ${_biometricUsername ?? 'akun ini'}.'
        : 'Aktifkan dari menu Profil untuk login tanpa password.';

    return Container(
      decoration: BoxDecoration(
        color: enabled ? Colors.green.withOpacity(0.08) : Colors.orange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  statusColor.withOpacity(0.9),
                  statusColor.withOpacity(0.6),
                ],
              ),
            ),
            child: const Icon(Icons.fingerprint_rounded, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  enabled ? 'Biometric Ready' : 'Biometric Available',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: LoginColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: LoginColors.textLight,
                  ),
                ),
              ],
            ),
          ),
          if (enabled)
            ElevatedButton(
              onPressed: _isLoading ? null : _handleBiometricLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: statusColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text('Masuk'),
            )
          else
            IconButton(
              onPressed: () => _showErrorSnackbar(
                'Aktifkan biometrik dari menu Profil untuk menggunakan fitur ini.',
              ),
              icon: Icon(Icons.info_outline, color: statusColor),
              tooltip: 'Aktifkan biometrik dari profil',
            ),
        ],
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

  Widget _buildStaggered(double start, Widget child) {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: _animController,
        curve: Interval(start, 1.0, curve: Curves.easeOut),
      ),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: _animController,
            curve: Interval(start, 1.0, curve: Curves.easeOutCubic),
          ),
        ),
        child: child,
      ),
    );
  }
}

// --- CUSTOM PAINTER FOR BACKGROUND ---
class _HeaderCurvePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LoginColors.blueGradient.createShader(
        Rect.fromLTWH(0, 0, size.width, size.height),
      )
      ..style = PaintingStyle.fill;

    final path = Path();
    path.lineTo(0, size.height * 0.85);

    // Membuat lengkungan asimetris yang modern
    path.quadraticBezierTo(
      size.width * 0.25,
      size.height,
      size.width * 0.6,
      size.height * 0.85,
    );
    path.quadraticBezierTo(
      size.width * 0.85,
      size.height * 0.75,
      size.width,
      size.height * 0.9,
    );

    path.lineTo(size.width, 0);
    path.close();

    canvas.drawPath(path, paint);

    // Tambahkan lingkaran hiasan transparan (Accent Orange)
    final circlePaint = Paint()
      ..color = LoginColors.accentOrange.withOpacity(0.1)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(size.width * 0.85, size.height * 0.3),
      80,
      circlePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
