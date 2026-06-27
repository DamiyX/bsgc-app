import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:bsgc_app/services/auth_service.dart';
import 'package:bsgc_app/services/bible_service.dart';
import 'package:bsgc_app/screens/foyer_screen.dart';
import 'package:bsgc_app/screens/main_hall_screen.dart';
import 'package:bsgc_app/theme.dart';
import 'package:bsgc_app/firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await BibleService().init();
  runApp(const BSGCApp());
}

class BSGCApp extends StatelessWidget {
  const BSGCApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BSGC',
      debugShowCheckedModeBanner: false,
      theme: appTheme,
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService().userStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }
        if (snapshot.hasData) {
          return const MainHallScreen();
        }
        return const FoyerScreen();
      },
    );
  }
}
