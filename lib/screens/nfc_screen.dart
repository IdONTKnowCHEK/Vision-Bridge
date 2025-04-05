import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import '../services/audio_service.dart';
import '../services/speech_service.dart';
import '../services/api_service.dart';
import '../utils/constants.dart';

class NfcScreen extends StatefulWidget {
  final String country;

  const NfcScreen({super.key, required this.country});

  @override
  State<NfcScreen> createState() => _NfcScreenState();
}

class _NfcScreenState extends State<NfcScreen> {
  bool _isNfcAvailable = false;
  bool _isProcessing = false;
  String _nfcStatus = '正在初始化 NFC...';
  String _nfcContent = '';
  String _description = '';
  String? _conversationId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initNfc();
    });
  }

  Future<void> _initNfc() async {
    if (!mounted) return;

    // 檢查設備是否支援 NFC
    final isAvailable = await NfcManager.instance.isAvailable();

    if (!mounted) return;

    setState(() {
      _isNfcAvailable = isAvailable;
      _nfcStatus = isAvailable ? '正在播放音訊提示...' : '此設備不支援 NFC 功能';
    });

    // 根據NFC支援情況播放相應的音訊
    if (isAvailable) {
      await AudioService.playAndWait(AppConstants.supportNfcAudio);
      if (!mounted) return;

      setState(() {
        _nfcStatus = '請靠近 NFC 裝置...';
      });

      _startNfcDetection();
    } else {
      // 不支援 NFC，播放相應提示
      await AudioService.playAndWait(AppConstants.notSupportNfcAudio);
      if (!mounted) return;

      setState(() {
        _nfcStatus = '此設備不支援 NFC 功能，無法進行 NFC 掃描';
      });

      // test
      await _processNfcContentForTest('1');
    }
  }

// 啟動 NFC 掃描
  void _startNfcDetection() {
    // 確保任何現有會話已經停止
    NfcManager.instance.stopSession().then((_) {
      // 然後開始新的會話
      NfcManager.instance.startSession(
        onDiscovered: (NfcTag tag) async {
          // 立即停止會話，避免重複讀取
          await NfcManager.instance.stopSession();

          if (!mounted || _isProcessing) return;

          setState(() {
            _isProcessing = true;
            _nfcStatus = '正在讀取 NFC 標籤...';
          });

          // 讀取 NFC 標籤中的 TEXT 資料
          String? textContent = _readNdefText(tag);

          if (!mounted) return;

          if (textContent != null) {
            setState(() {
              _nfcContent = textContent;
              _nfcStatus = '已讀取 NFC 內容，正在處理...';
            });

            // 發送 NFC 內容和國家到 API
            await _processNfcContentWithApi(textContent);
          } else {
            setState(() {
              _nfcStatus = '無法讀取 NFC 文字內容，請再試一次';
              _isProcessing = false;
            });

            // 讀取失敗時重新啟動掃描
            _startNfcDetection();
          }
        },
      ).catchError((e) {
        if (mounted) {
          setState(() {
            _nfcStatus = 'NFC 掃描啟動失敗: $e';
            _isProcessing = false;
          });
        }
      });
    }).catchError((e) {
      if (mounted) {
        setState(() {
          _nfcStatus = '停止先前 NFC 會話失敗: $e';
        });
      }
    });
  }


  // 從 NFC 標籤中讀取 TEXT 記錄
  String? _readNdefText(NfcTag tag) {
    try {
      // 獲取 NDEF 消息
      final ndefTag = Ndef.from(tag);
      if (ndefTag == null) return null;

      final cachedMessage = ndefTag.cachedMessage;
      if (cachedMessage == null) return null;

      // 遍歷所有記錄查找文本類型
      for (final record in cachedMessage.records) {
        // 檢查是否為 TEXT 類型記錄
        if (record.typeNameFormat == NdefTypeNameFormat.nfcWellknown &&
            String.fromCharCodes(record.type) == "T") {

          final payload = record.payload;
          if (payload.isEmpty) continue;

          // 第一個字節包含狀態和語言代碼長度
          final statusByte = payload[0];
          final languageCodeLength = statusByte & 0x3F;

          // UTF-8 或 UTF-16 標誌
          final isUtf8 = (statusByte & 0x80) == 0;

          // 跳過語言代碼獲取實際文本
          final textOffset = 1 + languageCodeLength;
          if (textOffset >= payload.length) continue;

          final textBytes = payload.sublist(textOffset);

          // 根據編碼解碼文本
          if (isUtf8) {
            return String.fromCharCodes(textBytes);
          } else {
            // 處理 UTF-16，這裡簡化處理
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

  // 處理 NFC 內容和發送到 API
  Future<void> _processNfcContentWithApi(String nfcContent) async {
    if (!mounted) return;
    try {
      // 發送 NFC 內容和國家到 API
      final response = await ApiService.processNfcContent(nfcContent, widget.country);
      if (!mounted) return;

      // 儲存回應
      setState(() {
        _description = response.description;
        _conversationId = response.conversationId;
        _nfcStatus = '正在播放描述音訊...';
      });

      // 直接播放 API 回傳的音訊字節資料
      await AudioService.playFromBytesAndWait(response.audioByteStream, response.contentLength);

      if (!mounted) return;

      setState(() {
        _nfcStatus = '描述播放完成，準備掃描下一個 NFC 標籤';
        _isProcessing = false;
      });
      _startNfcDetection();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _nfcStatus = '處理 NFC 內容時出錯: $e';
        _isProcessing = false;
      });
      _startNfcDetection();
    }
  }
// 在不支援 NFC 的測試情況下使用
  Future<void> _processNfcContentForTest(String testContent) async {
    if (!mounted) return;
    try {
      // 發送測試內容到 API
      final response = await ApiService.processNfcContent(testContent, widget.country);
      if (!mounted) return;

      // 儲存回應
      setState(() {
        _description = response.description;
        _conversationId = response.conversationId;
        _nfcStatus = '正在播放描述音訊...';
      });

      // 直接播放 API 回傳的音訊字節資料
      await AudioService.playFromBytesAndWait(response.audioByteStream, response.contentLength);

      if (!mounted) return;

      setState(() {
        _nfcStatus = '描述播放完成，測試結束';
      });

    } catch (e) {
      if (!mounted) return;

      setState(() {
        _nfcStatus = '處理測試內容時出錯: $e';
      });
    }
  }
  @override
  void dispose() {
    if (_isNfcAvailable) {
      NfcManager.instance.stopSession();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NFC 偵測'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '當前國家: ${widget.country}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),
            Icon(
              Icons.nfc ,
              size: 80,
              color: _isProcessing ? Colors.orange : (_isNfcAvailable ? Colors.blue : Colors.grey),
            ),
            const SizedBox(height: 20),
            Text(
              _nfcStatus,
              style: const TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            if (_nfcContent.isNotEmpty) ...[
              const SizedBox(height: 30),
              const Divider(),
              const SizedBox(height: 10),
              const Text(
                'NFC 內容:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _nfcContent,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
            if (_description.isNotEmpty) ...[
              const SizedBox(height: 30),
              const Divider(),
              const SizedBox(height: 10),
              const Text(
                '描述:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Text(
                  _description,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              if (_conversationId != null) ...[
                const SizedBox(height: 15),
                Text(
                  '對話 ID: $_conversationId',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}