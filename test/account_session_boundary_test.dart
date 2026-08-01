import 'package:bsgc_app/services/account_session_boundary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('advances the session epoch when accounts change', () {
    final boundary = AccountSessionBoundary();

    final signedOut = boundary.observe(null);
    final accountA = boundary.observe('account-a');
    final accountB = boundary.observe('account-b');

    expect(signedOut.generation, 0);
    expect(accountA.generation, 1);
    expect(accountB.generation, 2);
    expect(accountB.widgetKey, isNot(accountA.widgetKey));
    expect(boundary.isCurrent(accountA, uid: 'account-a'), isFalse);
    expect(boundary.isCurrent(accountB, uid: 'account-b'), isTrue);
  });

  test('same-account reauthentication still gets a fresh epoch', () {
    final boundary = AccountSessionBoundary();

    final firstLogin = boundary.observe('account-a');
    boundary.observe(null);
    final secondLogin = boundary.observe('account-a');

    expect(secondLogin.generation, greaterThan(firstLogin.generation));
    expect(boundary.isCurrent(firstLogin, uid: 'account-a'), isFalse);
    expect(boundary.isCurrent(secondLogin, uid: 'account-a'), isTrue);
  });

  test('a stale asynchronous result cannot pass the epoch check', () {
    final boundary = AccountSessionBoundary();

    final accountA = boundary.observe('account-a');
    boundary.observe('account-b');

    expect(boundary.isCurrent(accountA, uid: 'account-a'), isFalse);
    expect(boundary.isCurrent(accountA, uid: 'account-b'), isFalse);
  });
}
