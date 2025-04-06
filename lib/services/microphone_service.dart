import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:noise_meter/noise_meter.dart';
import 'package:permission_handler/permission_handler.dart';

class MicrophoneService {
  final NoiseMeter _noiseMeter = NoiseMeter();
  StreamSubscription<NoiseReading>? _noiseSubscription;
  final ValueNotifier<double> volumeNotifier = ValueNotifier(0.05);  // 初始值設為很小
  bool _isListening = false;

  // 音量範圍調整參數
  final double _minDb = 35.0;  // 靜音閾值 (dB)
  final double _maxDb = 70.0;  // 最大音量 (dB)

  // 平滑處理
  final List<double> _volumeBuffer = [];
  final int _bufferSize = 5;

  bool get isListening => _isListening;

  // 建構函數初始化
  MicrophoneService() {
    // 確保初始狀態時波形很小
    volumeNotifier.value = 0.05;
  }

  // 開始監聽麥克風
  Future<bool> startListening() async {
    // 檢查麥克風權限
    if (!(await Permission.microphone.isGranted)) {
      final status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        return false;
      }
    }

    try {
      // 重置緩衝區
      _volumeBuffer.clear();

      // 重置音量通知器為初始小值
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

  // 停止監聽麥克風
  void stopListening() {
    _noiseSubscription?.cancel();
    _noiseSubscription = null;
    _isListening = false;

    // 平滑過渡到安靜狀態
    _smoothTransitionToSilence();
  }

  // 平滑過渡到靜音
  void _smoothTransitionToSilence() {
    double currentValue = volumeNotifier.value;

    if (currentValue <= 0.05) {
      volumeNotifier.value = 0.05;  // 使用最小值而不是0
      return;
    }

    // 創建一個計時器，逐漸降低音量值
    Timer.periodic(const Duration(milliseconds: 50), (timer) {
      currentValue *= 0.8; // 每次減少20%

      if (currentValue <= 0.05) {
        currentValue = 0.05;  // 最小值
        timer.cancel();
      }

      volumeNotifier.value = currentValue;
    });
  }

  // 處理噪聲讀數
  void _onNoise(NoiseReading noiseReading) {
    if (!_isListening) return;

    // 獲取分貝值
    double db = noiseReading.meanDecibel;

    // 正規化音量值到0.0-1.0範圍
    double normalizedVolume = _normalizeVolume(db);

    // 添加到緩衝區進行平滑處理
    _addToBuffer(normalizedVolume);

    // 計算平滑音量值
    double smoothedVolume = _calculateSmoothedVolume();

    // 確保靜音時也有一個最小值（避免波形完全消失）
    smoothedVolume = math.max(0.05, smoothedVolume);

    // 更新音量通知
    volumeNotifier.value = smoothedVolume;
  }

  // 添加到緩衝區
  void _addToBuffer(double volume) {
    _volumeBuffer.add(volume);

    // 限制緩衝區大小
    if (_volumeBuffer.length > _bufferSize) {
      _volumeBuffer.removeAt(0);
    }
  }

  // 計算平滑音量值 - 使用加權移動平均
  double _calculateSmoothedVolume() {
    if (_volumeBuffer.isEmpty) return 0.05;  // 最小值

    double sum = 0;
    double weightSum = 0;

    // 較新的數據權重更大
    for (int i = 0; i < _volumeBuffer.length; i++) {
      double weight = i + 1; // 線性權重
      sum += _volumeBuffer[i] * weight;
      weightSum += weight;
    }

    return sum / weightSum;
  }

  // 根據分貝值正規化音量 (0.0 - 1.0)
  double _normalizeVolume(double db) {
    // 處理無效值
    if (db.isNaN || db.isInfinite || db < 0) return 0.05;  // 最小值

    // 限制在最小和最大閾值之間
    db = db.clamp(_minDb, _maxDb);

    // 範圍正規化
    double normalized = (db - _minDb) / (_maxDb - _minDb);

    // 為了更好的視覺效果，可以調整曲線
    normalized = normalized * normalized;  // 平方使低音量時變化更明顯

    // 確保最小值
    return math.max(0.05, normalized);
  }

  // 銷毀服務
  void dispose() {
    stopListening();
  }
}