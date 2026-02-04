import 'dart:async';
import 'dart:developer';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

class PushService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static StreamSubscription<RemoteMessage>? _foregroundMessageSub;

  /// Inisialisasi FCM, minta izin, ambil token, dan kirim ke server
  static Future<void> init() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      log('FCM permission: ${settings.authorizationStatus}');

      final token = await _messaging.getToken();
      if (token != null) {
        await _persistAndSendToken(token);
      }

      _messaging.onTokenRefresh.listen((newToken) async {
        await _persistAndSendToken(newToken);
      });

      _listenForegroundNotifications();
    } catch (e) {
      log('FCM init error: $e');
    }
  }

  /// Dipanggil setelah login berhasil untuk memastikan token dikirim
  static Future<void> syncTokenAfterLogin() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await _persistAndSendToken(token, forceSend: true);
      }
    } catch (e) {
      log('FCM sync error: $e');
    }
  }

  static Future<void> _persistAndSendToken(
    String token, {
    bool forceSend = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('fcm_token');
    if (cached == token && !forceSend) return;

    await prefs.setString('fcm_token', token);

    final authToken = prefs.getString('auth_token');
    if (authToken == null || authToken.isEmpty) return;

    try {
      await ApiService().post(
        '/api/user/fcm-token',
        body: {'token': token},
        token: authToken,
      );
      log('FCM token sent to server');
    } catch (e) {
      log('FCM send error: $e');
    }
  }

  static void _listenForegroundNotifications() {
    _foregroundMessageSub ??= FirebaseMessaging.onMessage.listen(
      (message) async {
        await _triggerVibrationFeedback();
        log('FCM foreground message received: ${message.messageId ?? 'no-id'}');
      },
      onError: (error, stackTrace) {
        log('FCM onMessage error: $error');
      },
    );
  }

  static Future<void> _triggerVibrationFeedback() async {
    try {
      await HapticFeedback.heavyImpact();
    } catch (e) {
      log('Haptic feedback failed: $e');
    }
  }

  static Future<void> dispose() async {
    await _foregroundMessageSub?.cancel();
    _foregroundMessageSub = null;
  }
}
