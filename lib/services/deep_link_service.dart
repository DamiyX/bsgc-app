import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  Future<void> init() async {
    try {
      // Check for initial link if the app was closed and opened via a link
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        await _handleIncomingLink(initialUri);
      }

      // Listen for links while the app is in the background or foreground
      _linkSubscription = _appLinks.uriLinkStream.listen((Uri? uri) {
        if (uri != null) {
          _handleIncomingLink(uri);
        }
      }, onError: (err) {
        if (kDebugMode) print('Error listening to deep links: $err');
      });
    } catch (e) {
      if (kDebugMode) print('Error initializing DeepLinkService: $e');
    }
  }

  Future<void> _handleIncomingLink(Uri uri) async {
    if (kDebugMode) print('Received Deep Link: $uri');
    
    // Check if it's an invite link
    if (uri.path.contains('/invite')) {
      final inviterId = uri.queryParameters['inviter'];
      if (inviterId != null && inviterId.isNotEmpty) {
        if (kDebugMode) print('Found inviter ID in link: $inviterId');
        
        // Save the inviter ID to SharedPreferences so we can use it during onboarding
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('pending_inviter_id', inviterId);
      }
    }
  }

  void dispose() {
    _linkSubscription?.cancel();
  }
}
