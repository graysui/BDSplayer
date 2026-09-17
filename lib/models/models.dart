class ShareRecord {
  final int? id;
  final String shareKey;
  final String shareUrl;
  final String pwd;
  final String title;
  final String coverUrl;
  final int totalFiles;
  final String createdAt;
  final String updatedAt;

  ShareRecord({
    this.id,
    required this.shareKey,
    required this.shareUrl,
    required this.pwd,
    required this.title,
    this.coverUrl = '',
    this.totalFiles = 0,
    this.createdAt = '',
    this.updatedAt = '',
  });

  factory ShareRecord.fromJson(Map<String, dynamic> json) {
    return ShareRecord(
      id: json['id'] is int ? json['id'] : null,
      shareKey: json['share_key'] ?? '',
      shareUrl: json['share_url'] ?? '',
      pwd: json['pwd'] ?? '',
      title: json['title'] ?? '',
      coverUrl: json['cover_url'] ?? '',
      totalFiles: json['total_files'] ?? 0,
      createdAt: json['created_at'] ?? '',
      updatedAt: json['updated_at'] ?? '',
    );
  }
}

class FileItem {
  final int fsId;
  final String name;
  final bool isDir;
  final bool isVideo;
  final int size;
  final String path;
  final String updatedAt;

  FileItem({
    required this.fsId,
    required this.name,
    required this.isDir,
    required this.isVideo,
    required this.size,
    this.path = '',
    this.updatedAt = '',
  });

  factory FileItem.fromJson(Map<String, dynamic> json) {
    return FileItem(
      fsId: json['fs_id'] ?? 0,
      name: json['name'] ?? '',
      isDir: json['is_dir'] ?? false,
      isVideo: json['is_video'] ?? false,
      size: json['size'] ?? 0,
      path: json['path'] ?? '',
      updatedAt: json['updated_at'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fs_id': fsId,
      'name': name,
      'is_dir': isDir,
      'is_video': isVideo,
      'size': size,
      'path': path,
      'updated_at': updatedAt,
    };
  }
}

class PlayResult {
  final String sessionId;
  final String streamUrl;
  final String rawDlink;
  final String videoId;
  final String videoName;
  final double duration;
  final double currentTime;

  PlayResult({
    required this.sessionId,
    required this.streamUrl,
    required this.rawDlink,
    required this.videoId,
    required this.videoName,
    required this.duration,
    required this.currentTime,
  });

  factory PlayResult.fromJson(Map<String, dynamic> json) {
    return PlayResult(
      sessionId: json['session_id'] ?? '',
      streamUrl: json['stream_url'] ?? '',
      rawDlink: json['raw_dlink'] ?? '',
      videoId: json['video_id'] ?? '',
      videoName: json['video_name'] ?? '',
      duration: (json['duration'] as num?)?.toDouble() ?? 0.0,
      currentTime: (json['current_time'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class PlaybackProgress {
  final String videoId;
  final String shareKey;
  final int shareFsId;
  final String videoName;
  final double currentTime;
  final double duration;
  final double progressPercent;
  final bool isFinished;
  final String lastPlayedAt;

  PlaybackProgress({
    required this.videoId,
    required this.shareKey,
    required this.shareFsId,
    required this.videoName,
    required this.currentTime,
    required this.duration,
    required this.progressPercent,
    required this.isFinished,
    required this.lastPlayedAt,
  });

  factory PlaybackProgress.fromJson(Map<String, dynamic> json) {
    return PlaybackProgress(
      videoId: json['video_id'] ?? '',
      shareKey: json['share_key'] ?? '',
      shareFsId: json['share_fsid'] ?? 0,
      videoName: json['video_name'] ?? '',
      currentTime: (json['current_time'] as num?)?.toDouble() ?? 0.0,
      duration: (json['duration'] as num?)?.toDouble() ?? 0.0,
      progressPercent: (json['progress_percent'] as num?)?.toDouble() ?? 0.0,
      isFinished: json['is_finished'] ?? false,
      lastPlayedAt: json['last_played_at'] ?? '',
    );
  }
}

class FavoriteRecord {
  final int? id;
  final String shareKey;
  final String sharePwd;
  final int fsId;
  final String name;
  final bool isDir;
  final String path;
  final int size;
  final String createdAt;

  FavoriteRecord({
    this.id,
    required this.shareKey,
    this.sharePwd = '',
    required this.fsId,
    required this.name,
    required this.isDir,
    this.path = '',
    this.size = 0,
    this.createdAt = '',
  });

  factory FavoriteRecord.fromJson(Map<String, dynamic> json) {
    return FavoriteRecord(
      id: json['id'] is int ? json['id'] : null,
      shareKey: json['share_key'] ?? '',
      sharePwd: json['share_pwd'] ?? '',
      fsId: json['fs_id'] ?? 0,
      name: json['name'] ?? '',
      isDir: json['is_dir'] ?? false,
      path: json['path'] ?? '',
      size: json['size'] ?? 0,
      createdAt: json['created_at'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'share_key': shareKey,
      'share_pwd': sharePwd,
      'fs_id': fsId,
      'name': name,
      'is_dir': isDir,
      'path': path,
      'size': size,
    };
  }
}

class DeviceCodeResponse {
  final String deviceCode;
  final String userCode;
  final String verificationUrl;
  final String qrcodeUrl;
  final int expiresIn;
  final int interval;

  DeviceCodeResponse({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUrl,
    required this.qrcodeUrl,
    required this.expiresIn,
    required this.interval,
  });

  factory DeviceCodeResponse.fromJson(Map<String, dynamic> json) {
    return DeviceCodeResponse(
      deviceCode: json['device_code'] ?? '',
      userCode: json['user_code'] ?? '',
      verificationUrl: json['verification_url'] ?? '',
      qrcodeUrl: json['qrcode_url'] ?? '',
      expiresIn: json['expires_in'] ?? 300,
      interval: json['interval'] ?? 2,
    );
  }
}
