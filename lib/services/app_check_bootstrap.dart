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
