import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/country_model.dart';
import '../models/description_model.dart';
import 'dart:convert';

class ApiService {
  static const String baseUrl = 'http://140.120.13.244:11320';

  static Future<CountryResponse> sendCountry(String text) async {
    // return CountryResponse(success: true, mappingCountry: '大中華民族');

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/race'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'content': text}),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        return CountryResponse.fromJson(decoded);
      } else {
        throw Exception('API 請求失敗: ${response.statusCode}');
        // return CountryResponse(success: false, mappingCountry: '');
      }
    } catch (e) {
      throw Exception('API 連接錯誤: $e');
    }
  }



  static Future<DescriptionResponse> processNfcContent(String nfcContent, String country, String? customColor) async {
    final url = Uri.parse('$baseUrl/description');
    final headers = {'Content-Type': 'application/json'};
    final body = jsonEncode({
      'draw_id': nfcContent,
      'country': country,
      // 'custom_color': customColor ?? ' ',
    });

    final client = http.Client();

    try {
      final response = await client.post(
        url,
        headers: headers,
        body: body,
      );

      // final conversationId = response.headers['x-conversation-id'] ?? '';
      // final encodedDescription = response.headers['x-description'] ?? '';

      if (response.statusCode == 200) {

        final data = jsonDecode(utf8.decode(response.bodyBytes));

        // String? decodedDescription;
        // if (encodedDescription != null) {
        //   try {
        //     // Decode the URL-encoded description
        //     decodedDescription = Uri.decodeComponent(encodedDescription);
        //   } catch (e) {
        //     print("Error decoding description: $e");
        //     decodedDescription = "Error decoding description"; // Show error
        //   }
        // } else {
        //   decodedDescription = "Description header not found";
        // }
        return DescriptionResponse(
          conversationId: data['conversation_id'] ?? '',
          description: data['description'] ?? ''
        );
      } else {
        print('API 處理 NFC 內容請求失敗: ${response.statusCode}');
        return DescriptionResponse(
            conversationId: 'error',
            description: 'error'
        );
      }
    } catch (e) {
      print('API 處理 NFC 內容連接錯誤: $e');
      return DescriptionResponse(
          conversationId: 'error',
          description: 'error'
      );
    }
  }

  static Future<DescriptionResponse> processSpeechContent(String speechText, String conversationId, String country) async {
    final url = Uri.parse('$baseUrl/chat');
    final headers = {'Content-Type': 'application/json'};
    final body = jsonEncode({
      'question': speechText,
      'conversation_id': conversationId,
      'country': country
    });

    final client = http.Client();

    try {
      final response = await client.post(
        url,
        headers: headers,
        body: body,
      );

      final data = jsonDecode(utf8.decode(response.bodyBytes));


      if (response.statusCode == 200) {
        return DescriptionResponse(
            conversationId: data['conversation_id'] ?? '',
            description: data['description'] ?? ''
        );
      } else {
        print('API 處理 NFC 內容請求失敗: ${response.statusCode}');
        return DescriptionResponse(
          // audioByteStream: Uint8List(0),
          description:  'error',
          conversationId:  '',
        );
        // throw Exception('API 處理 NFC 內容請求失敗: ${response.statusCode}');
      }
    } catch (e) {
      print('API 處理 NFC 內容連接錯誤: $e');
      return DescriptionResponse(
        // audioByteStream: Uint8List(0),
        description: 'error',
        conversationId: '',
      );
      // throw Exception('API 處理 NFC 內容連接錯誤: $e');
    }
  }

  static Future<AudioResponse> processTTS(String speechText) async {
    final url = Uri.parse('$baseUrl/tts');
    final headers = {'Content-Type': 'application/json'};
    final body = jsonEncode({
      'text': speechText,
    });

    final client = http.Client();

    try {
      final response = await client.post(
        url,
        headers: headers,
        body: body,
      );

      if (response.statusCode == 200) {
        return AudioResponse(
          audioByteStream: response.bodyBytes,
        );
      } else {
        print('API 處理 NFC 內容請求失敗: ${response.statusCode}');
        return AudioResponse(
          audioByteStream: Uint8List(0),
        );
        // throw Exception('API 處理 NFC 內容請求失敗: ${response.statusCode}');
      }
    } catch (e) {
      print('API 處理 NFC 內容連接錯誤: $e');
      return AudioResponse(
        audioByteStream: Uint8List(0),
      );
      // throw Exception('API 處理 NFC 內容連接錯誤: $e');
    }
  }


  static Future<AudioResponse> processTTSNan(String speechText) async {
    final url = Uri.parse('http://140.120.182.91:11310/tts-nan');
    final headers = {'Content-Type': 'application/json'};
    final body = jsonEncode({
      'text': speechText,
    });

    final client = http.Client();

    try {
      final response = await client.post(
        url,
        headers: headers,
        body: body,
      );

      if (response.statusCode == 200) {
        return AudioResponse(
          audioByteStream: response.bodyBytes,
        );
      } else {
        print('API 處理 NFC 內容請求失敗: ${response.statusCode}');
        return AudioResponse(
          audioByteStream: Uint8List(0),
        );
        // throw Exception('API 處理 NFC 內容請求失敗: ${response.statusCode}');
      }
    } catch (e) {
      print('API 處理 NFC 內容連接錯誤: $e');
      return AudioResponse(
        audioByteStream: Uint8List(0),
      );
      // throw Exception('API 處理 NFC 內容連接錯誤: $e');
    }
  }


}