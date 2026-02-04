import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:gtime/screens/splash_screen.dart';
import 'package:gtime/theme.dart';
import 'package:gtime/services/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await PushService.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shitcorner Premium',
      theme: premiumTheme,
      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
