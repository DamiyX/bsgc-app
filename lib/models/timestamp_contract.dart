import 'package:cloud_firestore/cloud_firestore.dart';

/// Stable ordering value used when a legacy document has no usable timestamp.
///
/// A compatibility reader must not use the current wall clock for historical
/// data: every rebuild would move the malformed record to a different place.
final stableTimestampEpoch = DateTime.fromMillisecondsSinceEpoch(
  0,
  isUtc: true,
);

class ResolvedTimestamp {
  final DateTime value;
  final bool isKnown;

  const ResolvedTimestamp({required this.value, required this.isKnown});
}

ResolvedTimestamp resolveFirestoreTimestamp(dynamic value) {
  if (value is Timestamp) {
    return ResolvedTimestamp(value: value.toDate(), isKnown: true);
  }
  if (value is DateTime) {
    return ResolvedTimestamp(value: value, isKnown: true);
  }
  return ResolvedTimestamp(value: stableTimestampEpoch, isKnown: false);
}
