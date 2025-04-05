import 'dart:async';
import 'package:nfc_manager/nfc_manager.dart';
import 'dart:convert';

class NFCService {
  StreamController<NfcTag>? _tagStreamController;
  bool _isScanning = false;

  Stream<NfcTag>? get tagStream => _tagStreamController?.stream;
  bool get isScanning => _isScanning;

  // 開始 NFC 掃描
  Future<void> startNFCScanning() async {
    if (_isScanning) return;

    try {
      // 檢查 NFC 是否可用
      final isAvailable = await NfcManager.instance.isAvailable();
      if (!isAvailable) {
        throw Exception('NFC 不可用');
      }

      _tagStreamController = StreamController<NfcTag>.broadcast();
      _isScanning = true;

      // 開始監聽 NFC 標籤
      NfcManager.instance.startSession(
        onDiscovered: (NfcTag tag) async {
          // 發送到流
          if (_tagStreamController != null && !_tagStreamController!.isClosed) {
            _tagStreamController!.add(tag);
          }
        },
        onError: (error) async {
          print('NFC 錯誤: $error');
        },
      );
    } catch (e) {
      print('啟動 NFC 掃描錯誤: $e');
      stopNFCScanning();
      rethrow;
    }
  }

  // 停止 NFC 掃描
  Future<void> stopNFCScanning() async {
    if (!_isScanning) return;

    _isScanning = false;

    try {
      await NfcManager.instance.stopSession();
    } catch (e) {
      print('停止 NFC 掃描錯誤: $e');
    } finally {
      await _tagStreamController?.close();
      _tagStreamController = null;
    }
  }

  // 處理讀取到的 NFC 標籤
  Future<Map<String, dynamic>> processNFCTag(NfcTag tag) async {
    Map<String, dynamic> result = {'raw': tag};

    // 獲取標籤 ID
    String tagId = '';

    // 處理不同類型的 NFC 標籤
    if (tag.data.containsKey('nfca')) {
      final nfca = tag.data['nfca'];
      tagId = nfca['identifier'].map((e) => e.toRadixString(16).padLeft(2, '0')).join('').toUpperCase();
      result['type'] = 'NFC-A';
    } else if (tag.data.containsKey('nfcb')) {
      final nfcb = tag.data['nfcb'];
      tagId = nfcb['identifier'].map((e) => e.toRadixString(16).padLeft(2, '0')).join('').toUpperCase();
      result['type'] = 'NFC-B';
    } else if (tag.data.containsKey('nfcf')) {
      final nfcf = tag.data['nfcf'];
      tagId = nfcf['identifier'].map((e) => e.toRadixString(16).padLeft(2, '0')).join('').toUpperCase();
      result['type'] = 'NFC-F';
    } else if (tag.data.containsKey('nfcv')) {
      final nfcv = tag.data['nfcv'];
      tagId = nfcv['identifier'].map((e) => e.toRadixString(16).padLeft(2, '0')).join('').toUpperCase();
      result['type'] = 'NFC-V';
    } else if (tag.data.containsKey('isodep')) {
      final isodep = tag.data['isodep'];
      tagId = isodep['historicalBytes']?.map((e) => e.toRadixString(16).padLeft(2, '0')).join('').toUpperCase() ?? '';
      result['type'] = 'ISO-DEP';
    } else if (tag.data.containsKey('mifare')) {
      final mifare = tag.data['mifare'];
      tagId = mifare['identifier'].map((e) => e.toRadixString(16).padLeft(2, '0')).join('').toUpperCase();
      result['type'] = 'MIFARE';
    }

    result['id'] = tagId;

    // 讀取 NDEF 數據（如果可用）
    try {
      if (Ndef.from(tag) != null) {
        final ndef = Ndef.from(tag);
        final cachedMessage = ndef?.cachedMessage;

        if (cachedMessage != null) {
          List<Map<String, dynamic>> records = [];

          for (var record in cachedMessage.records) {
            Map<String, dynamic> recordData = {
              'typeNameFormat': record.typeNameFormat.index,
              'type': String.fromCharCodes(record.type),
              'payload': record.payload,
            };

            // 嘗試解析文本記錄
            if (record.typeNameFormat == NdefTypeNameFormat.nfcWellknown &&
                record.type.isNotEmpty && record.type[0] == 0x54) { // 'T' for Text
              try {
                recordData['text'] = _decodeTextRecord(record.payload);
              } catch (e) {
                print('文本解析錯誤: $e');
              }
            }

            // 嘗試解析 URI 記錄
            if (record.typeNameFormat == NdefTypeNameFormat.nfcWellknown &&
                record.type.isNotEmpty && record.type[0] == 0x55) { // 'U' for URI
              try {
                recordData['uri'] = _decodeUriRecord(record.payload);
              } catch (e) {
                print('URI 解析錯誤: $e');
              }
            }

            records.add(recordData);
          }

          result['ndef'] = {
            'isWritable': ndef?.isWritable ?? false,
            'maxSize': ndef?.maxSize ?? 0,
            'records': records,
          };
        }
      }
    } catch (e) {
      print('NDEF 讀取錯誤: $e');
    }

    return result;
  }

  // 解析文本記錄
  String _decodeTextRecord(List<int> payload) {
    if (payload.isEmpty) return '';

    final statusByte = payload[0];
    final languageCodeLength = statusByte & 0x3F;
    final isUtf16 = (statusByte & 0x80) != 0;

    if (1 + languageCodeLength < payload.length) {
      final textBytes = payload.sublist(1 + languageCodeLength);
      final text = isUtf16
          ? String.fromCharCodes(textBytes)
          : utf8.decode(textBytes);
      return text;
    }

    return '';
  }

  // 解析 URI 記錄
  String _decodeUriRecord(List<int> payload) {
    if (payload.isEmpty) return '';

    final prefixCode = payload[0];
    final uriBytes = payload.sublist(1);
    final uri = utf8.decode(uriBytes);

    // URI 前綴列表
    final prefixes = [
      '', 'http://www.', 'https://www.', 'http://', 'https://', 'tel:', 'mailto:',
      'ftp://anonymous:anonymous@', 'ftp://ftp.', 'ftps://', 'sftp://',
      'smb://', 'nfs://', 'ftp://', 'dav://', 'news:', 'telnet://',
      'imap:', 'rtsp://', 'urn:', 'pop:', 'sip:', 'sips:', 'tftp:',
      'btspp://', 'btl2cap://', 'btgoep://', 'tcpobex://', 'irdaobex://',
      'file://', 'urn:epc:id:', 'urn:epc:tag:', 'urn:epc:pat:', 'urn:epc:raw:',
      'urn:epc:', 'urn:nfc:'
    ];

    if (prefixCode < prefixes.length) {
      return prefixes[prefixCode] + uri;
    }

    return uri;
  }

  // 釋放資源
  void dispose() {
    stopNFCScanning();
  }
}

