import 'dart:io';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';

class AudioService {
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  String? _recordingPath;
  DateTime? _recordingStartTime;

  Future<bool> startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getApplicationDocumentsDirectory();
        final fileName = '${const Uuid().v4()}.m4a';
        _recordingPath = '${dir.path}/$fileName';
        
        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: _recordingPath!,
        );
        _recordingStartTime = DateTime.now();
        return true;
      }
    } catch (e) {
      print('Error starting recording: $e');
    }
    return false;
  }

  Future<String?> stopRecording() async {
    return await _audioRecorder.stop();
  }

  Future<Map<String, dynamic>?> uploadRecording(String path) async {
    try {
      File file = File(path);
      
      if (!await file.exists()) {
        throw Exception("Local audio file missing before upload.");
      }

      // Convert audio bytes to Base64 string
      final bytes = await file.readAsBytes();
      final base64String = base64Encode(bytes);
      
      int duration = _recordingStartTime != null 
          ? DateTime.now().difference(_recordingStartTime!).inSeconds 
          : 0;
      
      if (duration < 1) duration = 1; // Guarantee at least 1 second

      // Clean up local file
      if (await file.exists()) {
        await file.delete();
      }
      
      return {
        'url': base64String,
        'duration': duration,
      };
    } catch (e) {
      print('Error uploading recording: $e');
      throw Exception(e.toString());
    }
  }

  Future<void> cancelRecording() async {
    final path = await _audioRecorder.stop();
    if (path != null) {
      File file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<void> playAudio(String base64String) async {
    try {
      final Uint8List bytes = base64Decode(base64String);
      await _audioPlayer.play(BytesSource(bytes));
    } catch (e) {
      print('Error playing audio: $e');
    }
  }

  Future<void> stopAudio() async {
    await _audioPlayer.stop();
  }

  void dispose() {
    _audioRecorder.dispose();
    _audioPlayer.dispose();
  }
}
