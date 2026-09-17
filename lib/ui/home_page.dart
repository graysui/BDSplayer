import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../player/native_player_theater.dart';
import 'login_dialog.dart';
import 'history_drawer.dart';
import 'favorites_drawer.dart';

enum FileSortOption {
  defaultOrder('默认排序', Icons.sort),
  nameAsc('名称 A-Z', Icons.sort_by_alpha),
  nameDesc('名称 Z-A', Icons.sort_by_alpha),
  sizeDesc('从大到小', Icons.arrow_downward),
  sizeAsc('从小到大', Icons.arrow_upward);

  final String label;
  final IconData icon;
  const FileSortOption(this.label, this.icon);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ApiService _api = ApiService();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // State
  bool _isLoggedIn = false;
  String _userInfo = '';
  List<ShareRecord> _shares = [];
  ShareRecord? _selectedShare;
  List<FileItem> _files = [];
  String _currentDir = '';
  bool _loadingFiles = false;
  String _searchQuery = '';
  int _selectedNavigationIndex = 0; // 0: 全部文件, 1: 我的收藏, 2: 播放历史

  // Sort Option
  FileSortOption _currentSort = FileSortOption.defaultOrder;

  // Folder Hiding: Global toggle & Selective hidden fsIds set
  bool _hideHiddenFolders = true; // true: 隐藏已标记文件夹；false: 全部显示
  final Set<int> _hiddenFolderFsIds = {};

  // Favorites cached set
  final Set<int> _favoriteFsIds = {};

  // Progress cache map: fsId -> PlaybackProgress
  final Map<int, PlaybackProgress> _progressMap = {};

  // Directory tree cache: "shareKey:sourceDir" -> List<FileItem>
  final Map<String, List<FileItem>> _dirTreeCache = {};

  // Active video theater state
  FileItem? _activeVideo;
  PlayResult? _activePlayResult;
  bool _loadingPlay = false;

  // Active drawer for EndDrawer (Favorites vs History)
  Widget? _endDrawerWidget;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  File _getHiddenFoldersFile() {
    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';
    final dir = Directory('$home/.config/share-player');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return File('${dir.path}/hidden_folders.json');
  }

  void _loadHiddenFolders() {
    try {
      final file = _getHiddenFoldersFile();
      if (file.existsSync()) {
        final text = file.readAsStringSync();
        final List<dynamic> list = jsonDecode(text);
        setState(() {
          _hiddenFolderFsIds.clear();
          for (var id in list) {
            if (id is int) _hiddenFolderFsIds.add(id);
          }
        });
      }
    } catch (_) {}
  }

  void _saveHiddenFolders() {
    try {
      final file = _getHiddenFoldersFile();
      file.writeAsStringSync(jsonEncode(_hiddenFolderFsIds.toList()));
    } catch (_) {}
  }

  void _toggleFolderHidden(int fsId) {
    setState(() {
      if (_hiddenFolderFsIds.contains(fsId)) {
        _hiddenFolderFsIds.remove(fsId);
      } else {
        _hiddenFolderFsIds.add(fsId);
      }
    });
    _saveHiddenFolders();
  }

  void _loadInitialData() async {
    _loadHiddenFolders();

    try {
      final status = await _api.getStatus();
      setState(() {
        _isLoggedIn = status['logged_in'] ?? false;
        _userInfo = status['user_info'] ?? '';
      });

      await _refreshFavorites();
      await _refreshProgress();

      final shares = await _api.listShares();
      setState(() {
        _shares = shares;
        if (shares.isNotEmpty) {
          _selectShare(shares.first);
        }
      });
    } catch (e) {
      debugPrint('Error loading initial data: $e');
    }
  }

  Future<void> _refreshFavorites() async {
    try {
      final favs = await _api.listFavorites();
      setState(() {
        _favoriteFsIds.clear();
        for (var f in favs) {
          _favoriteFsIds.add(f.fsId);
        }
      });
    } catch (_) {}
  }

  Future<void> _refreshProgress() async {
    try {
      final history = await _api.listHistory();
      setState(() {
        _progressMap.clear();
        for (var h in history) {
          _progressMap[h.shareFsId] = h;
        }
      });
    } catch (_) {}
  }

