import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';


class SpeechService {
  static final SpeechToText _speech = SpeechToText();
  static bool _isInitialized = false;

  static Future<bool> checkPermissionAndInit() async {
    final micStatus = await Permission.microphone.request();
    if (micStatus.isGranted) {
      _isInitialized = await _speech.initialize(
        onStatus: (status) {
          if (status == 'listening' || status == 'notListening') {
            HapticFeedback.vibrate();
          }
        },
      );
      return _isInitialized;
    }
    return false;
  }

  static Future<bool> isSTTAvailable() async {
    if (!_isInitialized) {
      _isInitialized = await _speech.initialize(
        onStatus: (status) {
          if (status == 'listening' || status == 'notListening') {
            HapticFeedback.vibrate();
          }
        },
      );
    }
    return _isInitialized;
  }

  static Future<String> listenAndWait() async {
    if (!_isInitialized) {
      await checkPermissionAndInit();
    }

    String recognizedText = '';

    if (_speech.isAvailable) {
      await _speech.listen(
        onResult: (result) {
          recognizedText = result.recognizedWords;
        },
        listenFor: const Duration(seconds: 10),
        localeId: 'zh_TW',
      );

      while (_speech.isListening) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    return recognizedText;
  }

  static void stopListening() {
    if (_speech.isListening) {
      _speech.stop();
    }
  }
  static bool isListening() {
    return _speech.isListening;
  }
}