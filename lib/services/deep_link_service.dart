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
  Future<void>? _initialization;
  Future<void> _pendingInviteOperationTail = Future<void>.value();

  Future<void> init() {
    final existingInitialization = _initialization;
    if (existingInitialization != null) return existingInitialization;

    final completer = Completer<void>();
    _initialization = completer.future;
    unawaited(_runInitialization(completer));
    return completer.future;
  }

  Future<void> _runInitialization(Completer<void> completer) async {
    try {
      await _linkSubscription?.cancel();
      _linkSubscription = null;

      await _enqueuePendingInviteOperation(() async {
        final preferences = await SharedPreferences.getInstance();
        pendingInviteToken.value = preferences.getString(_pendingInviteKey);
      });

      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        await handleIncomingLink(initialUri);
      }

      _linkSubscription = _appLinks.uriLinkStream.listen(
        (uri) => unawaited(_handleIncomingLinkSafely(uri)),
        onError: (Object error, StackTrace stackTrace) {
          if (kDebugMode) {
            debugPrint('Deep-link stream failed: $error');
          }
        },
      );
      completer.complete();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Deep-link initialization failed: $error');
      }
      try {
        await _linkSubscription?.cancel();
      } catch (cancelError) {
        if (kDebugMode) {
          debugPrint('Deep-link subscription cleanup failed: $cancelError');
        }
      }
      _linkSubscription = null;
      if (identical(_initialization, completer.future)) {
        _initialization = null;
      }
      // Initialization is intentionally best-effort. A later init call can
      // retry after a transient platform or storage failure.
      completer.complete();
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

  Future<bool> handleIncomingLink(Uri uri) {
    final token = inviteTokenFromUri(uri);
    if (token == null) return Future<bool>.value(false);

    return _enqueuePendingInviteOperation(() async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_pendingInviteKey, token);
      pendingInviteToken.value = token;
      return true;
    });
  }

  Future<String?> getPendingInviteToken() {
    return _enqueuePendingInviteOperation(_readPendingInviteToken);
  }

  Future<void> clearPendingInviteToken(String redeemedToken) {
    return _enqueuePendingInviteOperation(() async {
      final currentToken = await _readPendingInviteToken();
      if (currentToken != redeemedToken) return;

      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(_pendingInviteKey);
      pendingInviteToken.value = null;
    });
  }

  Future<String?> _readPendingInviteToken() async {
    final inMemoryToken = pendingInviteToken.value;
    if (inMemoryToken != null) return inMemoryToken;

    final preferences = await SharedPreferences.getInstance();
    final persistedToken = preferences.getString(_pendingInviteKey);
    pendingInviteToken.value = persistedToken;
    return persistedToken;
  }

  Future<void> _handleIncomingLinkSafely(Uri uri) async {
    try {
      await handleIncomingLink(uri);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Deep-link persistence failed: $error');
      }
    }
  }

  Future<T> _enqueuePendingInviteOperation<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _pendingInviteOperationTail = _pendingInviteOperationTail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> dispose() async {
    await _linkSubscription?.cancel();
    pendingInviteToken.dispose();
  }
}
