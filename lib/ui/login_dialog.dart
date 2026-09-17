import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class LoginDialog extends StatefulWidget {
  final VoidCallback onLoginSuccess;

  const LoginDialog({super.key, required this.onLoginSuccess});

  @override
  State<LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<LoginDialog> {
  final ApiService _api = ApiService();
  DeviceCodeResponse? _info;
  bool _loading = true;
  String _error = '';
  Timer? _pollTimer;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _startLogin();
  }

  void _startLogin() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final info = await _api.startDeviceLogin();
      setState(() {
        _info = info;
        _loading = false;
      });
      _startPolling(info);
    } catch (e) {
      setState(() {
        _error = '获取登录二维码失败: $e';
        _loading = false;
      });
    }
  }

  void _startPolling(DeviceCodeResponse info) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(Duration(seconds: info.interval > 0 ? info.interval : 2), (timer) async {
      try {
        final success = await _api.pollDeviceLogin(info.deviceCode);
        if (success) {
          timer.cancel();
          if (mounted) {
            Navigator.pop(context);
            widget.onLoginSuccess();
          }
        }
      } catch (_) {}
    });
  }

  void _copyCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _api.cancelLogin();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF141822),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF263042)),
      ),
      child: Container(
        width: 380,
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.blueAccent, size: 24),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '扫码授权百度网盘',
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '用于获取分享资源与解析高速直链',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white38, size: 20),
                  onPressed: () => Navigator.pop(context),
                  tooltip: '关闭',
                ),
              ],
            ),
            const SizedBox(height: 24),

            // QR Code Container
            Container(
              width: 220,
              height: 220,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
                  : _error.isNotEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
                                const SizedBox(height: 8),
                                const Text('获取二维码失败', style: TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text(
                                  _error.length > 80 ? '${_error.substring(0, 80)}...' : _error,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.black54, fontSize: 10),
                                ),
                                const SizedBox(height: 8),
                                ElevatedButton.icon(
                                  onPressed: _startLogin,
                                  icon: const Icon(Icons.refresh, size: 14),
                                  label: const Text('重试', style: TextStyle(fontSize: 12)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blueAccent,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            _info?.qrcodeUrl ?? '',
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Image.network(
                              '${_api.baseUrl}/api/auth/qrcode?url=${Uri.encodeComponent(_info?.qrcodeUrl ?? '')}',
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: Text(
                                    '二维码加载失败\n可使用下方设备码授权',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.black54, fontSize: 11),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
            ),
            const SizedBox(height: 20),

            // User Code
            if (_info != null && _info!.userCode.isNotEmpty) ...[
              const Text(
                '或在手机端百度网盘 App 输入设备码：',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => _copyCode(_info!.userCode),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2636),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _info!.userCode,
                        style: const TextStyle(
                          color: Colors.blueAccent,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        _copied ? Icons.check : Icons.copy,
                        color: _copied ? Colors.greenAccent : Colors.white54,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Polling Radar indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.blueAccent.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  '请使用手机【百度网盘 App】扫一扫授权',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
