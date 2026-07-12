import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart';

class PushNotificationSender {
  static const String _projectId = 'bsgc-app';

  static const Map<String, dynamic> _serviceAccountJson = {
    "type": "service_account",
    "project_id": "bsgc-app",
    "private_key_id": "YOUR_PRIVATE_KEY_ID_HERE",
    "private_key": "YOUR_PRIVATE_KEY_HERE",
    "client_email": "braid-push-notifications@bsgc-app.iam.gserviceaccount.com",
    "client_id": "114447050610643892949",
    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
    "token_uri": "https://oauth2.googleapis.com/token",
    "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
    "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/braid-push-notifications%40bsgc-app.iam.gserviceaccount.com",
    "universe_domain": "googleapis.com"
  };

  static final List<String> _scopes = [
    'https://www.googleapis.com/auth/firebase.messaging',
  ];

  static Future<String?> _getAccessToken() async {
    try {
      if (_serviceAccountJson['project_id'] == 'YOUR_PROJECT_ID_HERE') {
        if (kDebugMode) print('Service account JSON not configured yet.');
        return null;
      }

      final accountCredentials = ServiceAccountCredentials.fromJson(_serviceAccountJson);
      final client = http.Client();
      
      final accessCredentials = await obtainAccessCredentialsViaServiceAccount(
        accountCredentials,
        _scopes,
        client,
      );
      
      client.close();
      return accessCredentials.accessToken.data;
    } catch (e) {
      if (kDebugMode) print('Error getting access token: $e');
      return null;
    }
  }

  static Future<void> sendPushNotification({
    required String fcmToken,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    try {
      final accessToken = await _getAccessToken();
      if (accessToken == null) return;

      final String endpoint = 'https://fcm.googleapis.com/v1/projects/$_projectId/messages:send';

      final Map<String, dynamic> message = {
        'message': {
          'token': fcmToken,
          'notification': {
            'title': title,
            'body': body,
          },
          'data': data ?? {},
        }
      };

      final response = await http.post(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(message),
      );

      if (response.statusCode == 200) {
        if (kDebugMode) print('Push notification sent successfully');
      } else {
        if (kDebugMode) print('Failed to send push notification: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      if (kDebugMode) print('Error sending push notification: $e');
    }
  }
}
