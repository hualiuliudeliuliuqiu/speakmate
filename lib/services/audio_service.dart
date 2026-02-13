import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../config/constants.dart';

class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<List<int>>? _recordingSub;
  bool _isRecording = false;
  bool _isPlaying = false;

  // Audio level for visualization
  final _audioLevelController = StreamController<double>.broadcast();
  Stream<double> get onAudioLevel => _audioLevelController.stream;

  bool get isRecording => _isRecording;
  bool get isPlaying => _isPlaying;

  // Callback for audio chunks from microphone
  void Function(Uint8List)? onAudioChunk;

  // Buffer for collecting playback audio chunks
  final List<int> _playbackBuffer = [];
  Timer? _playbackTimer;
  bool _isBuffering = false;

  Future<bool> hasPermission() async {
    return await _recorder.hasPermission();
  }

  /// Start recording from the microphone, streaming PCM chunks
  Future<void> startRecording() async {
    if (_isRecording) return;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw Exception('Microphone permission not granted');
    }

    // Stop any playback
    await stopPlayback();

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: AppConstants.inputSampleRate,
        numChannels: AppConstants.numChannels,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ),
    );

    _isRecording = true;

    _recordingSub = stream.listen((data) {
      final bytes = Uint8List.fromList(data);
      onAudioChunk?.call(bytes);

      // Calculate audio level for visualization
      _calculateAudioLevel(bytes);
    });
  }

  /// Stop recording
  Future<void> stopRecording() async {
    if (!_isRecording) return;
    _isRecording = false;
    await _recordingSub?.cancel();
    _recordingSub = null;
    await _recorder.stop();
    _audioLevelController.add(0.0);
  }

  /// Add audio data to the playback buffer
  void addPlaybackData(Uint8List pcmData) {
    _playbackBuffer.addAll(pcmData);

    // Start playback after accumulating enough data (100ms worth)
    // 24000 samples/sec * 2 bytes/sample * 0.1 sec = 4800 bytes
    if (!_isBuffering && !_isPlaying && _playbackBuffer.length > 4800) {
      _isBuffering = true;
      // Small delay to buffer a bit more before starting playback
      _playbackTimer?.cancel();
      _playbackTimer = Timer(const Duration(milliseconds: 150), () {
        _flushPlayback();
      });
    }
  }

  /// Called when model turn is complete — flush remaining buffer
  Future<void> flushRemainingPlayback() async {
    _playbackTimer?.cancel();
    if (_playbackBuffer.isNotEmpty) {
      await _flushPlayback();
    }
  }

  Future<void> _flushPlayback() async {
    if (_playbackBuffer.isEmpty) {
      _isBuffering = false;
      return;
    }

    _isPlaying = true;
    _isBuffering = false;

    // Take all buffered data
    final pcmData = Uint8List.fromList(_playbackBuffer);
    _playbackBuffer.clear();

    try {
      // Create WAV file from PCM data
      final wavData = _createWavFromPcm(
        pcmData,
        AppConstants.outputSampleRate,
        AppConstants.bitsPerSample,
        AppConstants.numChannels,
      );

      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        '${tempDir.path}/speakmate_playback_${DateTime.now().millisecondsSinceEpoch}.wav',
      );
      await tempFile.writeAsBytes(wavData);

      await _player.play(DeviceFileSource(tempFile.path));

      // Wait for playback to complete
      await _player.onPlayerComplete.first.timeout(
        const Duration(seconds: 30),
        onTimeout: () {},
      );

      // Cleanup temp file
      try {
        await tempFile.delete();
      } catch (_) {}

      // If more data arrived during playback, flush again
      if (_playbackBuffer.isNotEmpty) {
        await _flushPlayback();
      }
    } catch (e) {
      debugPrint('Playback error: $e');
    } finally {
      _isPlaying = false;
    }
  }

  /// Create a WAV file from raw PCM data
  Uint8List _createWavFromPcm(
    Uint8List pcmData,
    int sampleRate,
    int bitsPerSample,
    int numChannels,
  ) {
    final byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
    final blockAlign = numChannels * (bitsPerSample ~/ 8);
    final dataSize = pcmData.length;
    final fileSize = 36 + dataSize;

    final header = ByteData(44);
    // RIFF header
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, fileSize, Endian.little);
    header.setUint8(8, 0x57); // W
    header.setUint8(9, 0x41); // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E

    // fmt chunk
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6D); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // (space)
    header.setUint32(16, 16, Endian.little); // chunk size
    header.setUint16(20, 1, Endian.little); // PCM format
    header.setUint16(22, numChannels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);

    // data chunk
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, dataSize, Endian.little);

    final result = Uint8List(44 + pcmData.length);
    result.setRange(0, 44, header.buffer.asUint8List());
    result.setRange(44, 44 + pcmData.length, pcmData);
    return result;
  }

  void _calculateAudioLevel(Uint8List bytes) {
    if (bytes.length < 2) return;

    // Interpret as 16-bit signed PCM
    final samples = bytes.buffer.asInt16List();
    double sumSquares = 0;
    for (final sample in samples) {
      sumSquares += sample * sample;
    }
    final rms = sumSquares / samples.length;
    // Normalize to 0-1 range (max int16 is 32768)
    final level = (rms / (32768 * 32768)).clamp(0.0, 1.0);
    // Apply sqrt for better visual scaling
    final scaledLevel = level > 0 ? (level * 10).clamp(0.0, 1.0) : 0.0;
    _audioLevelController.add(scaledLevel);
  }

  /// Stop all playback
  Future<void> stopPlayback() async {
    _playbackTimer?.cancel();
    _playbackBuffer.clear();
    _isBuffering = false;
    _isPlaying = false;
    await _player.stop();
  }

  void dispose() {
    stopRecording();
    stopPlayback();
    _recorder.dispose();
    _player.dispose();
    _audioLevelController.close();
  }
}
