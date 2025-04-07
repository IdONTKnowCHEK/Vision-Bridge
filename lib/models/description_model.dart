import 'dart:async'; // Required for Stream
import 'dart:typed_data';

class DescriptionResponse {
  final String description;
  final String conversationId;

  DescriptionResponse({
    required this.description,
    required this.conversationId,
  });
}

class AudioResponse {
  final Uint8List audioByteStream;

  AudioResponse({
    required this.audioByteStream,
  });
}
