import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum InviteFailureDisposition { terminal, retryable }

InviteFailureDisposition classifyInviteFailure(String code) {
  return switch (code) {
    'not-found' ||
    'deadline-exceeded' ||
    'failed-precondition' ||
    'resource-exhausted' ||
    'permission-denied' => InviteFailureDisposition.terminal,
    _ => InviteFailureDisposition.retryable,
  };
}

/// Accepts only Braid's canonical, opaque group-invite links.
///
/// The token is persisted so a link survives authentication, onboarding, an
/// app restart, or a temporary loss of connectivity. It is removed only after
/// the server confirms successful redemption.
class DeepLinkService {
  static const _pendingInviteKey = 'pending_group_invite_token';
  static final RegExp _inviteTokenPattern = RegExp(r'^[A-Za-z0-9_-]{40,128}$');

  static final DeepLinkService _instance = DeepLinkService._internal();

  factory DeepLinkService() => _instance;

  DeepLinkService._internal();

  final AppLinks _appLinks = AppLinks();
  final ValueNotifier<String?> pendingInviteToken = ValueNotifier(null);
  StreamSubscription<Uri>? _linkSubscription;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final preferences = await SharedPreferences.getInstance();
    pendingInviteToken.value = preferences.getString(_pendingInviteKey);

    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        await handleIncomingLink(initialUri);
      }

      _linkSubscription = _appLinks.uriLinkStream.listen(
        (uri) => unawaited(handleIncomingLink(uri)),
        onError: (Object error, StackTrace stackTrace) {
          if (kDebugMode) {
            debugPrint('Deep-link stream failed: $error');
          }
        },
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Deep-link initialization failed: $error');
      }
    }
  }

  @visibleForTesting
  static String? inviteTokenFromUri(Uri uri) {
    if (uri.scheme != 'https' || uri.host.toLowerCase() != 'braidapp.com') {
      return null;
    }
    if (uri.pathSegments.length != 2 || uri.pathSegments.first != 'join') {
      return null;
    }

    final token = uri.pathSegments[1];
    return _inviteTokenPattern.hasMatch(token) ? token : null;
  }

  Future<bool> handleIncomingLink(Uri uri) async {
    final token = inviteTokenFromUri(uri);
    if (token == null) return false;

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_pendingInviteKey, token);
    pendingInviteToken.value = token;
    return true;
  }

  Future<String?> getPendingInviteToken() async {
    final inMemoryToken = pendingInviteToken.value;
    if (inMemoryToken != null) return inMemoryToken;

    final preferences = await SharedPreferences.getInstance();
    final persistedToken = preferences.getString(_pendingInviteKey);
    pendingInviteToken.value = persistedToken;
    return persistedToken;
  }

  Future<void> clearPendingInviteToken(String redeemedToken) async {
    final currentToken = await getPendingInviteToken();
    if (currentToken != redeemedToken) return;

    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_pendingInviteKey);
    pendingInviteToken.value = null;
  }

  Future<void> dispose() async {
    await _linkSubscription?.cancel();
    pendingInviteToken.dispose();
  }
}
