import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

import 'account_service.dart';
import 'chat_service.dart';

/// Returns stable product copy for the account-deletion flow.
///
/// Exception messages are retained by the service for diagnostics, but are
/// deliberately not rendered because callable/plugin text can contain
/// implementation details or change without a client release.
String accountDeletionErrorCopy(Object error) {
  return switch (_errorCode(error)) {
    'unauthenticated' => 'Sign in again before requesting account deletion.',
    'permission-denied' =>
      'Your account cannot be deleted from this session. Sign in again and try.',
    'failed-precondition' =>
      'Complete the required study ownership steps before deleting your account.',
    'invalid-argument' =>
      'The deletion request was not accepted. Check your account and try again.',
    'unavailable' || 'deadline-exceeded' =>
      'We could not submit the deletion request. Check your connection and try again.',
    'resource-exhausted' =>
      'Deletion requests are temporarily busy. Please try again shortly.',
    _ => 'We could not submit the account deletion request. Please try again.',
  };
}

/// Returns stable product copy for creating a group invitation.
///
/// This function intentionally keys off typed error codes rather than the
/// exception's message. Server messages remain useful in logs, but must not
/// become an accidental public API or expose Firebase/plugin details.
String groupInviteErrorCopy(Object error) {
  return switch (_errorCode(error)) {
    'unauthenticated' => 'Sign in again before creating an invitation.',
    'permission-denied' =>
      'Only a study owner can create an invitation for this group.',
    'failed-precondition' =>
      'This study is not accepting new members right now.',
    'resource-exhausted' =>
      'This study cannot accept more members right now. Try again later.',
    'invalid-argument' =>
      'Check the invitation options and try creating it again.',
    'not-found' => 'This study is no longer available.',
    'unavailable' || 'deadline-exceeded' =>
      'We could not create the invitation. Check your connection and try again.',
    _ => 'We could not create the invitation. Please try again.',
  };
}

String? _errorCode(Object error) {
  if (error is AccountDeletionException) return error.code;
  if (error is ChatServiceException) return error.code;
  if (error is FirebaseFunctionsException) return error.code;
  if (error is FirebaseException) return error.code;
  return null;
}
