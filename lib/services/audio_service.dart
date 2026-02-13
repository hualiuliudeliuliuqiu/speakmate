import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:mp_audio_stream/mp_audio_stream.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../config/constants.dart';

class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _replayPlayer = AudioPlayer();
  StreamSubscription<List<int>>? _recordingSub;
  bool _isRecording = false;
  bool _isPlaying = false;

  // mp_audio_stream for real-time PCM push playback
  late AudioStream _audioStream;
  bool _streamInitialized = false;

  // Audio level for visualization
  final _audioLevelController = StreamController<double>.broadcast();
  Stream<double> get onAudioLevel => _audioLevelController.stream;

  bool get isRecording => _isRecording;
  bool get isPlaying => _isPlaying;

  // Callback for audio chunks from microphone
  void Function(Uint8List)? onAudioChunk;

  // Collect all PCM data for the current turn (for saving replay file)
  final List<int> _turnPcmBuffer = [];

  // Saved audio file paths by message ID
  final Map<String, String> _savedAudioFiles = {};

  // Notify listeners when replay state changes
  final _replayStateController = StreamController<bool>.broadcast();
  Stream<bool> get onReplayStateChanged => _replayStateController.stream;

  AudioService() {
    _audioStream = getAudioStream();
  }

  void _ensureStreamInit() {
    if (!_streamInitialized) {
      _audioStream.init(
        sampleRate: AppConstants.outputSampleRate, // 24000
        channels: AppConstants.numChannels, // 1
        bufferMilliSec: 5000, // 5 second buffer
        waitingBufferMilliSec: 50, // start playing after 50ms of data
      );
      _audioStream.resume();
      _streamInitialized = true;
    }
  }

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

  /// Add audio data — push to real-time stream AND collect for saving
  void addPlaybackData(Uint8List pcmData) {
    // Collect for saving later
    _turnPcmBuffer.addAll(pcmData);

    // Convert Int16 PCM to Float32 and push to audio stream for immediate playback
    _ensureStreamInit();
    final float32 = _pcm16ToFloat32(pcmData);
    _audioStream.push(float32);
    _isPlaying = true;
  }

  /// Convert 16-bit signed PCM (little-endian) to Float32 (-1.0 to 1.0)
  Float32List _pcm16ToFloat32(Uint8List pcmData) {
    // Ensure even length
    final alignedLength = pcmData.length - (pcmData.length % 2);
    final numSamples = alignedLength ~/ 2;
    final float32 = Float32List(numSamples);

    final byteData = ByteData.sublistView(pcmData, 0, alignedLength);
    for (int i = 0; i < numSamples; i++) {
      final sample = byteData.getInt16(i * 2, Endian.little);
      float32[i] = sample / 32768.0;
    }
    return float32;
  }

  /// Called when model turn is complete — save the audio for replay
  Future<void> flushRemainingPlayback({String? messageId}) async {
    // The audio is already playing via the stream — just need to save for replay
    if (messageId != null && _turnPcmBuffer.isNotEmpty) {
      await _saveTurnAudio(messageId);
    }
    _turnPcmBuffer.clear();
    // _isPlaying will be set to false by the model turn monitor
  }

  /// Mark playback as done (called by chat screen when model turn ends)
  void markPlaybackDone() {
    _isPlaying = false;
  }

  /// Save the complete turn PCM data as a WAV file for replay
  Future<void> _saveTurnAudio(String messageId) async {
    try {
      final wavData = _createWavFromPcm(
        Uint8List.fromList(_turnPcmBuffer),
        AppConstants.outputSampleRate,
        AppConstants.bitsPerSample,
        AppConstants.numChannels,
      );

      final appDir = await getApplicationDocumentsDirectory();
      final audioDir = Directory('${appDir.path}/audio');
      if (!await audioDir.exists()) {
        await audioDir.create(recursive: true);
      }

      final file = File('${audioDir.path}/$messageId.wav');
      await file.writeAsBytes(wavData);
      _savedAudioFiles[messageId] = file.path;
    } catch (e) {
      debugPrint('Failed to save turn audio: $e');
    }
  }

  /// Replay audio for a specific message ID (uses audioplayers for file playback)
  Future<void> replayAudio(String messageId) async {
    String? filePath = _savedAudioFiles[messageId];

    if (filePath == null) {
      final appDir = await getApplicationDocumentsDirectory();
      final candidate = File('${appDir.path}/audio/$messageId.wav');
      if (await candidate.exists()) {
        filePath = candidate.path;
        _savedAudioFiles[messageId] = filePath;
      }
    }

    if (filePath == null) return;

    final file = File(filePath);
    if (!await file.exists()) {
      _savedAudioFiles.remove(messageId);
      return;
    }

    // Stop any real-time stream playback first
    await stopPlayback();

    _replayStateController.add(true);

    try {
      await _replayPlayer.play(DeviceFileSource(filePath));

      final completer = Completer<void>();
      late StreamSubscription sub;
      sub = _replayPlayer.onPlayerComplete.listen((_) {
        if (!completer.isCompleted) completer.complete();
        sub.cancel();
      });

      await completer.future.timeout(
        const Duration(seconds: 120),
        onTimeout: () {
          sub.cancel();
        },
      );
    } catch (e) {
      debugPrint('Replay error: $e');
    } finally {
      _replayStateController.add(false);
    }
  }

  /// Check if a message has saved audio (sync, from cache)
  bool hasAudio(String messageId) {
    return _savedAudioFiles.containsKey(messageId);
  }

  /// Pre-load audio cache for a list of message IDs
  Future<void> preloadAudioCache(List<String> messageIds) async {
    final appDir = await getApplicationDocumentsDirectory();
    for (final id in messageIds) {
      if (!_savedAudioFiles.containsKey(id)) {
        final file = File('${appDir.path}/audio/$id.wav');
        if (await file.exists()) {
          _savedAudioFiles[id] = file.path;
        }
      }
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
    header.setUint8(0, 0x52); header.setUint8(1, 0x49);
    header.setUint8(2, 0x46); header.setUint8(3, 0x46);
    header.setUint32(4, fileSize, Endian.little);
    header.setUint8(8, 0x57); header.setUint8(9, 0x41);
    header.setUint8(10, 0x56); header.setUint8(11, 0x45);
    header.setUint8(12, 0x66); header.setUint8(13, 0x6D);
    header.setUint8(14, 0x74); header.setUint8(15, 0x20);
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, numChannels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    header.setUint8(36, 0x64); header.setUint8(37, 0x61);
    header.setUint8(38, 0x74); header.setUint8(39, 0x61);
    header.setUint32(40, dataSize, Endian.little);

    final result = Uint8List(44 + pcmData.length);
    result.setRange(0, 44, header.buffer.asUint8List());
    result.setRange(44, 44 + pcmData.length, pcmData);
    return result;
  }

  void _calculateAudioLevel(Uint8List bytes) {
    if (bytes.length < 2) return;
    final samples = bytes.buffer.asInt16List();
    double sumSquares = 0;
    for (final sample in samples) {
      sumSquares += sample * sample;
    }
    final rms = sumSquares / samples.length;
    final level = (rms / (32768 * 32768)).clamp(0.0, 1.0);
    final scaledLevel = level > 0 ? (level * 10).clamp(0.0, 1.0) : 0.0;
    _audioLevelController.add(scaledLevel);
  }

  /// Stop all playback
  Future<void> stopPlayback() async {
    _turnPcmBuffer.clear();
    _isPlaying = false;
    // Re-init stream to clear its buffer
    if (_streamInitialized) {
      _audioStream.uninit();
      _streamInitialized = false;
    }
    await _replayPlayer.stop();
  }

  void dispose() {
    stopRecording();
    stopPlayback();
    _recorder.dispose();
    _replayPlayer.dispose();
    if (_streamInitialized) {
      _audioStream.uninit();
    }
    _audioLevelController.close();
    _replayStateController.close();
  }
}
