import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';

class ApiService {
  static const String defaultBaseUrl = 'http://127.0.0.1:18900';
  final String baseUrl;

  ApiService({this.baseUrl = defaultBaseUrl});

  // 1. Status & Auth
  Future<Map<String, dynamic>> getStatus() async {
    final res = await http.get(Uri.parse('$baseUrl/api/status'));
    if (res.statusCode == 200) {
      return jsonDecode(utf8.decode(res.bodyBytes));
    }
    throw Exception('Failed to get status: ${res.statusCode}');
  }

  Future<DeviceCodeResponse> startDeviceLogin() async {
    final res = await http.get(Uri.parse('$baseUrl/api/auth/device_code'));
    if (res.statusCode == 200) {
      return DeviceCodeResponse.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
    }
    throw Exception('Failed to get device code: ${res.body}');
  }

  Future<bool> pollDeviceLogin(String deviceCode) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/auth/poll'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'device_code': deviceCode}),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      return data['success'] == true;
    }
    return false;
  }

  Future<bool> logout() async {
    try {
      final res = await http.post(Uri.parse('$baseUrl/api/auth/logout'));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> submitAuthCode(String code) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/auth/submit_code'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'code': code.trim()}),
    );
    final body = utf8.decode(res.bodyBytes);
    if (res.statusCode != 200) {
      try {
        final errObj = jsonDecode(body);
        throw Exception(errObj['error'] ?? body);
      } catch (e) {
        if (e is Exception) rethrow;
        throw Exception(body);
      }
    }
  }

  Future<String> getAuthUrl() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/auth/auth_url'));
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        if (data['url'] != null && data['url'].toString().isNotEmpty) {
          return data['url'].toString();
        }
      }
    } catch (_) {}
    return 'https://openapi.baidu.com/oauth/2.0/authorize?client_id=zF5kkNsCvckX4aIpRdHxpFkcSMxnGZky&display=popup&qrcode=1&redirect_uri=oob&response_type=code&scope=basic%2Cnetdisk';
  }

  Future<void> cancelLogin() async {
    try {
      await http.post(Uri.parse('$baseUrl/api/auth/cancel_login')).timeout(
        const Duration(milliseconds: 500),
      );
    } catch (_) {}
  }

  // 2. Shares
  Future<List<ShareRecord>> listShares() async {
    final res = await http.get(Uri.parse('$baseUrl/api/shares'));
    if (res.statusCode == 200) {
      final List<dynamic> list = jsonDecode(utf8.decode(res.bodyBytes));
      return list.map((e) => ShareRecord.fromJson(e)).toList();
    }
    throw Exception('Failed to fetch shares: ${res.body}');
  }

  Future<ShareRecord> addShare(String input) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/shares'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'input': input}),
    );
    if (res.statusCode == 200) {
      return ShareRecord.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
    }
    throw Exception('添加分享失败: ${res.body}');
  }

  Future<void> deleteShare(String shareKey) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/api/shares?share_key=$shareKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'share_key': shareKey}),
    );
    if (res.statusCode != 200) {
      throw Exception('删除失败: ${res.body}');
    }
  }

  Future<void> updateShareTitle(String shareKey, String title) async {
    final res = await http.put(
      Uri.parse('$baseUrl/api/shares'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'share_key': shareKey, 'title': title}),
    );
    if (res.statusCode != 200) {
      throw Exception('修改标题失败: ${res.body}');
    }
  }

  // 3. Share Files
  Future<List<FileItem>> getShareFiles(String shareKey, {String pwd = '', String sourceDir = '', int page = 1}) async {
    final uri = Uri.parse('$baseUrl/api/shares/$shareKey/files').replace(queryParameters: {
      'pwd': pwd,
      'source_dir': sourceDir,
      'page': page.toString(),
    });
    final res = await http.get(uri);
    if (res.statusCode == 200) {
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      final List<dynamic> items = data['items'] ?? [];
      return items.map((e) => FileItem.fromJson(e)).toList();
    }
    throw Exception('获取文件列表失败: ${res.body}');
  }

  // 4. Play (JIT Transfer & Get Dlink)
  Future<PlayResult> preparePlay({
    required String shareKey,
    required String pwd,
    required String videoName,
    required int shareFsId,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/play'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'share_key': shareKey,
        'pwd': pwd,
        'video_name': videoName,
        'share_fsid': shareFsId,
      }),
    );
    if (res.statusCode == 200) {
      return PlayResult.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
    }
    throw Exception('解析视频直链失败: ${res.body}');
  }

  // 5. Progress
  Future<void> saveProgress({
    required String videoId,
    required String shareKey,
    required int shareFsId,
    required String videoName,
    required double currentTime,
    required double duration,
  }) async {
    await http.post(
      Uri.parse('$baseUrl/api/progress'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'video_id': videoId,
        'share_key': shareKey,
        'share_fsid': shareFsId,
        'video_name': videoName,
        'current_time': currentTime,
        'duration': duration,
      }),
    );
  }

  Future<PlaybackProgress?> getProgress(String videoId) async {
    final res = await http.get(Uri.parse('$baseUrl/api/progress?video_id=$videoId'));
    if (res.statusCode == 200) {
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data != null && data['video_id'] != null) {
        return PlaybackProgress.fromJson(data);
      }
    }
    return null;
  }

  // 6. History
  Future<List<PlaybackProgress>> listHistory() async {
    final res = await http.get(Uri.parse('$baseUrl/api/history'));
    if (res.statusCode == 200) {
      final List<dynamic> list = jsonDecode(utf8.decode(res.bodyBytes));
      return list.map((e) => PlaybackProgress.fromJson(e)).toList();
    }
    return [];
  }

  Future<void> clearHistory() async {
    final res = await http.delete(Uri.parse('$baseUrl/api/history'));
    if (res.statusCode != 200) {
      throw Exception('清空历史记录失败: ${res.body}');
    }
  }

  // 7. Favorites
  Future<List<FavoriteRecord>> listFavorites() async {
    final res = await http.get(Uri.parse('$baseUrl/api/favorites'));
    if (res.statusCode == 200) {
      final List<dynamic> list = jsonDecode(utf8.decode(res.bodyBytes));
      return list.map((e) => FavoriteRecord.fromJson(e)).toList();
    }
    return [];
  }

  Future<void> saveFavorite(FavoriteRecord fav) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/favorites'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(fav.toJson()),
    );
    if (res.statusCode != 200) {
      throw Exception('保存收藏失败: ${res.body}');
    }
  }

  Future<void> deleteFavorite(String shareKey, int fsId) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/api/favorites'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'share_key': shareKey, 'fs_id': fsId}),
    );
    if (res.statusCode != 200) {
      throw Exception('取消收藏失败: ${res.body}');
    }
  }
}
