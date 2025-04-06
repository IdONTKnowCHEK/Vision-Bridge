import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/country_model.dart';
import '../models/description_model.dart';

class ApiService {
  static const String baseUrl = 'http://140.120.13.244:11304'; // 替換為實際的 API URL

  static Future<CountryResponse> sendCountry(String text) async {
    return CountryResponse(success: true, mappingCountry: '日本');

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/process_text'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return CountryResponse.fromJson(data);
      } else {
        throw Exception('API 請求失敗: ${response.statusCode}');
        // return CountryResponse(success: false, mappingCountry: '');
      }
    } catch (e) {
      throw Exception('API 連接錯誤: $e');
    }
  }

  static Future<DescriptionResponse> processNfcContent(String nfcContent,
      String country) async {
    final url = Uri.parse('$baseUrl/tts');
    final headers = {'Content-Type': 'application/json'};
    final body = jsonEncode({
      'nfcContent': nfcContent,
      'country': country, // Example country
    });

    final client = http.Client();

    try {
      final response = await client.post(
        url,
        headers: headers,
        body: body,
      );

      final conversationId = response.headers['x-conversation-id'] ?? '';
      final encodedDescription = response.headers['x-description'] ?? '';

      if (response.statusCode == 200) {
        String? decodedDescription;
        if (encodedDescription != null) {
          try {
            // Decode the URL-encoded description
            decodedDescription = Uri.decodeComponent(encodedDescription);
          } catch (e) {
            print("Error decoding description: $e");
            decodedDescription = "Error decoding description"; // Show error
          }
        } else {
          decodedDescription = "Description header not found";
        }
        return DescriptionResponse(
          audioByteStream: response.bodyBytes,
          // contentLength:contentLength,
          description: decodedDescription ?? '',
          conversationId: conversationId ?? '',
        );
      } else {
        print('API 處理 NFC 內容請求失敗: ${response.statusCode}');
        throw Exception('API 處理 NFC 內容請求失敗: ${response.statusCode}');
      }
    } catch (e) {
      print('API 處理 NFC 內容連接錯誤: $e');
      throw Exception('API 處理 NFC 內容連接錯誤: $e');
    }
  }

  static Future<DescriptionResponse> processSpeechContent(String speechText,
      String conversationId,) async {
    final url = Uri.parse('$baseUrl/tts_q');
    final headers = {'Content-Type': 'application/json'};
    final body = jsonEncode({
      'query': speechText,
      'conversationId': conversationId,
    });

    final client = http.Client();

    try {
      final response = await client.post(
        url,
        headers: headers,
        body: body,
      );

      final conversationId = response.headers['x-conversation-id'] ?? '';
      final encodedDescription = response.headers['x-description'] ?? '';

      if (response.statusCode == 200) {
        String? decodedDescription;
        if (encodedDescription != null) {
          try {
            // Decode the URL-encoded description
            decodedDescription = Uri.decodeComponent(encodedDescription);
          } catch (e) {
            print("Error decoding description: $e");
            decodedDescription = "Error decoding description"; // Show error
          }
        } else {
          decodedDescription = "Description header not found";
        }
        return DescriptionResponse(
          audioByteStream: response.bodyBytes,
          description: decodedDescription ?? '',
          conversationId: conversationId ?? '',
        );
      } else {
        print('API 處理 NFC 內容請求失敗: ${response.statusCode}');
        throw Exception('API 處理 NFC 內容請求失敗: ${response.statusCode}');
      }
    } catch (e) {
      print('API 處理 NFC 內容連接錯誤: $e');
      throw Exception('API 處理 NFC 內容連接錯誤: $e');
    }
  }
}