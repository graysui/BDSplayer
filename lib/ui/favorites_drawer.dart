import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class FavoritesDrawer extends StatefulWidget {
  final Function(FavoriteRecord) onSelect;

  const FavoritesDrawer({super.key, required this.onSelect});

  @override
  State<FavoritesDrawer> createState() => _FavoritesDrawerState();
}

class _FavoritesDrawerState extends State<FavoritesDrawer> {
  final ApiService _api = ApiService();
  List<FavoriteRecord> _list = [];
  bool _loading = true;
  String _filter = 'all'; // 'all', 'folder', 'video'

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  void _loadFavorites() async {
    setState(() => _loading = true);
    try {
      final items = await _api.listFavorites();
      setState(() {
        _list = items;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _removeFavorite(FavoriteRecord fav) async {
    try {
      await _api.deleteFavorite(fav.shareKey, fav.fsId);
      setState(() {
        _list.removeWhere((item) => item.shareKey == fav.shareKey && item.fsId == fav.fsId);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('移除收藏失败: $e')));
      }
    }
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

  @override
  Widget build(BuildContext context) {
    final filtered = _list.where((f) {
      if (_filter == 'folder') return f.isDir;
      if (_filter == 'video') return !f.isDir;
      return true;
    }).toList();

    return Drawer(
      backgroundColor: const Color(0xFF141822),
      surfaceTintColor: Colors.transparent,
      width: 380,
      child: SafeArea(
        child: Column(
          children: [
            // Drawer Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF222B3D))),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.star, color: Colors.amberAccent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    '我的收藏',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '(${_list.length})',
                    style: const TextStyle(color: Colors.white38, fontSize: 13, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),

            // Segment Filter
            Container(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _buildFilterChip('全部 (${_list.length})', 'all'),
                  const SizedBox(width: 8),
                  _buildFilterChip('文件夹', 'folder'),
                  const SizedBox(width: 8),
                  _buildFilterChip('视频', 'video'),
                ],
              ),
            ),

            // Content List
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
                  : filtered.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.star_border, color: Colors.white24, size: 48),
                              SizedBox(height: 12),
                              Text('暂无收藏内容', style: TextStyle(color: Colors.white38, fontSize: 13)),
                              SizedBox(height: 4),
                              Text('在文件或视频右侧点击星标即可收藏', style: TextStyle(color: Colors.white24, fontSize: 11)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, idx) {
                            final fav = filtered[idx];

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1B2230),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFF263044)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: fav.isDir
                                          ? Colors.amber.withValues(alpha: 0.15)
                                          : Colors.blueAccent.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      fav.isDir ? Icons.folder : Icons.movie_outlined,
                                      color: fav.isDir ? Colors.amberAccent : Colors.blueAccent,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          fav.name,
                                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          fav.isDir ? '目录' : _formatSize(fav.size),
                                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.star, color: Colors.amberAccent, size: 18),
                                    tooltip: '取消收藏',
                                    onPressed: () => _removeFavorite(fav),
                                  ),
                                  IconButton(
                                    icon: Icon(fav.isDir ? Icons.arrow_forward_ios : Icons.play_arrow, size: 16, color: Colors.blueAccent),
                                    tooltip: fav.isDir ? '打开目录' : '播放',
                                    onPressed: () {
                                      Navigator.pop(context);
                                      widget.onSelect(fav);
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filter == value;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _filter = value),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? Colors.blueAccent.withValues(alpha: 0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? Colors.blueAccent : const Color(0xFF263044),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.blueAccent : Colors.white54,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
