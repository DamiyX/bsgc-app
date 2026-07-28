import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

class PreparedRecording {
  final Uint8List bytes;
  final int durationSeconds;
  final String localPath;

  const PreparedRecording({
    required this.bytes,
    required this.durationSeconds,
    required this.localPath,
  });
}

class AudioService {
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();

  String? _recordingPath;
  DateTime? _recordingStartTime;

  Future<bool> startRecording() async {
    try {
      if (!await _audioRecorder.hasPermission()) return false;

      final directory = await getTemporaryDirectory();
      _recordingPath = '${directory.path}/${const Uuid().v4()}.m4a';
      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: _recordingPath!,
      );
      _recordingStartTime = DateTime.now();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> stopRecording() => _audioRecorder.stop();

  Future<PreparedRecording> prepareRecording(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw StateError('The recorded audio is no longer available.');
    }

    final bytes = await file.readAsBytes();
    final elapsed = _recordingStartTime == null
        ? 1
        : DateTime.now().difference(_recordingStartTime!).inSeconds;
    final duration = elapsed.clamp(1, 300).toInt();
    return PreparedRecording(
      bytes: bytes,
      durationSeconds: duration,
      localPath: path,
    );
  }

  Future<void> deletePreparedRecording(PreparedRecording recording) async {
    final file = File(recording.localPath);
    if (await file.exists()) await file.delete();
    _recordingPath = null;
    _recordingStartTime = null;
  }

  Future<void> cancelRecording() async {
    final path = await _audioRecorder.stop() ?? _recordingPath;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    _recordingPath = null;
    _recordingStartTime = null;
  }

  Future<void> playAudioBytes(Uint8List bytes) {
    return _audioPlayer.play(BytesSource(bytes));
  }

  Future<void> stopAudio() => _audioPlayer.stop();

  void dispose() {
    _audioRecorder.dispose();
    _audioPlayer.dispose();
  }
}
