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
import 'package:provider/provider.dart';
import 'package:bsgc_app/providers/theme_provider.dart';
import 'package:workmanager/workmanager.dart';
import 'package:bsgc_app/services/backup_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      final backupService = BackupService();
      await backupService.backupToGoogleDrive(isBackground: true);
    } catch (err) {
      debugPrint("Background backup error: $err");
      return Future.value(false);
    }
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
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

  if (!kIsWeb) {
    try {
      Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: false,
      );
      Workmanager().registerPeriodicTask(
        "1",
        "dailyBackupTask",
        frequency: const Duration(days: 1),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
        ),
      );
    } catch (e) {
      debugPrint('Failed to initialize Workmanager: $e');
    }
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const BraidApp(),
    ),
  );
}

class BraidApp extends StatelessWidget {
  const BraidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          title: 'Braid',
          debugShowCheckedModeBanner: false,
          theme: appTheme,
          darkTheme: darkAppTheme,
          themeMode: themeProvider.themeMode,
          home: const AuthWrapper(),
        );
      },
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
            body: Center(child: CircularProgressIndicator(color: AppColors.gradientEnd)),
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

