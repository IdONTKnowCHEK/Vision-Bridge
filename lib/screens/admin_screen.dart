import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:nfc_manager/nfc_manager.dart';

class AdminPanel extends StatefulWidget {
  const AdminPanel({super.key});

  @override
  State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel> {
  File? _image;
  final ImagePicker _picker = ImagePicker();
  bool _isUploading = false;
  Map<String, dynamic>? _responseData;
  String? _errorMessage;
  bool _isNfcAvailable = false;
  bool _isWritingToNfc = false;
  String? _nfcStatus;

  @override
  void initState() {
    super.initState();
    _checkNfcAvailability();
  }

  Future<void> _checkNfcAvailability() async {
    bool isAvailable = await NfcManager.instance.isAvailable();
    setState(() {
      _isNfcAvailable = isAvailable;
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _selectImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery);

      if (pickedFile != null) {
        setState(() {
          _image = File(pickedFile.path);
          _responseData = null;
          _errorMessage = null;
          _nfcStatus = null;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error selecting image: $e';
      });
    }
  }

  Future<void> _uploadImage() async {
    if (_image == null) {
      setState(() {
        _errorMessage = '請先選擇一張圖片';
      });
      return;
    }

    setState(() {
      _isUploading = true;
      _errorMessage = null;
    });

    try {
      // Create multipart request
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('http://140.120.13.244:11320/upload-image'), // Replace with your actual API endpoint
      );

      // Attach image file to request
      request.files.add(
        await http.MultipartFile.fromPath(
          'image', // This field name should match what your API expects
          _image!.path,
        ),
      );

      // Send the request
      final response = await request.send();
      final responseString = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        setState(() {
          _responseData = json.decode(responseString);
          _isUploading = false;
        });
      } else {
        setState(() {
          _errorMessage = '上傳失敗：${response.statusCode} - $responseString';
          _isUploading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '上傳發生錯誤：$e';
        _isUploading = false;
      });
    }
  }

  // Function to write draw_id to NFC tag
  Future<void> _writeToNfc() async {
    if (_responseData == null || _responseData!['draw_id'] == null) {
      setState(() {
        _nfcStatus = '沒有可寫入的 draw_id';
      });
      return;
    }

    setState(() {
      _isWritingToNfc = true;
      _nfcStatus = '請將 NFC 標籤靠近手機';
    });

    try {
      // Start NFC session
      await NfcManager.instance.startSession(
        onDiscovered: (NfcTag tag) async {
          try {
            final String drawId = _responseData!['draw_id'];

            // Create a simple NDEF text record
            final ndefRecord = NdefRecord.createText(drawId);
            final ndefMessage = NdefMessage([ndefRecord]);

            // Try to write to the tag
            final ndefFormatable = Ndef.from(tag);

            if (ndefFormatable != null) {
              await ndefFormatable.write(ndefMessage);

              setState(() {
                _nfcStatus = '已成功寫入到 NFC 標籤';
                _isWritingToNfc = false;
              });

              // Stop the session after successful write
              NfcManager.instance.stopSession();
            } else {
              setState(() {
                _nfcStatus = '此 NFC 標籤不支援 NDEF 格式';
                _isWritingToNfc = false;
              });
              NfcManager.instance.stopSession(errorMessage: 'NFC tag is not NDEF formatable');
            }
          } catch (e) {
            setState(() {
              _nfcStatus = '寫入 NFC 失敗: $e';
              _isWritingToNfc = false;
            });
            NfcManager.instance.stopSession(errorMessage: 'Write failed: $e');
          }
        },
      );
    } catch (e) {
      setState(() {
        _nfcStatus = 'NFC 操作失敗: $e';
        _isWritingToNfc = false;
      });
    }
  }

  // Cancel ongoing NFC session
  void _cancelNfcWrite() {
    NfcManager.instance.stopSession();
    setState(() {
      _isWritingToNfc = false;
      _nfcStatus = 'NFC 寫入已取消';
    });
  }

  Widget _buildResponseView() {
    if (_responseData == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '上傳成功',
            style: TextStyle(
              color: Colors.greenAccent,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _buildResponseField('圖片 ID', _responseData!['draw_id']),
          _buildResponseField('原始檔名', _responseData!['original_filename']),
          _buildResponseField('儲存檔名', _responseData!['saved_filename']),
          _buildResponseField('檔案路徑', _responseData!['filepath']),
          _buildResponseField('上傳時間', _responseData!['upload_time']),
          _buildResponseField('檔案大小', '${_responseData!['file_size']} bytes'),
          _buildResponseField('檔案類型', _responseData!['file_type']),
          const SizedBox(height: 16),
          const Text(
            '圖片描述',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            _responseData!['description'],
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 16),
          _buildResponseField('藝術概念', _responseData!['artistic_conception']),
          const SizedBox(height: 16),
          const Text(
            '色彩',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: (_responseData!['color'] as List)
                .map((color) => Chip(
              label: Text(
                color,
                style: const TextStyle(color: Colors.black87),
              ),
              backgroundColor: Colors.white70,
            ))
                .toList(),
          ),
          if (_isNfcAvailable) ...[
            const SizedBox(height: 24),
            const Divider(color: Colors.white30),
            const SizedBox(height: 8),
            Center(
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isWritingToNfc ? null : _writeToNfc,
                  icon: const Icon(Icons.nfc),
                  label: const Text('寫入到 NFC 標籤'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                  ),
                ),
              ),
            ),

            if (_nfcStatus != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _nfcStatus!.contains('成功')
                      ? Colors.green.withOpacity(0.2)
                      : Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Center(
                        child: Text(
                          _nfcStatus!,
                          style: TextStyle(
                            color: _nfcStatus!.contains('成功')
                                ? Colors.greenAccent
                                : Colors.orangeAccent,
                          ),
                        ),
                      ),
                    ),
                    if (_isWritingToNfc) ...[
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: _cancelNfcWrite,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(80, 36),
                        ),
                        child: const Text('取消'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildResponseField(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          Expanded(
            child: Text(
              value.toString(),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('圖片上傳'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
      ),
      body: Container(
        padding: const EdgeInsets.all(16.0),
        color: const Color(0xFF1B1B1B),
        child: ListView(
          children: [
            ElevatedButton.icon(
              onPressed: _selectImage,
              icon: const Icon(Icons.photo_library),
              label: const Text('選擇圖片'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 16),
            if (_image != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  _image!,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isUploading ? null : _uploadImage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: _isUploading
                    ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                  ],
                )
                    : const Text('上傳圖片'),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
            _buildResponseView(),
          ],
        ),
      ),
    );
  }
}