  void _selectShare(ShareRecord share, {bool forceRefresh = false}) async {
    setState(() {
      _selectedShare = share;
      _currentDir = '';
      _loadingFiles = true;
    });

    final cacheKey = '${share.shareKey}:';
    if (!forceRefresh && _dirTreeCache.containsKey(cacheKey)) {
      setState(() {
        _files = _dirTreeCache[cacheKey]!;
        _loadingFiles = false;
      });
      _refreshProgress();
      return;
    }

    try {
      final files = await _api.getShareFiles(share.shareKey, pwd: share.pwd, sourceDir: '');
      _dirTreeCache[cacheKey] = files;
      setState(() {
        _files = files;
        _loadingFiles = false;
      });
      _refreshProgress();
    } catch (e) {
      setState(() => _loadingFiles = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载目录失败: $e')));
      }
    }
  }

  void _navigateToDir(String dir, {bool forceRefresh = false}) async {
    if (_selectedShare == null) return;
    setState(() {
      _currentDir = dir;
      _loadingFiles = true;
    });

    final cacheKey = '${_selectedShare!.shareKey}:$dir';
    if (!forceRefresh && _dirTreeCache.containsKey(cacheKey)) {
      setState(() {
        _files = _dirTreeCache[cacheKey]!;
        _loadingFiles = false;
      });
      _refreshProgress();
      return;
    }

    try {
      final files = await _api.getShareFiles(_selectedShare!.shareKey, pwd: _selectedShare!.pwd, sourceDir: dir);
      _dirTreeCache[cacheKey] = files;
      setState(() {
        _files = files;
        _loadingFiles = false;
      });
      _refreshProgress();
    } catch (e) {
      setState(() => _loadingFiles = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载子目录失败: $e')));
      }
    }
  }

  void _refreshCurrentDir() {
    if (_selectedShare == null) return;
    if (_currentDir.isEmpty) {
      _selectShare(_selectedShare!, forceRefresh: true);
    } else {
      _navigateToDir(_currentDir, forceRefresh: true);
    }
  }

