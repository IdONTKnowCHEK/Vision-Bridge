import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../components/audio_visualizer.dart';
import '../screens/nfc_screen.dart';
import '../services/audio_service.dart';
import '../services/microphone_service.dart';
import '../services/speech_service.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import 'package:permission_handler/permission_handler.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with SingleTickerProviderStateMixin {
  AudioVisualizerMode _audioMode = AudioVisualizerMode.loading;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  final MicrophoneService _microphoneService = MicrophoneService();
  bool _isMicrophoneActive = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
    ));

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );

    _animationController.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initApp();
    });
  }

  // Future<bool> _activateMicrophone() async {
  //   if (_isMicrophoneActive) {
  //     _microphoneService.stopListening();
  //   }
  //
  //   bool hasPermission = await _microphoneService.startListening();
  //   if (mounted) {
  //     setState(() {
  //       _isMicrophoneActive = hasPermission;
  //     });
  //   }
  //   return hasPermission;
  // }

  void _deactivateMicrophone() {
    if (_isMicrophoneActive) {
      _microphoneService.stopListening();
      setState(() {
        _isMicrophoneActive = false;
      });
    }
  }

  Future<void> _initApp() async {
    if (!StorageService.isFirstLaunch()) {
      final country = StorageService.getCountry();
      if (country != null && mounted) {
        Future.microtask(() {
          _navigateToNfcScreen(country);
        });
        return;
      }
    }

    if (mounted) {
      await _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    print('Checking permissions...');

    // 1. 麥克風權限
    PermissionStatus micStatus = await Permission.microphone.status;
    print('Initial Microphone status: $micStatus');

    if (micStatus.isDenied || micStatus.isRestricted) { // isDenied 表示用戶還沒選擇，或者選擇了「拒絕」但不是「永不詢問」
      micStatus = await Permission.microphone.request();
      print('Microphone status after request: $micStatus');
    }

    if (micStatus.isPermanentlyDenied) {
      print('麥克風權限已被永久拒絕，請至「設定」開啟權限');
      // 提示用戶去設置開啟，可以考慮使用 openAppSettings()
      await openAppSettings();
      return;
    }

    if (!micStatus.isGranted) {
      print('需要麥克風權限才能繼續使用，請授予權限後重試');
      return;
    }

    // 2. 語音辨識權限 (如果你的 SpeechService 依賴這個)
    // speech_to_text 套件通常會在其 initialize 方法中處理 SFSpeechRecognizerAuthorizationStatus
    // 但你也可以用 permission_handler 檢查 (雖然它沒有直接的 speech_recognition 枚舉給 iOS 的 SFSpeechRecognizer)
    // 通常，如果麥克風權限被授予，且 Info.plist 有 NSSpeechRecognitionUsageDescription，
    // speech_to_text 插件內部應該能處理好。

    print('麥克風權限已授予，繼續檢查 STT...');

    try {
      final sttAvailable = await SpeechService.isSTTAvailable(); // 假設這是 speech_to_text 的 initialize 或類似方法
      if (!sttAvailable) {
        print('您的設備不支援語音辨識功能 或 語音辨識權限未授予');
        // speech_to_text 的 initialize 返回 false 也可能是因為語音辨識權限未授予
        // 此時可以檢查 SFSpeechRecognizerAuthorizationStatus (如果能直接訪問) 或提示用戶
        return;
      }
    } catch (e) {
      print('此裝置無法使用語音辨識，或發生錯誤：$e');
      if (e.toString().contains("speech_recognition_not_authorized")) { // 這是 speech_to_text 可能拋出的錯誤
        print('語音辨識權限未授予，請至「設定」確認相關權限。');
        // await openAppSettings(); // 可以引導用戶去設定
      } else {
        print('此裝置無法使用語音辨識，請安裝 Google STT (如果適用於Android) 或檢查iOS設定');
      }
      setState(() {
        _audioMode = AudioVisualizerMode.systemPlaying;
      });

      _deactivateMicrophone();
      SpeechService.stopListening();
      await AudioService.playAndWait(AppConstants.notSupportSTT);

      setState(() {
        _audioMode = AudioVisualizerMode.loading;
      });
      return;
    }
    await _playSoundAndListen();
  }

  Future<void> _playSoundAndListen() async {
    try {
      setState(() {
        _audioMode = AudioVisualizerMode.systemPlaying;
      });

      _deactivateMicrophone();
      SpeechService.stopListening();

      await AudioService.playAndWait(AppConstants.startAudio);

      await _startListening();
    } catch (e) {
      print('無法播放音效或啟動語音識別: $e');
      setState(() {
        _audioMode = AudioVisualizerMode.loading;
      });
    }
  }

  Future<void> _startListening() async {
    // bool micStarted = await _activateMicrophone();
    // if (!micStarted) {
    //   print('麥克風啟動失敗');
    //   if (mounted) {
    //     setState(() {
    //       _audioMode = AudioVisualizerMode.systemPlaying;
    //     });
    //     SpeechService.stopListening();
    //     await AudioService.playAndWait(AppConstants.retryAudio);
    //     await _startListening();
    //   }
    //   return;
    // }

    await Future.delayed(const Duration(milliseconds: 300));

    if (mounted) {
      setState(() {
        _audioMode = AudioVisualizerMode.userSpeaking;
      });
    }

    try {
      final recognizedText = await SpeechService.listenAndWait();

      _deactivateMicrophone();
      SpeechService.stopListening();

      print('辨識的文字：$recognizedText');

      if (mounted) {


        setState(() {
          _audioMode = AudioVisualizerMode.loading;
        });

        if (recognizedText.trim().isEmpty || recognizedText.trim().length < 2) {
          setState(() {
            _audioMode = AudioVisualizerMode.systemPlaying;
          });
          await AudioService.playAndWait(AppConstants.retryAudio);
          await _startListening();
          return;
        }
        await _processRecognizedText(recognizedText);
      }
    } catch (e) {
      if (mounted) {
        _deactivateMicrophone();
        SpeechService.stopListening();

        setState(() {
          _audioMode = AudioVisualizerMode.systemPlaying;
        });
        await AudioService.playAndWait(AppConstants.retryAudio);
        await _startListening();
      }
    }
  }

  Future<void> _processRecognizedText(String text) async {
    try {
      final response = await ApiService.sendCountry(text);
      print(response.content);
      if (response.success) {
        setState(() {
          _audioMode = AudioVisualizerMode.systemPlaying;
        });
        SpeechService.stopListening();
        await AudioService.playAndWait(AppConstants.gotAudio);
        await StorageService.saveCountry(response.content);

        await _promptForCustomColor();

        await StorageService.setNotFirstLaunch();

        _navigateToNfcScreen(response.content);
      } else {
        setState(() {
          _audioMode = AudioVisualizerMode.systemPlaying;
        });
        SpeechService.stopListening();
        await AudioService.playAndWait(AppConstants.retryAudio);
        await _startListening();
      }
    } catch (e) {
      print('API 處理錯誤: $e');
      setState(() {
        _audioMode = AudioVisualizerMode.systemPlaying;
      });
      SpeechService.stopListening();
      await AudioService.playAndWait(AppConstants.retryAudio);
      await _startListening();
    }
  }

  Future<void> _promptForCustomColor() async {
    await Future.delayed(const Duration(milliseconds: 100));

    setState(() {
      _audioMode = AudioVisualizerMode.systemPlaying;
    });
    SpeechService.stopListening();
    await AudioService.playAndWait(AppConstants.customColor);

    // bool micStarted = await _activateMicrophone();
    // if (!micStarted) {
    //   print('麥克風啟動失敗');
    //   return;
    // }

    await Future.delayed(const Duration(milliseconds: 300));

    if (mounted) {
      setState(() {
        _audioMode = AudioVisualizerMode.userSpeaking;
      });
    }

    try {
      final colorText = await SpeechService.listenAndWait();
      _deactivateMicrophone();

      setState(() {
        _audioMode = AudioVisualizerMode.loading;
      });

      if (colorText.trim().isNotEmpty) {
        await StorageService.saveCustom(colorText.trim());
        setState(() {
          _audioMode = AudioVisualizerMode.systemPlaying;
        });
      }
      SpeechService.stopListening();
      await AudioService.playAndWait(AppConstants.doneAudio);
      print('顏色語音識別成功: $colorText');
    } catch (e) {
      _deactivateMicrophone();
      print('顏色語音識別錯誤: $e');
    }
  }

  void _navigateToNfcScreen(String country) {

    _deactivateMicrophone();
    SpeechService.stopListening();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => NfcScreen(country: country),
      ),
    );
  }

  @override
  void dispose() {
    _microphoneService.dispose();
    _animationController.dispose();
    SpeechService.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final double visualizerSize = screenSize.width * 0.7;

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        // decoration: const BoxDecoration(
        //   gradient: LinearGradient(
        //     begin: Alignment.topLeft,
        //     end: Alignment.bottomRight,
        //     colors: [
        //       Color(0xFF202020),
        //       Color(0xFF1B1B1B),
        //     ],
        //   ),
        // ),
        child: Container( //New added container
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/bg.png'),
              repeat: ImageRepeat.repeat,
              fit: BoxFit.none,
              colorFilter: ColorFilter.mode(
                Colors.white54,
                BlendMode.srcATop,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularAudioVisualizer(
                      mode: _audioMode,
                      size: visualizerSize,
                      microphoneVolumeNotifier:
                      _audioMode == AudioVisualizerMode.userSpeaking
                          ? _microphoneService.volumeNotifier
                          : null,
                      amplitude: 0.7,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}