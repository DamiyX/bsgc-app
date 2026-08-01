import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

enum BraidEnvironment { local, staging, production }

enum AppCheckProviderKind {
  debug,
  playIntegrity,
  appAttestWithDeviceCheckFallback,
}

class AppCheckBootstrapPlan {
  final BraidEnvironment environment;
  final AppCheckProviderKind androidProvider;
  final AppCheckProviderKind appleProvider;
  final bool enforcementEligible;

  const AppCheckBootstrapPlan({
    required this.environment,
    required this.androidProvider,
    required this.appleProvider,
    required this.enforcementEligible,
  });
}

typedef AppCheckActivator = Future<void> Function(AppCheckBootstrapPlan plan);

/// The compile-time environment used by the App Check provider selection.
///
/// Local builds intentionally use the debug provider. Release workflows must
/// pass `--dart-define=BRAID_ENV=staging` or
/// `--dart-define=BRAID_ENV=production` explicitly; no debug token is stored
/// in this repository.
const String braidEnvironmentDefine = String.fromEnvironment(
  'BRAID_ENV',
  defaultValue: 'local',
);

class AppCheckUnsupportedPlatformException implements Exception {
  final BraidEnvironment environment;
  final TargetPlatform platform;

  const AppCheckUnsupportedPlatformException({
    required this.environment,
    required this.platform,
  });

  @override
  String toString() {
    return 'Firebase App Check is not configured for $platform in the '
        '${environment.name} environment. This mobile release supports '
        'Android (Play Integrity/debug) and Apple (App Attest with Device '
        'Check fallback/debug). Configure an explicit web provider before '
        'enabling web enforcement.';
  }
}

class AppCheckActivationException implements Exception {
  final AppCheckBootstrapPlan plan;
  final Object cause;

  const AppCheckActivationException({required this.plan, required this.cause});

  @override
  String toString() {
    return 'Firebase App Check activation failed for '
        '${plan.environment.name}: $cause';
  }
}

BraidEnvironment braidEnvironmentFromDefine(String value) {
  return switch (value.trim().toLowerCase()) {
    'production' => BraidEnvironment.production,
    'staging' => BraidEnvironment.staging,
    _ => BraidEnvironment.local,
  };
}

AppCheckBootstrapPlan appCheckPlanFor(BraidEnvironment environment) {
  if (environment == BraidEnvironment.local) {
    return const AppCheckBootstrapPlan(
      environment: BraidEnvironment.local,
      androidProvider: AppCheckProviderKind.debug,
      appleProvider: AppCheckProviderKind.debug,
      enforcementEligible: false,
    );
  }
  return AppCheckBootstrapPlan(
    environment: environment,
    androidProvider: AppCheckProviderKind.playIntegrity,
    appleProvider: AppCheckProviderKind.appAttestWithDeviceCheckFallback,
    // Eligibility still requires observed staging metrics and an operator
    // decision. The source plan alone never enables backend enforcement.
    enforcementEligible: false,
  );
}

Future<AppCheckBootstrapPlan> bootstrapAppCheck({
  required String environmentDefine,
  required AppCheckActivator activate,
}) async {
  final plan = appCheckPlanFor(braidEnvironmentFromDefine(environmentDefine));
  await activate(plan);
  return plan;
}

/// Activates the official FlutterFire App Check plugin for the selected
/// environment. This must run after `Firebase.initializeApp()` and before any
/// other Firebase service is used.
Future<AppCheckBootstrapPlan> activateConfiguredAppCheck({
  String environmentDefine = braidEnvironmentDefine,
}) {
  return bootstrapAppCheck(
    environmentDefine: environmentDefine,
    activate: activateFirebaseAppCheck,
  );
}

Future<void> activateFirebaseAppCheck(AppCheckBootstrapPlan plan) async {
  if (kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS &&
          defaultTargetPlatform != TargetPlatform.macOS)) {
    throw AppCheckUnsupportedPlatformException(
      environment: plan.environment,
      platform: defaultTargetPlatform,
    );
  }

  try {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: switch (plan.androidProvider) {
        AppCheckProviderKind.debug => const AndroidDebugProvider(),
        AppCheckProviderKind.playIntegrity =>
          const AndroidPlayIntegrityProvider(),
        AppCheckProviderKind.appAttestWithDeviceCheckFallback =>
          const AndroidPlayIntegrityProvider(),
      },
      providerApple: switch (plan.appleProvider) {
        AppCheckProviderKind.debug => const AppleDebugProvider(),
        AppCheckProviderKind.playIntegrity =>
          const AppleAppAttestWithDeviceCheckFallbackProvider(),
        AppCheckProviderKind.appAttestWithDeviceCheckFallback =>
          const AppleAppAttestWithDeviceCheckFallbackProvider(),
      },
    );
  } catch (error, stackTrace) {
    Error.throwWithStackTrace(
      AppCheckActivationException(plan: plan, cause: error),
      stackTrace,
    );
  }
}
