import 'dart:async'; // Required for Stream
import 'dart:typed_data';

class DescriptionResponse {
  final Uint8List audioByteStream;
  final int? contentLength;
  final String description;
  final String conversationId;

  DescriptionResponse({
    required this.audioByteStream,
    this.contentLength,
    required this.description,
    required this.conversationId,
  });
}
// class DescriptionResponse {
//   final Stream<List<int>> audioByteStream;
//   final int? contentLength;
//   final String description;
//
//   final String conversationId;
//
//   DescriptionResponse({
//     required this.audioByteStream,
//     this.contentLength,
//     required this.description,
//     required this.conversationId,
//   });
// }
