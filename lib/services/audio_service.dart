import 'package:just_audio/just_audio.dart';
import 'dart:typed_data';

class AudioService {
  static final AudioPlayer _audioPlayer = AudioPlayer();

  static Future<void> playAudio(String audioPath) async {
    await _audioPlayer.setAsset(audioPath);
    await _audioPlayer.play();
  }

  static Future<void> stopAudio() async {
    await _audioPlayer.stop();
  }

  static Future<void> disposeAudio() async {
    await _audioPlayer.dispose();
  }

  static Future<void> playAndWait(String audioPath) async {
    await _audioPlayer.setAsset(audioPath);
    await _audioPlayer.play();

    // 等待音檔播放完畢
    await _audioPlayer.playerStateStream.firstWhere(
            (state) => state.processingState == ProcessingState.completed
    );
  }

  static Future<void> playFromBytesAndWait(Uint8List audioByteStream, int? contentLength) async {

    await _audioPlayer.setAudioSource(
      ProgressiveAudioSource(
        Uri.dataFromBytes(
          audioByteStream,
          mimeType: 'audio/mpeg',
        ),
      ),
    );

    try {
      await _audioPlayer.play();
      await _audioPlayer.playerStateStream.firstWhere(
              (state) => state.processingState == ProcessingState.completed
      );
    } on PlayerException catch (e) {
      print("Error during audio playback setup/start: ${e.message}");
    } on PlayerInterruptedException catch (e) {
      print("Audio playback interrupted: ${e.message}");
    } catch (e) {
      throw Exception('無法播放音訊字節資料: $e');
    }
  }
}
