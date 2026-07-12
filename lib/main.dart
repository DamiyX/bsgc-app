import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:bsgc_app/services/auth_service.dart';
import 'package:bsgc_app/services/bible_service.dart';
import 'package:bsgc_app/services/deep_link_service.dart';
import 'package:bsgc_app/screens/foyer_screen.dart';
import 'package:bsgc_app/widgets/user_data_wrapper.dart';
import 'package:bsgc_app/theme.dart';
import 'package:bsgc_app/firebase_options.dart';

import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint('Failed to load .env file: $e');
  }
  
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    
    if (!kIsWeb) {
      // Pass all uncaught "fatal" errors from the framework to Crashlytics
      FlutterError.onError =
          FirebaseCrashlytics.instance.recordFlutterFatalError;

      // Pass all uncaught asynchronous errors that aren't handled by the Flutter framework to Crashlytics
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    }
  } catch (e) {
    debugPrint('Failed to initialize Crashlytics: $e');
  }

  try {
    await BibleService().init();
  } catch (e) {
    debugPrint('Failed to initialize BibleService: $e');
  }

  try {
    await DeepLinkService().init();
  } catch (e) {
    debugPrint('Failed to initialize DeepLinkService: $e');
  }

  runApp(const BraidApp());
}

class BraidApp extends StatelessWidget {
  const BraidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Braid',
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
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          return const UserDataWrapper();
        }
        return const FoyerScreen();
      },
    );
  }
}
