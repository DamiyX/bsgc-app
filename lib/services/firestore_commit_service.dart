import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Completes only after Firestore reports that a write has reached the server.
///
/// This prevents a local, memory-only mutation from being presented as a
/// durable save when the app is offline.
Future<void> waitForCommitAcknowledgement(
  Stream<bool> pendingStates, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final acknowledgement = Completer<void>();
  late final StreamSubscription<bool> subscription;
  subscription = pendingStates.listen((hasPendingWrites) {
    if (!hasPendingWrites && !acknowledgement.isCompleted) {
      acknowledgement.complete();
    }
  }, onError: acknowledgement.completeError);
  try {
    await acknowledgement.future.timeout(timeout);
  } finally {
    await subscription.cancel();
  }
}

Future<void> waitForDocumentCommit(
  DocumentReference<Map<String, dynamic>> reference, {
  Duration timeout = const Duration(seconds: 8),
}) {
  return waitForCommitAcknowledgement(
    reference
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) => snapshot.metadata.hasPendingWrites),
    timeout: timeout,
  );
}
