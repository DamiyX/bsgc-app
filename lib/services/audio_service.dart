import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

const voiceRecordingDiscardedMessage =
    'The recording could not be saved and was discarded. Record again.';

/// The recorder plugin can return null even though it was given a path. Keep
/// the path owned by this service as the recovery candidate so a stopped file
/// is either moved into the outbox or explicitly discarded; it must not be
/// released into the OS temporary directory.
String? resolveRecordingPath(String? stoppedPath, String? activePath) {
  return stoppedPath ?? activePath;
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

  Future<String?> stopRecording() async {
    final stoppedPath = await _audioRecorder.stop();
    return resolveRecordingPath(stoppedPath, _recordingPath);
  }

  /// Returns the user-visible duration for the current recording without
  /// reading the temporary file. The file is moved into the durable outbox
  /// before any optional processing, so a read failure cannot strand it in
  /// the OS temporary directory.
  int get recordingDurationSeconds {
    final startedAt = _recordingStartTime;
    final elapsed = startedAt == null
        ? 1
        : DateTime.now().difference(startedAt).inSeconds;
    return elapsed.clamp(1, 300).toInt();
  }

  Future<void> discardRecording(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
    _recordingPath = null;
    _recordingStartTime = null;
  }

  void releaseRecording() {
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
