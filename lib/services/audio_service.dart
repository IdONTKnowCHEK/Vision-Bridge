import 'dart:ffi';

import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
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

  static Future<void> pauseAudio() async {
    await _audioPlayer.pause();
  }


  static Future<void> disposeAudio() async {
    await _audioPlayer.dispose();
  }

  static Future<void> playAndWait(String audioPath) async {
    await _audioPlayer.setLoopMode(LoopMode.off);
    await _audioPlayer.setAsset(audioPath);
    await _audioPlayer.setVolume(0.5);
    await _audioPlayer.play();

    // 等待音檔播放完畢
    await _audioPlayer.playerStateStream.firstWhere(
            (state) => state.processingState == ProcessingState.completed
    );
  }

  static Future<void> play(String audioPath) async {
    await _audioPlayer.setLoopMode(LoopMode.off);
    await _audioPlayer.setAsset(audioPath);
    await _audioPlayer.setVolume(0.3);
    _audioPlayer.play();

  }

  static Future<void> playLoop(String audioPath) async {
    await _audioPlayer.setAsset(audioPath);
    await _audioPlayer.setVolume(0.3);

    _audioPlayer.setLoopMode(LoopMode.one);
    _audioPlayer.play();
  }


  static Future<void> playFromBytesAndWait(
      Uint8List audioByteStream,
      String? conversationId, {
        double volume = 0.5,
      }) async {
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/audio_$conversationId.mp3');
    await tempFile.writeAsBytes(audioByteStream);

    await _audioPlayer.setFilePath(tempFile.path);
    await _audioPlayer.setVolume(volume);

    try {
      await _audioPlayer.setLoopMode(LoopMode.off);
      await _audioPlayer.stop();
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
