import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nfc_manager/nfc_manager.dart';
import '../services/audio_service.dart';
import '../services/speech_service.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../services/microphone_service.dart';
import '../components/audio_visualizer.dart';
import 'dart:math' as math;

import 'admin_screen.dart';

class NfcScreen extends StatefulWidget {
  final String country;

  const NfcScreen({super.key, required this.country});

  @override
  State<NfcScreen> createState() => _NfcScreenState();
}

class _NfcScreenState extends State<NfcScreen> {
  bool _isNfcAvailable = false;
  bool _isProcessing = false;
  String _conversation_Id = '';
  bool _hasValidConversationId = false;
  bool _isListening = false;
  String _recognizedText = '';
  bool _isInConversationFlow = false;
  bool _isCancelled = false;
  bool _isMicrophoneActive = false;
  bool _hasPlayedTapToSpeak = false;
  String? customColor = StorageService.getCustom();


  AudioVisualizerMode _audioMode = AudioVisualizerMode.loading;
  final MicrophoneService _microphoneService = MicrophoneService();

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
    ));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initNfc();
    });
  }

  Future<bool> _activateMicrophone() async {
    if (_isMicrophoneActive) {
      _microphoneService.stopListening();
    }

    bool hasPermission = await _microphoneService.startListening();
    if (mounted) {
      setState(() {
        _isMicrophoneActive = hasPermission;
      });
    }
    return hasPermission;
  }

  void _deactivateMicrophone() {
    if (_isMicrophoneActive) {
      _microphoneService.stopListening();
      setState(() {
        _isMicrophoneActive = false;
      });
    }
  }

  Future<void> _initNfc() async {
    if (!mounted) return;

    final isAvailable = await NfcManager.instance.isAvailable();

    if (!mounted) return;

    setState(() {
      _isNfcAvailable = isAvailable;
      _audioMode = AudioVisualizerMode.systemPlaying;
    });

    if (isAvailable) {
      await AudioService.playAndWait(AppConstants.supportNfcAudio);
      if (!mounted) return;

      setState(() {
        _audioMode = AudioVisualizerMode.loading;
      });
      _startNfcDetection();
    } else {
      await AudioService.playAndWait(AppConstants.notSupportNfcAudio);
      if (!mounted) return;
      setState(() {
        _audioMode = AudioVisualizerMode.loading;
      });
    }
  }



  void _startNfcDetection() {
    if (_isInConversationFlow) {
      print('對話流程進行中，暫時不啟動 NFC 掃描');
      return;
    }

    print('啟動 NFC 掃描');
    NfcManager.instance.stopSession().then((_) {
      NfcManager.instance.startSession(
        onDiscovered: (NfcTag tag) async {
          await NfcManager.instance.stopSession();
          if (!mounted || _isProcessing || _isInConversationFlow) return;
          setState(() {
            _isProcessing = true;
          });

          String? textContent = _readNdefText(tag);
          AudioService.play(AppConstants.triggerNfc);
          await Future.delayed(const Duration(milliseconds: 300));

          print(textContent);
          if (!mounted) return;

          if (textContent != null) {
            await _processNfcContentWithApi(textContent);
          } else {
            print('nfc辨識失敗');
            setState(() {
              _isProcessing = false;
            });
            _startNfcDetection();
          }
        },
      ).catchError((e) {
        if (mounted) {
          print('NFC 啟動會話失敗: $e');
          setState(() {
            _isProcessing = false;
          });
        }
      });
    }).catchError((e) {
      if (mounted) {
        print('停止先前 NFC 會話失敗: $e');
      }
    });
  }

  String? _readNdefText(NfcTag tag) {
    try {
      final ndefTag = Ndef.from(tag);
      if (ndefTag == null) return null;

      final cachedMessage = ndefTag.cachedMessage;
      if (cachedMessage == null) return null;

      for (final record in cachedMessage.records) {
        if (record.typeNameFormat == NdefTypeNameFormat.nfcWellknown &&
            String.fromCharCodes(record.type) == "T") {

          final payload = record.payload;
          if (payload.isEmpty) continue;

          final statusByte = payload[0];
          final languageCodeLength = statusByte & 0x3F;

          final isUtf8 = (statusByte & 0x80) == 0;

          final textOffset = 1 + languageCodeLength;
          if (textOffset >= payload.length) continue;

          final textBytes = payload.sublist(textOffset);

          if (isUtf8) {
            return String.fromCharCodes(textBytes);
          } else {
            return String.fromCharCodes(textBytes);
          }
        }
      }

      return null;
    } catch (e) {
      debugPrint('讀取 NFC 內容時出錯: $e');
      return null;
    }
  }

  Future<void> _processNfcContentWithApi(String nfcContent) async {
    if (!mounted) return;
    try {
      setState(() {
        _audioMode = AudioVisualizerMode.loading;
      });
      final descriptionResponse = await ApiService.processNfcContent(nfcContent, widget.country, customColor);
      if (descriptionResponse.description == 'error') {
        if (!mounted) return;

        setState(() {
          _audioMode = AudioVisualizerMode.systemPlaying;
        });

        AudioService.stopAudio();
        await AudioService.playAndWait(AppConstants.someProblem);

        setState(() {
          _isProcessing = false;
          _audioMode = AudioVisualizerMode.loading;
        });

        if (!_isInConversationFlow) {
          _startNfcDetection();
        }
        return;
      }


      print(descriptionResponse.description);

      AudioService.playLoop(AppConstants.loadingAudio);
      final ttsResponse = await ApiService.processTTS(descriptionResponse.description);

      if (!mounted) return;

      setState(() {
        _conversation_Id = descriptionResponse.conversationId;
        _hasValidConversationId = true;
        _audioMode = AudioVisualizerMode.systemPlaying;
      });


      await AudioService.playFromBytesAndWait(ttsResponse.audioByteStream, descriptionResponse.conversationId);
      // final response = await ApiService.processTTSNan('文字測試');
      // await AudioService.playFromBytesAndWait(response.audioByteStream, 's',  volume: 1.0);
      if (!mounted) return;

      await Future.delayed(const Duration(milliseconds: 300));

      if (_hasValidConversationId && !_hasPlayedTapToSpeak) {
        await AudioService.playAndWait(AppConstants.tapToSpeak);
        _hasPlayedTapToSpeak = true;
      }


      setState(() {
        _isProcessing = false;
        _audioMode = AudioVisualizerMode.loading;
      });

      if (!_isInConversationFlow) {
        _startNfcDetection();
      }
    } catch (e) {
      if (!mounted) return;
      print('處理 NFC 內容時出錯: $e');
      setState(() {
        _isProcessing = false;
        _audioMode = AudioVisualizerMode.loading;
      });

      if (!_isInConversationFlow) {
        _startNfcDetection();
      }
    }
  }


  Future<void> _startListening() async {
    _isCancelled = false;
    setState(() {
      _isProcessing = true;
      _isInConversationFlow = true;
    });

    await NfcManager.instance.stopSession();

    bool micStarted = await _activateMicrophone();
    if (!micStarted) {
      print('麥克風啟動失敗');
      if (mounted) {
        setState(() {
          _audioMode = AudioVisualizerMode.systemPlaying;
        });
        await AudioService.playAndWait(AppConstants.retryAudio);
        await _startListening();
      }
      return;
    }
    await Future.delayed(const Duration(milliseconds: 300));

    if (mounted) {
      setState(() {
        _recognizedText = '';
        _isListening = true;
        _audioMode = AudioVisualizerMode.userSpeaking;
      });
    }

    try {
      final recognizedText = await SpeechService.listenAndWait();
      if (_isCancelled) {
        _resetConversationState();
        return;
      }
      print(recognizedText);

      if (mounted) {
        _deactivateMicrophone();

        setState(() {
          _isListening = false;
          _recognizedText = recognizedText;
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
        await _sendSpeechToApi();
      }
    } catch (e) {
      print('語音辨識錯誤：$e');
      if (_isCancelled) {
        _resetConversationState();
        return;
      }
      if (mounted) {
        _deactivateMicrophone();
        setState(() {
          _audioMode = AudioVisualizerMode.systemPlaying;
        });
        await AudioService.playAndWait(AppConstants.retryAudio);
        await _startListening();
      }
    }
  }
  void _resetConversationState() {
    if (!mounted) return;

    setState(() {
      _isCancelled = false;
      _isProcessing = false;
      _isListening = false;
      _isInConversationFlow = false;
      _audioMode = AudioVisualizerMode.loading;
    });

    _startNfcDetection();
  }
  void _stopListening() async {
    if (!_isListening) return;
    _isCancelled = true;
    SpeechService.stopListening();
    _deactivateMicrophone();

    setState(() {
      _isListening = false;
      _isProcessing = false;
      _audioMode = AudioVisualizerMode.loading;
      _isInConversationFlow = false;
    });


    _startNfcDetection();
  }

  Future<void> _sendSpeechToApi() async {
    if (!mounted) return;

    setState(() {
      _audioMode = AudioVisualizerMode.loading;
    });

    try {
      print('發送語音內容到API: $_recognizedText, conversationId: $_conversation_Id');

      final response = await ApiService.processSpeechContent(
        _recognizedText,
        _conversation_Id,
          widget.country
      );

      if (response.description == 'error') {
        await AudioService.playAndWait(AppConstants.someProblem);

        setState(() {
          _isProcessing = false;
          _audioMode = AudioVisualizerMode.loading;
          _isInConversationFlow = false;
        });

        _startNfcDetection();
        return;
      }


      if (!mounted) return;

      print(response.description);

      AudioService.playLoop(AppConstants.loadingAudio);
      final ttsResponse = await ApiService.processTTS(response.description);

      setState(() {
        _audioMode = AudioVisualizerMode.systemPlaying;
      });

      await AudioService.playFromBytesAndWait(ttsResponse.audioByteStream, response.conversationId);

      if (!mounted) return;

      setState(() {
        _conversation_Id = response.conversationId;
        _isProcessing = false;
        _audioMode = AudioVisualizerMode.loading;
        _isInConversationFlow = false;
      });

      _startNfcDetection();

    } catch (e) {
      print('發送語音內容時出錯: $e');

      await AudioService.playAndWait(AppConstants.nfcNotFound);

      setState(() {
        _isProcessing = false;
        _audioMode = AudioVisualizerMode.loading;
        _isInConversationFlow = false;
      });

      _startNfcDetection();
    }
  }

  @override
  void dispose() {
    if (_isNfcAvailable) {
      NfcManager.instance.stopSession();
    }
    _microphoneService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final double visualizerSize = screenSize.width * 0.7;

    // Store points for gesture detection
    List<Offset> gesturePoints = [];

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: GestureDetector(
        onDoubleTap: _hasValidConversationId && !_isProcessing && !_isListening && !_isInConversationFlow
            ? _startListening
            : null,
        onLongPress: _isListening ? _stopListening : null,
        // Add L gesture detection
        onPanStart: (details) {
          gesturePoints.clear();
          gesturePoints.add(details.localPosition);
        },
        onPanUpdate: (details) {
          gesturePoints.add(details.localPosition);
        },
        onPanEnd: (_) {
          if (_isLGesture(gesturePoints)) {
            _navigateToAdminPage(context);
          }
          gesturePoints.clear();
        },
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF202020),
                Color(0xFF1B1B1B),
              ],
            ),
          ),
          child: SafeArea(
            top: false,
            child: Center(
              child: CircularAudioVisualizer(
                mode: _audioMode,
                size: visualizerSize,
                microphoneVolumeNotifier: _audioMode == AudioVisualizerMode.userSpeaking
                    ? _microphoneService.volumeNotifier
                    : null,
                amplitude: 0.7,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Add these methods to your class
  bool _isLGesture(List<Offset> points) {
    if (points.length < 10) return false; // Need sufficient points for a gesture

    // Get bounding box
    double minX = double.infinity;
    double maxX = 0;
    double minY = double.infinity;
    double maxY = 0;

    for (Offset point in points) {
      minX = math.min(minX, point.dx);
      maxX = math.max(maxX, point.dx);
      minY = math.min(minY, point.dy);
      maxY = math.max(maxY, point.dy);
    }

    double width = maxX - minX;
    double height = maxY - minY;

    // Split points into two segments
    List<Offset> firstHalf = points.sublist(0, points.length ~/ 2);
    List<Offset> secondHalf = points.sublist(points.length ~/ 2);

    // Calculate average directions
    double firstHalfVertical = _calculateVerticalDirection(firstHalf);
    double secondHalfHorizontal = _calculateHorizontalDirection(secondHalf);

    // L shape requirements:
    // 1. First half should move significantly downward
    // 2. Second half should move significantly rightward
    // 3. Overall shape should have sufficient width and height
    return firstHalfVertical > 0.6 && // First segment goes down
        secondHalfHorizontal > 0.6 && // Second segment goes right
        width > 50 && height > 50; // Minimum size requirements
  }

  double _calculateVerticalDirection(List<Offset> points) {
    if (points.isEmpty) return 0;
    double totalVertical = 0;
    double totalMovement = 0;

    for (int i = 1; i < points.length; i++) {
      double dy = points[i].dy - points[i - 1].dy;
      double dx = points[i].dx - points[i - 1].dx;
      double movement = math.sqrt(dx * dx + dy * dy);

      totalVertical += dy > 0 ? movement : -movement;
      totalMovement += movement;
    }

    return totalMovement > 0 ? totalVertical / totalMovement : 0;
  }

  double _calculateHorizontalDirection(List<Offset> points) {
    if (points.isEmpty) return 0;
    double totalHorizontal = 0;
    double totalMovement = 0;

    for (int i = 1; i < points.length; i++) {
      double dx = points[i].dx - points[i - 1].dx;
      double dy = points[i].dy - points[i - 1].dy;
      double movement = math.sqrt(dx * dx + dy * dy);

      totalHorizontal += dx > 0 ? movement : -movement;
      totalMovement += movement;
    }

    return totalMovement > 0 ? totalHorizontal / totalMovement : 0;
  }

  void _navigateToAdminPage(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => AdminPanel(),
      ),
    );
  }
}