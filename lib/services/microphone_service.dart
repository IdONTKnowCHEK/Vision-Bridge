import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:noise_meter/noise_meter.dart';
import 'package:permission_handler/permission_handler.dart';

class MicrophoneService {
  final NoiseMeter _noiseMeter = NoiseMeter();
  StreamSubscription<NoiseReading>? _noiseSubscription;
  final ValueNotifier<double> volumeNotifier = ValueNotifier(0.05);
  bool _isListening = false;

  final double _minDb = 35.0;
  final double _maxDb = 70.0;

  final List<double> _volumeBuffer = [];
  final int _bufferSize = 5;

  bool get isListening => _isListening;

  MicrophoneService() {
    volumeNotifier.value = 0.05;
  }

  Future<bool> startListening() async {
    if (!(await Permission.microphone.isGranted)) {
      final status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        return false;
      }
    }

    try {
      _volumeBuffer.clear();

      volumeNotifier.value = 0.05;

      _noiseSubscription = _noiseMeter.noise.listen(_onNoise);
      _isListening = true;
      return true;
    } catch (e) {
      debugPrint('麥克風監聽錯誤: $e');
      _isListening = false;
      return false;
    }
  }

  void stopListening() {
    _noiseSubscription?.cancel();
    _noiseSubscription = null;
    _isListening = false;

    _smoothTransitionToSilence();
  }

  void _smoothTransitionToSilence() {
    double currentValue = volumeNotifier.value;

    if (currentValue <= 0.05) {
      volumeNotifier.value = 0.05;
      return;
    }

    Timer.periodic(const Duration(milliseconds: 50), (timer) {
      currentValue *= 0.8;

      if (currentValue <= 0.05) {
        currentValue = 0.05;
        timer.cancel();
      }

      volumeNotifier.value = currentValue;
    });
  }

  void _onNoise(NoiseReading noiseReading) {
    if (!_isListening) return;

    double db = noiseReading.meanDecibel;
    double normalizedVolume = _normalizeVolume(db);
    _addToBuffer(normalizedVolume);
    double smoothedVolume = _calculateSmoothedVolume();
    smoothedVolume = math.max(0.05, smoothedVolume);
    volumeNotifier.value = smoothedVolume;
  }

  void _addToBuffer(double volume) {
    _volumeBuffer.add(volume);

    if (_volumeBuffer.length > _bufferSize) {
      _volumeBuffer.removeAt(0);
    }
  }

  double _calculateSmoothedVolume() {
    if (_volumeBuffer.isEmpty) return 0.05;

    double sum = 0;
    double weightSum = 0;

    for (int i = 0; i < _volumeBuffer.length; i++) {
      double weight = i + 1;
      sum += _volumeBuffer[i] * weight;
      weightSum += weight;
    }

    return sum / weightSum;
  }

  double _normalizeVolume(double db) {
    if (db.isNaN || db.isInfinite || db < 0) return 0.05;
    db = db.clamp(_minDb, _maxDb);
    double normalized = (db - _minDb) / (_maxDb - _minDb);
    normalized = normalized * normalized;
    return math.max(0.05, normalized);
  }

  void dispose() {
    stopListening();
  }
}