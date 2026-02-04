import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';
import './login_screen.dart';
import 'package:gtime/services/biometric_service.dart';
import 'package:google_fonts/google_fonts.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _word1Controller;
  late AnimationController _word2Controller;
  late AnimationController _word3Controller;
  
  late Animation<double> _word1Opacity;
  late Animation<double> _word1Scale;
  late Animation<Offset> _word1Slide;
  
  late Animation<double> _word2Opacity;
  late Animation<double> _word2Scale;
  late Animation<Offset> _word2Slide;
  
  late Animation<double> _word3Opacity;
  late Animation<double> _word3Scale;
  late Animation<Offset> _word3Slide;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _startAnimationSequence();
    _checkSession();
  }

  void _setupAnimations() {
    // Word 1: "Time" - Start immediately
    _word1Controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _word1Opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _word1Controller, curve: Curves.easeOut),
    );
    _word1Scale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _word1Controller, curve: Curves.elasticOut),
    );
    _word1Slide = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _word1Controller, curve: Curves.easeOut));

    // Word 2: "People"
    _word2Controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _word2Opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _word2Controller, curve: Curves.easeOut),
    );
    _word2Scale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _word2Controller, curve: Curves.elasticOut),
    );
    _word2Slide = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _word2Controller, curve: Curves.easeOut));

    // Word 3: "System"
    _word3Controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _word3Opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _word3Controller, curve: Curves.easeOut),
    );
    _word3Scale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _word3Controller, curve: Curves.elasticOut),
    );
    _word3Slide = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _word3Controller, curve: Curves.easeOut));
  }

  Future<void> _startAnimationSequence() async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    _word1Controller.forward();
    
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    _word2Controller.forward();
    
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    _word3Controller.forward();
  }

  @override
  void dispose() {
    _word1Controller.dispose();
    _word2Controller.dispose();
    _word3Controller.dispose();
    super.dispose();
  }

  // --- LOGIC SESSION (TIDAK BERUBAH) ---
  Future<void> _checkSession() async {
    // Tunggu durasi splash (minimal 2.5 detik agar animasi selesai & user lihat branding)
    await Future.delayed(const Duration(milliseconds: 2500));

    if (!mounted) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('auth_token');
      final bool biometricEnabled = prefs.getBool('biometric_enabled') ?? false;

      if (token != null && token.isNotEmpty && biometricEnabled) {
        final ok = await BiometricService.authenticate();
        if (!mounted) return;
        if (ok) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
          return;
        }
      }

      if (!mounted) return;
      if (token != null && token.isNotEmpty) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF1976D2),
              Color(0xFF0D47A1),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // App logo
              AnimatedBuilder(
                animation: _word1Controller,
                builder: (context, child) {
                  return Opacity(
                    opacity: _word1Opacity.value,
                    child: Transform.scale(
                      scale: _word1Scale.value,
                      child: Image.asset(
                        'icon/logoapps.png',
                        width: 120,
                        height: 120,
                        fit: BoxFit.contain,
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 24),

              // Word 1: "Time"
              AnimatedBuilder(
                animation: _word1Controller,
                builder: (context, child) {
                  return Opacity(
                    opacity: _word1Opacity.value,
                    child: Transform.scale(
                      scale: _word1Scale.value,
                      child: SlideTransition(
                        position: _word1Slide,
                        child: Text(
                          'Time',
                          style: GoogleFonts.poppins(
                            fontSize: 56,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 2,
                            shadows: [
                              Shadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              
              const SizedBox(height: 16),
              
              // Word 2: "People"
              AnimatedBuilder(
                animation: _word2Controller,
                builder: (context, child) {
                  return Opacity(
                    opacity: _word2Opacity.value,
                    child: Transform.scale(
                      scale: _word2Scale.value,
                      child: SlideTransition(
                        position: _word2Slide,
                        child: Text(
                          'People',
                          style: GoogleFonts.poppins(
                            fontSize: 56,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 2,
                            shadows: [
                              Shadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              
              const SizedBox(height: 16),
              
              // Word 3: "System"
              AnimatedBuilder(
                animation: _word3Controller,
                builder: (context, child) {
                  return Opacity(
                    opacity: _word3Opacity.value,
                    child: Transform.scale(
                      scale: _word3Scale.value,
                      child: SlideTransition(
                        position: _word3Slide,
                        child: Text(
                          'System',
                          style: GoogleFonts.poppins(
                            fontSize: 56,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 2,
                            shadows: [
                              Shadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              
              const SizedBox(height: 60),
              
              // Loading indicator
              AnimatedBuilder(
                animation: _word3Controller,
                builder: (context, child) {
                  return Opacity(
                    opacity: _word3Opacity.value,
                    child: const SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        strokeWidth: 3.0,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                      ),
                    ),
                  );
                },
              ),
              
              const SizedBox(height: 40),
              
              // Copyright
              AnimatedBuilder(
                animation: _word3Controller,
                builder: (context, child) {
                  return Opacity(
                    opacity: _word3Opacity.value,
                    child: Text(
                      '© 2025 G-TIME System',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
