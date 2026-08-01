import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:bsgc_app/services/auth_service.dart';
import 'package:bsgc_app/services/deep_link_service.dart';
import 'package:bsgc_app/services/startup_service.dart';
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

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider()..load(),
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
          home: const _AppStartupGate(),
        );
      },
    );
  }
}

class _AppStartupGate extends StatefulWidget {
  const _AppStartupGate();

  @override
  State<_AppStartupGate> createState() => _AppStartupGateState();
}

class _AppStartupGateState extends State<_AppStartupGate> {
  late final StartupController _controller = StartupController(
    initialize: _initializeEssentialServices,
  )..addListener(_refresh);

  @override
  void initState() {
    super.initState();
    unawaited(_controller.start());
  }

  Future<void> _initializeEssentialServices() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    if (!kIsWeb) {
      final firestore = FirebaseFirestore.instance;
      // Preserve Firestore's local cache so the signed-in shell, groups, and
      // previously loaded study content remain usable without a network.
      firestore.settings = const Settings(persistenceEnabled: true);
      try {
        final crashlytics = FirebaseCrashlytics.instance;
        FlutterError.onError = (details) {
          unawaited(
            crashlytics
                .recordFlutterFatalError(details)
                .catchError(
                  (Object error) =>
                      debugPrint('Crash reporting failed: $error'),
                ),
          );
        };
        PlatformDispatcher.instance.onError = (error, stack) {
          unawaited(
            crashlytics
                .recordError(error, stack, fatal: true)
                .catchError(
                  (Object reportingError) =>
                      debugPrint('Crash reporting failed: $reportingError'),
                ),
          );
          return true;
        };
      } catch (error) {
        debugPrint('Crash reporting initialization failed: $error');
      }
    }
    unawaited(
      DeepLinkService()
          .init()
          .timeout(const Duration(seconds: 5))
          .catchError(
            (Object error) =>
                debugPrint('Deep-link initialization failed: $error'),
          ),
    );
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return switch (_controller.status) {
      StartupStatus.ready => const AuthWrapper(),
      StartupStatus.failed => _StartupErrorScreen(onRetry: _controller.retry),
      _ => const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.gradientEnd),
        ),
      ),
    };
  }
}

class _StartupErrorScreen extends StatelessWidget {
  final Future<void> Function() onRetry;

  const _StartupErrorScreen({required this.onRetry});

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
                    'Braid could not initialize its secure local session. '
                    'Check your connection and try again. Your local drafts '
                    'have not been changed.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try again'),
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
  late Stream<User?> _authStream;
  Timer? _authTimeout;
  bool _hasReceivedData = false;
  Widget? _lastScreen;
  Object? _authError;

  @override
  void initState() {
    super.initState();
    _subscribeToAuth();
  }

  void _subscribeToAuth() {
    _authStream = AuthService().userStream;
    _authError = null;
    _authTimeout?.cancel();
    _authTimeout = Timer(const Duration(seconds: 12), () {
      if (mounted && !_hasReceivedData) {
        setState(() => _authError = TimeoutException('Auth state timed out.'));
      }
    });
  }

  void _retryAuth() {
    setState(() {
      _hasReceivedData = false;
      _lastScreen = null;
      _subscribeToAuth();
    });
  }

  @override
  void dispose() {
    _authTimeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          _authError = snapshot.error;
        }
        if (snapshot.hasData || snapshot.data != null) {
          _authTimeout?.cancel();
          _authError = null;
          _hasReceivedData = true;
          _lastScreen = const UserDataWrapper();
        } else if (snapshot.connectionState == ConnectionState.active &&
            !snapshot.hasData) {
          _authTimeout?.cancel();
          _authError = null;
          _hasReceivedData = true;
          _lastScreen = const FoyerScreen();
        }

        if (_authError != null) {
          return _AuthLoadErrorScreen(onRetry: _retryAuth);
        }
        if (!_hasReceivedData) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: AppColors.gradientEnd),
            ),
          );
        }

        return _lastScreen ?? const FoyerScreen();
      },
    );
  }
}

class _AuthLoadErrorScreen extends StatelessWidget {
  final VoidCallback onRetry;

  const _AuthLoadErrorScreen({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_clock_outlined, size: 52),
                const SizedBox(height: 18),
                Text(
                  'Your session could not be checked',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Reconnect and try again. Braid will not open another '
                  'account’s cached session.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
