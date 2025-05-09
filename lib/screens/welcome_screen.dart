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

    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      print('需要麥克風權限才能繼續使用，請授予權限後重試');
      return;
    }

    try {
      final sttAvailable = await SpeechService.isSTTAvailable();
      if (!sttAvailable) {
        print('您的設備不支援語音辨識功能');
        return;
      }
    } catch (e) {
      print('此裝置無法使用語音辨識，請安裝 Google STT');
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