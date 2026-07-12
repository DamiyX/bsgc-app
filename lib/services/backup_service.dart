import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}

class BackupService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveFileScope],
  );

  Future<void> backupToGoogleDrive() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    // 1. Gather all user data from Firestore
    Map<String, dynamic> backupData = {};
    
    // Get Notes
    final notesQuery = await _firestore.collection('notes').where('authorUid', isEqualTo: user.uid).get();
    backupData['notes'] = notesQuery.docs.map((doc) => doc.data()).toList();

    // Get Saved Insights
    final insightsQuery = await _firestore.collection('users').doc(user.uid).collection('savedInsights').get();
    backupData['savedInsights'] = insightsQuery.docs.map((doc) => doc.data()).toList();

    // We can also get user's profile info
    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    if (userDoc.exists) {
      backupData['profile'] = userDoc.data();
    }

    // 2. Write to local temp file
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/braid_backup.json');
    await file.writeAsString(jsonEncode(backupData));

    // 3. Upload to Google Drive
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
    if (googleUser == null) throw Exception('Google Sign In failed');

    final authHeaders = await googleUser.authHeaders;
    final authenticateClient = GoogleAuthClient(authHeaders);
    final driveApi = drive.DriveApi(authenticateClient);

    // Check if backup already exists
    final fileList = await driveApi.files.list(q: "name = 'braid_backup.json' and trashed = false");
    String? fileId;
    if (fileList.files != null && fileList.files!.isNotEmpty) {
      fileId = fileList.files!.first.id;
    }

    final driveFile = drive.File()..name = 'braid_backup.json';
    final media = drive.Media(file.openRead(), file.lengthSync());

    if (fileId != null) {
      await driveApi.files.update(driveFile, fileId, uploadMedia: media);
    } else {
      await driveApi.files.create(driveFile, uploadMedia: media);
    }
  }

  Future<void> restoreFromGoogleDrive() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
    if (googleUser == null) throw Exception('Google Sign In failed');

    final authHeaders = await googleUser.authHeaders;
    final authenticateClient = GoogleAuthClient(authHeaders);
    final driveApi = drive.DriveApi(authenticateClient);

    final fileList = await driveApi.files.list(q: "name = 'braid_backup.json' and trashed = false");
    if (fileList.files == null || fileList.files!.isEmpty) {
      throw Exception('No backup found in your Google Drive');
    }

    final fileId = fileList.files!.first.id!;
    final drive.Media media = await driveApi.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
    
    List<int> dataStore = [];
    await for (var data in media.stream) {
      dataStore.addAll(data);
    }
    
    final jsonString = utf8.decode(dataStore);
    final backupData = jsonDecode(jsonString) as Map<String, dynamic>;

    // Restore Notes
    if (backupData['notes'] != null) {
      for (var note in backupData['notes']) {
        await _firestore.collection('notes').doc(note['id']).set(note, SetOptions(merge: true));
      }
    }

    // Restore Saved Insights
    if (backupData['savedInsights'] != null) {
      for (var insight in backupData['savedInsights']) {
        await _firestore.collection('users').doc(user.uid).collection('savedInsights').doc(insight['id']).set(insight, SetOptions(merge: true));
      }
    }
    
    // Restore Profile
    if (backupData['profile'] != null) {
       await _firestore.collection('users').doc(user.uid).set(backupData['profile'], SetOptions(merge: true));
    }
  }
}
