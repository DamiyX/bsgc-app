import 'dart:async';

/// The maximum time an Insight mutation may keep a user action pending.
///
/// Firestore acknowledgement and callable writes both use this boundary so a
/// network that never resolves cannot leave a reaction, save, or comment form
/// disabled forever. Callers still receive the timeout error and can present
/// their existing retry/rollback state.
const insightMutationTimeout = Duration(seconds: 8);

Future<T> awaitInsightMutation<T>(
  Future<T> operation, {
  Duration timeout = insightMutationTimeout,
}) {
  return operation.timeout(timeout);
}
