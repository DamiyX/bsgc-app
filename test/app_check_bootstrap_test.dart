import 'package:bsgc_app/services/app_check_bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('debug providers are local-only', () {
    final local = appCheckPlanFor(BraidEnvironment.local);
    final staging = appCheckPlanFor(BraidEnvironment.staging);
    final production = appCheckPlanFor(BraidEnvironment.production);

    expect(local.androidProvider, AppCheckProviderKind.debug);
    expect(local.appleProvider, AppCheckProviderKind.debug);
    expect(staging.androidProvider, AppCheckProviderKind.playIntegrity);
    expect(
      staging.appleProvider,
      AppCheckProviderKind.appAttestWithDeviceCheckFallback,
    );
    expect(production.androidProvider, AppCheckProviderKind.playIntegrity);
    expect(production.enforcementEligible, isFalse);
  });

  test('bootstrap uses an injectable activation boundary', () async {
    AppCheckBootstrapPlan? activated;
    final plan = await bootstrapAppCheck(
      environmentDefine: 'staging',
      activate: (value) async => activated = value,
    );
    expect(activated, same(plan));
    expect(plan.environment, BraidEnvironment.staging);
  });

}
