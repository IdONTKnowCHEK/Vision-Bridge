import 'package:flutter/material.dart';
import 'dart:math' as math;

enum AudioVisualizerMode {
  userSpeaking,  // 使用者說話
  loading,       // 載入中
  systemPlaying  // 系統播放音訊
}

class CircularAudioVisualizer extends StatefulWidget {
  final AudioVisualizerMode mode;
  final Color? color;
  final double size;
  final double? amplitude; // 可選，若為null則使用內部動畫
  final ValueNotifier<double>? microphoneVolumeNotifier; // 麥克風音量通知器
  final Duration transitionDuration; // 音量過渡動畫時長

  const CircularAudioVisualizer({
    Key? key,
    required this.mode,
    this.color,
    this.size = 200,
    this.amplitude,
    this.microphoneVolumeNotifier,
    this.transitionDuration = const Duration(milliseconds: 300),
  }) : super(key: key);

  @override
  State<CircularAudioVisualizer> createState() => _CircularAudioVisualizerState();
}

class _CircularAudioVisualizerState extends State<CircularAudioVisualizer> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late AnimationController _volumeTransitionController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _volumeAnimation;

  final List<double> _waveSizes = List.filled(5, 0.0);
  final List<double> _waveOpacities = List.filled(5, 0.0);

  final math.Random _random = math.Random();
  late double _currentAmplitude;
  late double _targetAmplitude;
  double _lastMicVolume = 0.0;
  bool _isInitialVolumeSetting = true;

  // 音量平滑參數
  final List<double> _recentVolumes = [];
  final int _smoothingWindowSize = 3;

  @override
  void initState() {
    super.initState();

    // 根據模式選擇合適的初始振幅
    _initializeAmplitude();

    _initializeAnimations();

    // 添加麥克風音量監聽 (只影響波形，不影響圖標)
    if (widget.mode == AudioVisualizerMode.userSpeaking &&
        widget.microphoneVolumeNotifier != null) {
      widget.microphoneVolumeNotifier!.addListener(_updateFromMicrophone);

      // 立即獲取初始音量值
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateFromMicrophone();
      });
    }
  }

  void _initializeAmplitude() {
    // 如果是用戶說話模式且使用麥克風，則初始振幅設為很小的值
    if (widget.mode == AudioVisualizerMode.userSpeaking &&
        widget.microphoneVolumeNotifier != null) {
      _currentAmplitude = 0.05; // 很小的初始值
      _targetAmplitude = 0.05;
    } else {
      _currentAmplitude = widget.amplitude ?? 0.7;
      _targetAmplitude = _currentAmplitude;
    }
  }

  @override
  void didUpdateWidget(CircularAudioVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 處理模式變化
    if (oldWidget.mode != widget.mode) {
      // 移除舊的監聽器
      if (oldWidget.mode == AudioVisualizerMode.userSpeaking &&
          oldWidget.microphoneVolumeNotifier != null) {
        oldWidget.microphoneVolumeNotifier!.removeListener(_updateFromMicrophone);
      }

      // 添加新的監聽器
      if (widget.mode == AudioVisualizerMode.userSpeaking &&
          widget.microphoneVolumeNotifier != null) {
        widget.microphoneVolumeNotifier!.addListener(_updateFromMicrophone);
      }

      // 重置動畫
      _disposeAnimations();

      // 重新初始化振幅
      _initializeAmplitude();
      _initializeAnimations();

      // 切換到麥克風模式時，立即設置為初始狀態並請求麥克風音量
      if (widget.mode == AudioVisualizerMode.userSpeaking &&
          widget.microphoneVolumeNotifier != null) {
        _isInitialVolumeSetting = true;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateFromMicrophone();
        });
      }
    }

    // 處理振幅變化
    if (oldWidget.amplitude != widget.amplitude && widget.amplitude != null) {
      // 只有在非用戶說話模式，或者用戶說話模式但不使用麥克風時才直接更新振幅
      if (widget.mode != AudioVisualizerMode.userSpeaking ||
          widget.microphoneVolumeNotifier == null) {
        _updateTargetAmplitude(widget.amplitude!);
      }
    }

    // 處理麥克風通知器變化
    if (oldWidget.microphoneVolumeNotifier != widget.microphoneVolumeNotifier) {
      if (oldWidget.microphoneVolumeNotifier != null) {
        oldWidget.microphoneVolumeNotifier!.removeListener(_updateFromMicrophone);
      }

      if (widget.microphoneVolumeNotifier != null &&
          widget.mode == AudioVisualizerMode.userSpeaking) {
        _isInitialVolumeSetting = true;
        widget.microphoneVolumeNotifier!.addListener(_updateFromMicrophone);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateFromMicrophone();
        });
      }
    }

    // 處理過渡時長變化
    if (oldWidget.transitionDuration != widget.transitionDuration) {
      _volumeTransitionController.duration = widget.transitionDuration;
    }
  }

  // 平滑音量值
  double _smoothVolume(double newVolume) {
    // 添加新值到歷史記錄
    _recentVolumes.add(newVolume);

    // 保持窗口大小
    if (_recentVolumes.length > _smoothingWindowSize) {
      _recentVolumes.removeAt(0);
    }

    // 計算加權平均 (較新的值權重更大)
    double sum = 0;
    double weightSum = 0;

    for (int i = 0; i < _recentVolumes.length; i++) {
      double weight = i + 1;
      sum += _recentVolumes[i] * weight;
      weightSum += weight;
    }

    return sum / weightSum;
  }

  // 平滑過渡到目標音量
  void _updateTargetAmplitude(double newTarget) {
    // 設置新的目標值
    _targetAmplitude = newTarget;

    // 如果是初始設置，直接更新當前振幅而不需要動畫
    if (_isInitialVolumeSetting) {
      _currentAmplitude = newTarget;
      _isInitialVolumeSetting = false;
      _volumeAnimation = Tween<double>(
        begin: _currentAmplitude,
        end: _targetAmplitude,
      ).animate(
        CurvedAnimation(
          parent: _volumeTransitionController,
          curve: Curves.easeOutCubic,
        ),
      );
      setState(() {});
      return;
    }

    // 計算過渡時長，變化越大時長越長
    final double changeAmount = (_targetAmplitude - _currentAmplitude).abs();
    final double durationFactor = math.min(1.0, changeAmount * 3);

    // 根據變化量調整過渡時長
    final adjustedDuration = Duration(
      milliseconds: (widget.transitionDuration.inMilliseconds * durationFactor).round(),
    );

    // 設置動畫控制器時長
    _volumeTransitionController.duration = adjustedDuration;

    // 如果動畫正在運行，先停止
    _volumeTransitionController.stop();

    // 設置新的動畫
    _volumeAnimation = Tween<double>(
      begin: _currentAmplitude,
      end: _targetAmplitude,
    ).animate(
      CurvedAnimation(
        parent: _volumeTransitionController,
        curve: Curves.easeOutCubic,
      ),
    );

    // 啟動動畫
    _volumeTransitionController.forward(from: 0.0);
  }

  void _updateFromMicrophone() {
    if (widget.microphoneVolumeNotifier == null ||
        widget.mode != AudioVisualizerMode.userSpeaking) return;

    double newVolume = widget.microphoneVolumeNotifier!.value;

    // 針對初始值進行特殊處理
    if (_isInitialVolumeSetting) {
      _updateTargetAmplitude(newVolume);
      return;
    }

    // 平滑音量值
    double smoothedVolume = _smoothVolume(newVolume);

    // 減少更新頻率，僅當音量值變化明顯時才更新
    if ((smoothedVolume - _lastMicVolume).abs() > 0.03 ||
        (smoothedVolume > 0.2 && _lastMicVolume < 0.2) ||
        (smoothedVolume < 0.2 && _lastMicVolume > 0.2)) {

      _lastMicVolume = smoothedVolume;

      // 開始過渡到新的音量值，只影響波形，不影響中心圖標
      _updateTargetAmplitude(smoothedVolume);
    }
  }

  void _initializeAnimations() {
    // 主脈衝動畫控制器 - 統一使用 loading 模式的時長
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    // 波形擴散控制器
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    // 音量過渡控制器
    _volumeTransitionController = AnimationController(
      vsync: this,
      duration: widget.transitionDuration,
    );

    // 脈衝大小動畫 - 所有模式統一
    _pulseAnimation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    // 音量過渡動畫
    _volumeAnimation = Tween<double>(
      begin: _currentAmplitude,
      end: _targetAmplitude,
    ).animate(
      CurvedAnimation(
        parent: _volumeTransitionController,
        curve: Curves.easeOutCubic,
      ),
    );

    // 音量變化監聽
    _volumeTransitionController.addListener(_onVolumeAnimationChanged);

    // 根據模式產生隨機振幅變化
    _pulseController.addListener(_updateAmplitude);

    // 啟動波形擴散動畫
    _waveController.addListener(_updateWaves);

    // 對所有模式啟動脈衝動畫，不再區分模式
    _pulseController.repeat(reverse: true);
  }

  // 音量動畫更新
  void _onVolumeAnimationChanged() {
    if (_volumeTransitionController.isAnimating) {
      setState(() {
        _currentAmplitude = _volumeAnimation.value;
      });
    }
  }

  // 更新振幅變化
  void _updateAmplitude() {
    if (!mounted) return;

    // 強制更新渲染
    setState(() {});
  }

  // 更新波形位置和不透明度
  void _updateWaves() {
    if (!mounted) return;

    setState(() {
      for (int i = 0; i < _waveSizes.length; i++) {
        // 波形大小隨時間變化
        _waveSizes[i] = (i * 0.2 + _waveController.value) % 1.0;

        // 波形不透明度 - 當波形擴散時逐漸消失
        _waveOpacities[i] = math.max(0, 1.0 - _waveSizes[i]);

        // 用戶說話模式下，根據麥克風音量調整波形振幅
        if (widget.mode == AudioVisualizerMode.userSpeaking &&
            widget.microphoneVolumeNotifier != null) {
          _waveOpacities[i] *= (0.3 + _currentAmplitude * 0.7);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final Color visualizerColor = widget.color ?? _getModeColor();

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 擴散的波形圓環
          ..._buildWaveCircles(visualizerColor),

          // 中心圖標
          _buildCenterIcon(visualizerColor),
        ],
      ),
    );
  }

  List<Widget> _buildWaveCircles(Color color) {
    List<Widget> circles = [];

    for (int i = 0; i < _waveSizes.length; i++) {
      // 根據當前振幅和模式計算波形大小
      double currentSize = widget.size * _getAmplitudeFactor() * _waveSizes[i];

      if (currentSize <= 0) continue;

      circles.add(
        Opacity(
          opacity: _waveOpacities[i],
          child: Container(
            width: currentSize,
            height: currentSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: color,
                width: _getBorderWidth(i),
              ),
            ),
          ),
        ),
      );
    }

    return circles;
  }

  // 根據模式和動畫狀態計算振幅因子
  double _getAmplitudeFactor() {
    double baseAmplitude;

    // 使用外部提供的振幅或內部振幅
    if (widget.mode == AudioVisualizerMode.userSpeaking &&
        widget.microphoneVolumeNotifier != null) {
      baseAmplitude = _currentAmplitude;
    } else {
      baseAmplitude = widget.amplitude ?? _currentAmplitude;
    }

    double animationValue = _pulseAnimation.value;

    switch (widget.mode) {
      case AudioVisualizerMode.userSpeaking:
        if (widget.microphoneVolumeNotifier != null) {
          // 麥克風直接控制 - 使用平滑過渡後的振幅並添加微小隨機變化
          return baseAmplitude * (0.95 + _random.nextDouble() * 0.1);
        } else {
          // 無麥克風 - 更隨機的波動
          return baseAmplitude * animationValue * (0.7 + _random.nextDouble() * 0.3);
        }

      case AudioVisualizerMode.loading:
      // 載入中 - 平滑的波動
        return baseAmplitude * animationValue;

      case AudioVisualizerMode.systemPlaying:
      // 系統播放 - 均勻的波動
        return baseAmplitude * animationValue * (0.9 + _random.nextDouble() * 0.1);
    }
  }

  // 根據不同圈數獲取邊框寬度
  double _getBorderWidth(int index) {
    // 使用者說話模式下，根據麥克風音量動態調整邊框寬度
    if (widget.mode == AudioVisualizerMode.userSpeaking &&
        widget.microphoneVolumeNotifier != null) {
      // 根據振幅變化，高聲音時邊框更粗
      double volumeFactor = 1.0 + _currentAmplitude * 2.0;
      return math.min(5.0, (3.0 - index * 0.4) * volumeFactor);
    }

    switch (widget.mode) {
      case AudioVisualizerMode.userSpeaking:
        return 3.0 - index * 0.4;
      case AudioVisualizerMode.loading:
        return 2.0;
      case AudioVisualizerMode.systemPlaying:
        return 2.5 - index * 0.3;
    }
  }

  // 中央圖標 - 所有模式統一使用相同的動畫
  Widget _buildCenterIcon(Color color) {
    IconData iconData;
    double iconSize = widget.size * 0.25;

    // 根據模式選擇圖標，但動畫效果統一
    switch (widget.mode) {
      case AudioVisualizerMode.userSpeaking:
        iconData = Icons.mic;
        break;
      case AudioVisualizerMode.loading:
        iconData = Icons.hourglass_empty;
        break;
      case AudioVisualizerMode.systemPlaying:
        iconData = Icons.volume_up;
        break;
    }

    return Container(
      width: widget.size * 0.35,
      height: widget.size * 0.35,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.5),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.2),
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
      ),
      // 使用統一的動畫，不再根據模式區分
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return Transform.scale(
            scale: 0.8 + _pulseController.value * 0.2,
            child: Icon(
              iconData,
              color: color,
              size: iconSize,
            ),
          );
        },
      ),
    );
  }

  // 根據模式獲取顏色
  Color _getModeColor() {
    switch (widget.mode) {
      case AudioVisualizerMode.userSpeaking:
        return Colors.blueAccent;
      case AudioVisualizerMode.loading:
        return Colors.orangeAccent;
      case AudioVisualizerMode.systemPlaying:
        return Colors.greenAccent;
    }
  }

  void _disposeAnimations() {
    _pulseController.removeListener(_updateAmplitude);
    _waveController.removeListener(_updateWaves);
    _volumeTransitionController.removeListener(_onVolumeAnimationChanged);

    _pulseController.dispose();
    _waveController.dispose();
    _volumeTransitionController.dispose();
  }

  @override
  void dispose() {
    if (widget.microphoneVolumeNotifier != null &&
        widget.mode == AudioVisualizerMode.userSpeaking) {
      widget.microphoneVolumeNotifier!.removeListener(_updateFromMicrophone);
    }

    _disposeAnimations();
    super.dispose();
  }
}