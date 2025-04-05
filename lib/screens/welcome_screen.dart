import 'package:flutter/material.dart';
import '../screens/nfc_screen.dart';
import '../services/audio_service.dart';
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

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _isLoading = true;
  bool _isListening = false;
  String _statusMessage = '正在初始化...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initApp();
    });
  }

  Future<void> _initApp() async {
    // 檢查是否為首次啟動
    if (!StorageService.isFirstLaunch()) {
      final country = StorageService.getCountry();
      if (country != null && mounted) {
        Future.microtask(() {
          _navigateToNfcScreen(country);
        });
        return;
      }
    }

    // 首次啟動或沒有保存的國家資訊
    if (mounted) {
      await _checkPermissions();
    }
  }


  Future<void> _checkPermissions() async {
    setState(() {
      _statusMessage = '正在檢查權限...';
    });

    // 檢查麥克風權限
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      setState(() {
        _statusMessage = '需要麥克風權限才能繼續使用，請授予權限後重試';
        _isLoading = false;
      });
      return;
    }

    // 檢查 STT 是否可用
    try {
      final sttAvailable = await SpeechService.isSTTAvailable();
      if (!sttAvailable) {
        setState(() {
          _statusMessage = '您的設備不支援語音辨識功能';
          _isLoading = false;
        });
        return;
      }
    } catch (e) {
      // Handle the exception here
      setState(() {
        _statusMessage = '此裝置無法使用語音辨識，請安裝 Google STT';
        _isLoading = false;
      });

      await AudioService.playAndWait(AppConstants.notSupportSTT);

      return;
    }

    // 權限獲取後，自動播放 start 音訊
    await _playSoundAndListen();
  }

  Future<void> _playSoundAndListen() async {
    try {
      setState(() {
        _statusMessage = '請聆聽指示...';
      });

      // 播放開始音訊
      await AudioService.playAndWait(AppConstants.startAudio);

      // 音訊播放完畢後自動開始語音輸入
      await _startListening();
    } catch (e) {
      setState(() {
        _statusMessage = '音訊播放出錯: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _startListening() async {
    setState(() {
      _isListening = true;
      _statusMessage = '請說話...';
    });

    try {
      final recognizedText = await SpeechService.listenAndWait();

      setState(() {
        _isListening = false;
        _statusMessage = '正在處理: "$recognizedText"';
        _isLoading = true;
      });

      // 檢查是否無語音輸入或輸入內容太短
      if (recognizedText.trim().isEmpty || recognizedText.trim().length < 2) {
        // 語音識別沒有捕捉到有效的內容，播放重試音效
        setState(() {
          _statusMessage = '未偵測到語音，請再試一次';
        });
        await AudioService.playAndWait(AppConstants.retryAudio);
        await _startListening();
        return;
      }
      // 發送識別的文本到 API
      await _processRecognizedText(recognizedText);
    } catch (e) {
      setState(() {
        _isListening = false;
        _statusMessage = '語音識別錯誤: $e';
        _isLoading = false;
      });

      await AudioService.playAndWait(AppConstants.retryAudio);
      await _startListening();
    }
  }

  Future<void> _processRecognizedText(String text) async {
    try {
      final response = await ApiService.sendCountry(text);

      if (response.success) {
        // 成功，播放完成音訊
        await AudioService.playAndWait(AppConstants.doneAudio);

        // 保存國家資訊，標記非首次啟動
        await StorageService.saveCountry(response.mappingCountry);
        await StorageService.setNotFirstLaunch();

        // 導航到 NFC 畫面
        _navigateToNfcScreen(response.mappingCountry);
      } else {
        // 失敗，播放重試音訊
        await AudioService.playAndWait(AppConstants.retryAudio);

        // 自動重新開始語音識別
        await _startListening();
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'API 處理錯誤: $e';
        _isLoading = false;
      });

      // 播放重試音訊
      await AudioService.playAndWait(AppConstants.retryAudio);

      // 自動重新開始語音識別
      await _startListening();
    }
  }

  void _navigateToNfcScreen(String country) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => NfcScreen(country: country),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isLoading)
              const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18),
            ),
            if (_isListening)
              ...[
                const SizedBox(height: 20),
                const Icon(
                  Icons.mic,
                  size: 50,
                  color: Colors.blue,
                ),
              ],
            if (!_isLoading && !_isListening && _statusMessage.contains('權限'))
              ...[
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _checkPermissions,
                  child: const Text('授予權限'),
                ),
              ],
          ],
        ),
      ),
    );
  }
}