  void _playVideo(FileItem file) async {
    if (_selectedShare == null) return;

    setState(() {
      _loadingPlay = true;
    });

    try {
      final playResult = await _api.preparePlay(
        shareKey: _selectedShare!.shareKey,
        pwd: _selectedShare!.pwd,
        videoName: file.name,
        shareFsId: file.fsId,
      );

      setState(() {
        _activeVideo = file;
        _activePlayResult = playResult;
        _loadingPlay = false;
      });
    } catch (e) {
      setState(() => _loadingPlay = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('起播失败: $e')));
      }
    }
  }

  void _resumeFromHistory(PlaybackProgress progress) async {
    setState(() => _loadingPlay = true);
    try {
      final targetShare = _shares.firstWhere(
        (s) => s.shareKey == progress.shareKey,
        orElse: () => ShareRecord(shareKey: progress.shareKey, shareUrl: '', pwd: '', title: progress.videoName),
      );

      final playResult = await _api.preparePlay(
        shareKey: progress.shareKey,
        pwd: targetShare.pwd,
        videoName: progress.videoName,
        shareFsId: progress.shareFsId,
      );

      final file = FileItem(
        fsId: progress.shareFsId,
        name: progress.videoName,
        isDir: false,
        isVideo: true,
        size: 0,
      );

      setState(() {
        _selectedShare = targetShare;
        _activeVideo = file;
        _activePlayResult = playResult;
        _loadingPlay = false;
      });
    } catch (e) {
      setState(() => _loadingPlay = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('恢复播放失败: $e')));
      }
    }
  }

  void _handleFavoriteSelect(FavoriteRecord fav) async {
    final targetShare = _shares.firstWhere(
      (s) => s.shareKey == fav.shareKey,
      orElse: () => ShareRecord(shareKey: fav.shareKey, shareUrl: '', pwd: fav.sharePwd, title: fav.name),
    );

    _selectShare(targetShare);

    if (fav.isDir) {
      _navigateToDir(fav.path);
    } else {
      final file = FileItem(
        fsId: fav.fsId,
        name: fav.name,
        isDir: false,
        isVideo: true,
        size: fav.size,
        path: fav.path,
      );
      _playVideo(file);
    }
  }

  void _toggleFavorite(FileItem file) async {
    if (_selectedShare == null) return;
    final isFav = _favoriteFsIds.contains(file.fsId);

    try {
      if (isFav) {
        await _api.deleteFavorite(_selectedShare!.shareKey, file.fsId);
        setState(() => _favoriteFsIds.remove(file.fsId));
      } else {
        await _api.saveFavorite(FavoriteRecord(
          shareKey: _selectedShare!.shareKey,
          sharePwd: _selectedShare!.pwd,
          fsId: file.fsId,
          name: file.name,
          isDir: file.isDir,
          path: file.path.isNotEmpty ? file.path : '$_currentDir/${file.name}',
          size: file.size,
        ));
        setState(() => _favoriteFsIds.add(file.fsId));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('收藏操作失败: $e')));
      }
    }
  }

  void _showLoginDialog() {
    if (_isLoggedIn) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E2636),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF2E394E)),
          ),
          title: const Row(
            children: [
              Icon(Icons.verified_user, color: Colors.greenAccent, size: 22),
              SizedBox(width: 10),
              Text('百度网盘已授权', style: TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('当前授权用户：$_userInfo', style: const TextStyle(color: Colors.white, fontSize: 14)),
              const SizedBox(height: 8),
              const Text('授权状态正常，可直接解析直链享受免限速点播。', style: TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('我知道了', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
              onPressed: () {
                Navigator.pop(ctx);
                _openQrLogin();
              },
              child: const Text('重新绑定 / 切换账号', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    } else {
      _openQrLogin();
    }
  }

  void _openQrLogin() {
    showDialog(
      context: context,
      builder: (ctx) => LoginDialog(
        onLoginSuccess: () {
          _loadInitialData();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('百度网盘账号已成功绑定！')),
          );
        },
      ),
    );
  }

  void _showAddShareDialog() {
    final textCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2636),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF2E394E)),
        ),
        title: const Text('添加百度网盘分享资源', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: textCtrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: '粘贴分享链接与提取码 (例: pan.baidu.com/s/1xxx 提取码: 1234)',
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
            filled: true,
            fillColor: const Color(0xFF141924),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              final input = textCtrl.text.trim();
              if (input.isEmpty) return;
              Navigator.pop(ctx);
              try {
                final share = await _api.addShare(input);
                setState(() {
                  _shares.insert(0, share);
                  _selectShare(share);
                });
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('添加失败: $e')));
                }
              }
            },
            child: const Text('解析入库', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _openHistoryDrawer() {
    setState(() {
      _endDrawerWidget = HistoryDrawer(onResume: _resumeFromHistory);
    });
    _scaffoldKey.currentState?.openEndDrawer();
  }

  void _openFavoritesDrawer() {
    setState(() {
      _endDrawerWidget = FavoritesDrawer(onSelect: _handleFavoriteSelect);
    });
    _scaffoldKey.currentState?.openEndDrawer();
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  String _formatDuration(double seconds) {
    final d = Duration(seconds: seconds.toInt());
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    // If playing video, render Native MPV Theater!
    if (_activeVideo != null && _activePlayResult != null) {
      final videoPlaylist = _files.where((f) => !f.isDir && f.isVideo).toList();
      return NativePlayerTheater(
        video: _activeVideo!,
        playData: _activePlayResult!,
        playlist: videoPlaylist,
        onClose: () {
          setState(() {
            _activeVideo = null;
            _activePlayResult = null;
          });
          _refreshFavorites();
          _refreshProgress();
        },
        onSwitchVideo: (nextVideo) => _playVideo(nextVideo),
      );
    }

    // 1. Filter files by Selective Folder Hiding & Query
    var displayFiles = _files.where((f) {
      if (f.isDir && _hideHiddenFolders && _hiddenFolderFsIds.contains(f.fsId)) {
        return false;
      }
      return true;
    }).toList();

    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase().trim();
      displayFiles = displayFiles.where((f) => f.name.toLowerCase().contains(q)).toList();
    }

    // 2. Sort files based on _currentSort
    final folders = displayFiles.where((f) => f.isDir).toList();
    final nonFolders = displayFiles.where((f) => !f.isDir).toList();

    void sortList(List<FileItem> list) {
      switch (_currentSort) {
        case FileSortOption.nameAsc:
          list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          break;
        case FileSortOption.nameDesc:
          list.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
          break;
        case FileSortOption.sizeDesc:
          list.sort((a, b) => b.size.compareTo(a.size));
          break;
        case FileSortOption.sizeAsc:
          list.sort((a, b) => a.size.compareTo(b.size));
          break;
        case FileSortOption.defaultOrder:
          break;
      }
    }

    sortList(folders);
    sortList(nonFolders);
    displayFiles = [...folders, ...nonFolders];

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF0F1218),
      endDrawer: _endDrawerWidget,
      body: Row(
        children: [
          // 1. Flutter Modern Navigation Rail
          NavigationRail(
            backgroundColor: const Color(0xFF121620),
            selectedIndex: _selectedNavigationIndex,
            onDestinationSelected: (idx) {
              if (idx == 1) {
                _openFavoritesDrawer();
              } else if (idx == 2) {
                _openHistoryDrawer();
              } else {
                setState(() => _selectedNavigationIndex = idx);
              }
            },
            labelType: NavigationRailLabelType.all,
            leading: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blueAccent.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(height: 20),
              ],
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: IconButton(
                    icon: Icon(
                      _isLoggedIn ? Icons.verified_user : Icons.login,
                      color: _isLoggedIn ? Colors.greenAccent : Colors.white54,
                    ),
                    tooltip: _isLoggedIn ? '已授权: $_userInfo (点击管理)' : '点击扫码登录百度网盘',
                    onPressed: _showLoginDialog,
                  ),
                ),
              ),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.folder_outlined),
                selectedIcon: Icon(Icons.folder),
                label: Text('全部文件', style: TextStyle(fontSize: 11)),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.star_border),
                selectedIcon: Icon(Icons.star),
                label: Text('我的收藏', style: TextStyle(fontSize: 11)),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.history_outlined),
                selectedIcon: Icon(Icons.history),
                label: Text('播放历史', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),

          const VerticalDivider(width: 1, color: Color(0xFF1E2534)),

          // 2. Shares Sidebar Panel
          Container(
            width: 260,
            color: const Color(0xFF141924),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                  child: Row(
                    children: [
                      const Text(
                        '分享资源库',
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 6),
                      Text('(${_shares.length})', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: Colors.blueAccent, size: 22),
                        tooltip: '添加分享链接',
                        onPressed: _showAddShareDialog,
                      ),
                    ],
                  ),
                ),

                // Share Cards
                Expanded(
                  child: _shares.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.link_off, color: Colors.white24, size: 36),
                              const SizedBox(height: 8),
                              const Text('暂无分享链接', style: TextStyle(color: Colors.white38, fontSize: 13)),
                              TextButton(
                                onPressed: _showAddShareDialog,
                                child: const Text('添加第一个分享'),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          itemCount: _shares.length,
                          itemBuilder: (context, idx) {
                            final share = _shares[idx];
                            final isSelected = _selectedShare?.shareKey == share.shareKey;

                            return Card(
                              elevation: 0,
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              color: isSelected
                                  ? Colors.blueAccent.withValues(alpha: 0.16)
                                  : Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                  color: isSelected ? Colors.blueAccent.withValues(alpha: 0.5) : Colors.transparent,
                                ),
                              ),
                              child: ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                leading: Icon(
                                  Icons.folder_shared,
                                  color: isSelected ? Colors.blueAccent : Colors.white54,
                                  size: 20,
                                ),
                                title: Text(
                                  share.title.isNotEmpty ? share.title : share.shareKey,
                                  style: TextStyle(
                                    color: isSelected ? Colors.blueAccent : Colors.white,
                                    fontSize: 13,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${share.totalFiles} 个文件',
                                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                                ),
                                trailing: PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert, size: 16, color: Colors.white38),
                                  onSelected: (val) async {
                                    if (val == 'delete') {
                                      await _api.deleteShare(share.shareKey);
                                      setState(() {
                                        _shares.removeAt(idx);
                                        if (_selectedShare?.shareKey == share.shareKey) {
                                          _selectedShare = _shares.isNotEmpty ? _shares.first : null;
                                          if (_selectedShare != null) _selectShare(_selectedShare!);
                                        }
                                      });
                                    }
                                  },
                                  itemBuilder: (ctx) => [
                                    const PopupMenuItem(value: 'delete', child: Text('移除此分享')),
                                  ],
                                ),
                                onTap: () => _selectShare(share),
                              ),
                            );
                          },
                        ),
                ),

                // Account Bar
                InkWell(
                  onTap: _showLoginDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: const BoxDecoration(
                      color: Color(0xFF10141D),
                      border: Border(top: BorderSide(color: Color(0xFF1E2534))),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isLoggedIn ? Icons.account_circle : Icons.no_accounts,
                          color: _isLoggedIn ? Colors.greenAccent : Colors.white38,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isLoggedIn ? _userInfo : '点击登录网盘',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                _isLoggedIn ? '已连接 • 点击管理账号' : '登录后享原画免限速',
                                style: TextStyle(
                                  color: _isLoggedIn ? Colors.greenAccent : Colors.white38,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 12),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const VerticalDivider(width: 1, color: Color(0xFF1E2534)),

          // 3. Explorer Main Area
          Expanded(
            child: Column(
              children: [
                // Top Action & Search Bar
                Container(
                  height: 60,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: const BoxDecoration(
                    color: Color(0xFF141924),
                    border: Border(bottom: BorderSide(color: Color(0xFF1E2534))),
                  ),
                  child: Row(
                    children: [
                      // Breadcrumb
                      if (_currentDir.isNotEmpty) ...[
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white70, size: 20),
                          tooltip: '返回上一级',
                          onPressed: () {
                            final idx = _currentDir.lastIndexOf('/');
                            if (idx <= 0) {
                              _navigateToDir('');
                            } else {
                              _navigateToDir(_currentDir.substring(0, idx));
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        _selectedShare?.title ?? '请选择左侧资源',
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      if (_currentDir.isNotEmpty)
                        Text(' $_currentDir', style: const TextStyle(color: Colors.white38, fontSize: 13)),

                      const SizedBox(width: 8),

                      // Fast Refresh Button (pulls latest from Baidu and updates cache)
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white54, size: 18),
                        tooltip: '重新拉取并更新目录缓存',
                        onPressed: _refreshCurrentDir,
                      ),

                      const Spacer(),

                      // 1. Sort Popup Menu
                      PopupMenuButton<FileSortOption>(
                        tooltip: '文件排序',
                        initialValue: _currentSort,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        color: const Color(0xFF1E2636),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C2230),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF2B3547)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_currentSort.icon, size: 16, color: Colors.blueAccent),
                              const SizedBox(width: 6),
                              Text(
                                _currentSort.label,
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.arrow_drop_down, size: 16, color: Colors.white38),
                            ],
                          ),
                        ),
                        onSelected: (opt) => setState(() => _currentSort = opt),
                        itemBuilder: (ctx) => [
                          for (final opt in FileSortOption.values)
                            PopupMenuItem(
                              value: opt,
                              child: Row(
                                children: [
                                  Icon(opt.icon, size: 16, color: _currentSort == opt ? Colors.blueAccent : Colors.white54),
                                  const SizedBox(width: 10),
                                  Text(
                                    opt.label,
                                    style: TextStyle(
                                      color: _currentSort == opt ? Colors.blueAccent : Colors.white,
                                      fontWeight: _currentSort == opt ? FontWeight.bold : FontWeight.normal,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),

                      const SizedBox(width: 12),

                      // 2. Hide Folders Global Switch (FilterChip)
                      FilterChip(
                        selected: _hideHiddenFolders,
                        showCheckmark: true,
                        avatar: Icon(
                          _hideHiddenFolders ? Icons.visibility_off : Icons.visibility,
                          size: 16,
                          color: _hideHiddenFolders ? Colors.blueAccent : Colors.white54,
                        ),
                        label: Text(
                          _hideHiddenFolders
                              ? '隐藏已标文件夹 (${_hiddenFolderFsIds.length})'
                              : '显示所有文件夹',
                          style: TextStyle(
                            color: _hideHiddenFolders ? Colors.blueAccent : Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        backgroundColor: const Color(0xFF1C2230),
                        selectedColor: Colors.blueAccent.withValues(alpha: 0.15),
                        side: BorderSide(
                          color: _hideHiddenFolders ? Colors.blueAccent : Colors.transparent,
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        onSelected: (val) => setState(() => _hideHiddenFolders = val),
                      ),

                      const SizedBox(width: 16),

                      // 3. Search input
                      SizedBox(
                        width: 220,
                        height: 36,
                        child: TextField(
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: '搜索当前资源...',
                            hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                            prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 18),
                            filled: true,
                            fillColor: const Color(0xFF1C2230),
                            contentPadding: EdgeInsets.zero,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onChanged: (val) => setState(() => _searchQuery = val),
                        ),
                      ),
                    ],
                  ),
                ),

                // Explorer Content
                Expanded(
                  child: _loadingFiles
                      ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
                      : displayFiles.isEmpty
                          ? const Center(
                              child: Text('当前目录无匹配文件', style: TextStyle(color: Colors.white38)),
                            )
                          : Stack(
                              children: [
                                ListView.separated(
                                  padding: const EdgeInsets.all(20),
                                  itemCount: displayFiles.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                                  itemBuilder: (context, idx) {
                                    final file = displayFiles[idx];
                                    final isFav = _favoriteFsIds.contains(file.fsId);
                                    final isHidden = _hiddenFolderFsIds.contains(file.fsId);
                                    final prog = _progressMap[file.fsId];

                                    return InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () {
                                        if (file.isDir) {
                                          _navigateToDir(file.path.isNotEmpty ? file.path : '$_currentDir/${file.name}');
                                        } else if (file.isVideo) {
                                          _playVideo(file);
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        decoration: BoxDecoration(
                                          color: isHidden ? const Color(0xFF141720) : const Color(0xFF171D2A),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: isHidden ? const Color(0xFF1C2230) : const Color(0xFF222A3B),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: file.isDir
                                                    ? (isHidden
                                                        ? Colors.grey.withValues(alpha: 0.1)
                                                        : Colors.amber.withValues(alpha: 0.15))
                                                    : Colors.blueAccent.withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Icon(
                                                file.isDir
                                                    ? (isHidden ? Icons.folder_off : Icons.folder)
                                                    : Icons.movie_outlined,
                                                color: file.isDir
                                                    ? (isHidden ? Colors.white38 : Colors.amberAccent)
                                                    : Colors.blueAccent,
                                                size: 22,
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          file.name,
                                                          style: TextStyle(
                                                            color: isHidden ? Colors.white54 : Colors.white,
                                                            fontSize: 14,
                                                            fontWeight: FontWeight.w500,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                      if (isHidden) ...[
                                                        const SizedBox(width: 8),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: Colors.grey.withValues(alpha: 0.2),
                                                            borderRadius: BorderRadius.circular(4),
                                                          ),
                                                          child: const Text('已隐藏', style: TextStyle(color: Colors.white38, fontSize: 10)),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    children: [
                                                      Text(
                                                        file.isDir ? '目录' : _formatSize(file.size),
                                                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                                                      ),
                                                      if (prog != null) ...[
                                                        const SizedBox(width: 10),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: prog.isFinished
                                                                ? Colors.greenAccent.withValues(alpha: 0.15)
                                                                : Colors.blueAccent.withValues(alpha: 0.15),
                                                            borderRadius: BorderRadius.circular(4),
                                                          ),
                                                          child: Text(
                                                            prog.isFinished
                                                                ? '已看完'
                                                                : '已播至 ${prog.progressPercent.toInt()}% (${_formatDuration(prog.currentTime)})',
                                                            style: TextStyle(
                                                              color: prog.isFinished ? Colors.greenAccent : Colors.blueAccent,
                                                              fontSize: 11,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),

                                            // Selective Hide Button (Only for Folders)
                                            if (file.isDir)
                                              IconButton(
                                                icon: Icon(
                                                  isHidden ? Icons.visibility_off : Icons.visibility_outlined,
                                                  color: isHidden ? Colors.amberAccent : Colors.white38,
                                                  size: 20,
                                                ),
                                                tooltip: isHidden ? '恢复显示此文件夹' : '隐藏此文件夹',
                                                onPressed: () => _toggleFolderHidden(file.fsId),
                                              ),

                                            // Favorite Button
                                            IconButton(
                                              icon: Icon(
                                                isFav ? Icons.star : Icons.star_border,
                                                color: isFav ? Colors.amberAccent : Colors.white38,
                                                size: 20,
                                              ),
                                              tooltip: isFav ? '取消收藏' : '加入收藏',
                                              onPressed: () => _toggleFavorite(file),
                                            ),

                                            const SizedBox(width: 8),

                                            // Action Icon
                                            Icon(
                                              file.isDir ? Icons.arrow_forward_ios : Icons.play_circle_filled,
                                              color: file.isDir ? Colors.white38 : Colors.blueAccent,
                                              size: file.isDir ? 14 : 26,
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),

                                // Loading overlay when preparing play
                                if (_loadingPlay)
                                  Container(
                                    color: Colors.black54,
                                    child: const Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          CircularProgressIndicator(color: Colors.blueAccent),
                                          SizedBox(height: 16),
                                          Text(
                                            '正在即点即存并提取原生直链...',
                                            style: TextStyle(color: Colors.white, fontSize: 14),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
