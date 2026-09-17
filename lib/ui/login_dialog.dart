import 'dart:async';
import 'dart:io';
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

class _LoginDialogState extends State<LoginDialog> with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  late TabController _tabController;
  final TextEditingController _codeController = TextEditingController();

  // QR Login State
  DeviceCodeResponse? _info;
  bool _loadingQR = true;
  String _qrError = '';
  Timer? _pollTimer;
  bool _codeCopied = false;
  bool _errorCopied = false;

  // Web Auth State
  bool _submittingWebCode = false;
  String _webAuthError = '';
  bool _openingBrowser = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _startQRLogin();
  }

  void _startQRLogin() async {
    setState(() {
      _loadingQR = true;
      _qrError = '';
    });
    try {
      final info = await _api.startDeviceLogin();
      if (!mounted) return;
      setState(() {
        _info = info;
        _loadingQR = false;
      });
      _startPolling(info);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _qrError = e.toString().replaceFirst('Exception: ', '');
        _loadingQR = false;
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

  void _copyUserCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    setState(() => _codeCopied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _codeCopied = false);
    });
  }

  void _copyErrorText(String text) {
    Clipboard.setData(ClipboardData(text: text));
    setState(() => _errorCopied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _errorCopied = false);
    });
  }

  void _openBrowserAuth() async {
    setState(() => _openingBrowser = true);
    try {
      final url = await _api.getAuthUrl();
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', url]);
      }
    } catch (e) {
      final fallbackUrl = await _api.getAuthUrl();
      Clipboard.setData(ClipboardData(text: fallbackUrl));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已复制授权链接，请在浏览器中粘贴打开')),
        );
      }
    } finally {
      if (mounted) setState(() => _openingBrowser = false);
    }
  }

  void _submitAuthCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _webAuthError = '请先输入或粘贴授权码');
      return;
    }
    setState(() {
      _submittingWebCode = true;
      _webAuthError = '';
    });
    try {
      await _api.submitAuthCode(code);
      if (mounted) {
        Navigator.pop(context);
        widget.onLoginSuccess();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _webAuthError = e.toString().replaceFirst('Exception: ', '');
          _submittingWebCode = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _api.cancelLogin();
    _tabController.dispose();
    _codeController.dispose();
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
        width: 440,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.cloud_sync_rounded, color: Colors.blueAccent, size: 24),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '登录百度网盘',
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '授权以解析分享资源并开启原画高速串流',
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
            const SizedBox(height: 18),

            // Tab Bar
            Container(
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF1B2230),
                borderRadius: BorderRadius.circular(10),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.blueAccent.withValues(alpha: 0.3),
                  border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.5)),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: Colors.blueAccent,
                unselectedLabelColor: Colors.white54,
                labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                unselectedLabelStyle: const TextStyle(fontSize: 13),
                tabs: const [
                  Tab(text: '扫码登录'),
                  Tab(text: '网页授权'),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Tab View Content
            _tabController.index == 0 ? _buildQRTab() : _buildWebTab(),
          ],
        ),
      ),
    );
  }

  // --- TAB 1: QR CODE LOGIN ---
  Widget _buildQRTab() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
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
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: _loadingQR
              ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
              : _qrError.isNotEmpty
                  ? _buildQRErrorWidget()
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
        const SizedBox(height: 16),

        // If Error occurred in QR mode
        if (_qrError.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.25)),
            ),
            constraints: const BoxConstraints(maxHeight: 110),
            child: SingleChildScrollView(
              child: SelectableText(
                _qrError,
                style: const TextStyle(color: Colors.redAccent, fontSize: 11, height: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () => _copyErrorText(_qrError),
                icon: Icon(_errorCopied ? Icons.check : Icons.copy, size: 14),
                label: Text(_errorCopied ? '已复制' : '复制诊断信息', style: const TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Color(0xFF333E52)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: () => _tabController.animateTo(1),
                icon: const Icon(Icons.language, size: 14),
                label: const Text('切换网页授权', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
              ),
            ],
          ),
        ],

        // User Code
        if (_info != null && _info!.userCode.isNotEmpty && _qrError.isEmpty) ...[
          const Text(
            '或在手机端百度网盘 App 输入设备码：',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _copyUserCode(_info!.userCode),
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
                    _codeCopied ? Icons.check : Icons.copy,
                    color: _codeCopied ? Colors.greenAccent : Colors.white54,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
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
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _tabController.animateTo(1),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white38,
              padding: EdgeInsets.zero,
              minimumSize: const Size(50, 26),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('扫码遇到问题？使用网页授权 ->', style: TextStyle(fontSize: 11)),
          ),
        ],
      ],
    );
  }

  Widget _buildQRErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 38),
            const SizedBox(height: 8),
            const Text(
              '获取二维码失败',
              style: TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              '可能是网络异常或安全软件拦截\n请点击下方重试或使用网页授权',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 10, height: 1.3),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _startQRLogin,
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
    );
  }

  // --- TAB 2: WEB OAUTH LOGIN ---
  Widget _buildWebTab() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Explanatory note
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1B2230),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF2B3648)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: Colors.blueAccent, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '网页授权不受本地网络代理或杀毒软件限制。点击下方按钮在浏览器中登录后，复制网页中的【授权码】粘贴至此即可。',
                  style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Step 1: Open browser button
        ElevatedButton.icon(
          onPressed: _openingBrowser ? null : _openBrowserAuth,
          icon: _openingBrowser
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.open_in_browser_rounded, size: 18),
          label: Text(_openingBrowser ? '正在启动浏览器...' : '第一步：在默认浏览器打开授权页面'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF263348),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: Color(0xFF384B66)),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Step 2: Code Input Field
        const Text(
          '第二步：粘贴百度网页返回的授权码',
          style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF161C26),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF2A364A)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeController,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    hintText: '在此粘贴授权码...',
                    hintStyle: TextStyle(color: Colors.white24, fontSize: 12),
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => _submitAuthCode(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.paste_rounded, color: Colors.blueAccent, size: 20),
                tooltip: '从剪贴板粘贴',
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data != null && data.text != null && data.text!.isNotEmpty) {
                    _codeController.text = data.text!.trim();
                    setState(() {});
                  }
                },
              ),
            ],
          ),
        ),

        // Error message if web submit fails
        if (_webAuthError.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
            ),
            child: SelectableText(
              _webAuthError,
              style: const TextStyle(color: Colors.redAccent, fontSize: 11, height: 1.3),
            ),
          ),
        ],
        const SizedBox(height: 16),

        // Step 3: Submit Button
        ElevatedButton(
          onPressed: _submittingWebCode ? null : _submitAuthCode,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueAccent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: _submittingWebCode
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('完成登录', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
