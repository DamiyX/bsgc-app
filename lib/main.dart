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
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:bsgc_app/services/notification_service.dart';

import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:provider/provider.dart';
import 'package:bsgc_app/providers/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  Object? startupError;

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    
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

    await Future.wait([
      BibleService().init().catchError(
        (Object error) =>
            debugPrint('Bible data initialization failed: $error'),
      ),
      DeepLinkService().init().catchError(
        (Object error) =>
            debugPrint('Deep-link initialization failed: $error'),
      ),
    ]);
  } catch (error, stackTrace) {
    startupError = error;
    debugPrint('Braid startup failed: $error\n$stackTrace');
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(prefs),
      child: BraidApp(startupError: startupError),
    ),
  );
}

class BraidApp extends StatelessWidget {
  final Object? startupError;

  const BraidApp({super.key, this.startupError});

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
          home: startupError == null
              ? const AuthWrapper()
              : const _StartupErrorScreen(),
        );
      },
    );
  }
}

class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 54,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Braid could not start',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Close and reopen the app. If this continues, install the '
                    'latest version or contact Braid support. Your local study '
                    'data has not been changed.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  late final Stream<User?> _authStream;
  bool _hasReceivedData = false;
  Widget? _lastScreen;

  @override
  void initState() {
    super.initState();
    _authStream = AuthService().userStream;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authStream,
      builder: (context, snapshot) {
        if (snapshot.hasData || snapshot.data != null) {
          _hasReceivedData = true;
          _lastScreen = const UserDataWrapper();
        } else if (snapshot.connectionState == ConnectionState.active && !snapshot.hasData) {
          _hasReceivedData = true;
          _lastScreen = const FoyerScreen();
        }

        if (!_hasReceivedData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: AppColors.gradientEnd)),
          );
        }

        return _lastScreen ?? const FoyerScreen();
      },
    );
  }
}

