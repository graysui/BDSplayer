import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class HistoryDrawer extends StatefulWidget {
  final Function(PlaybackProgress) onResume;

  const HistoryDrawer({super.key, required this.onResume});

  @override
  State<HistoryDrawer> createState() => _HistoryDrawerState();
}

class _HistoryDrawerState extends State<HistoryDrawer> {
  final ApiService _api = ApiService();
  List<PlaybackProgress> _list = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  void _loadHistory() async {
    setState(() => _loading = true);
    try {
      final items = await _api.listHistory();
      setState(() {
        _list = items;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A202C),
        title: const Text('清空播放历史', style: TextStyle(color: Colors.white)),
        content: const Text('确定要清空全部播放进度与历史记录吗？', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _api.clearHistory();
        setState(() => _list.clear());
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('清空失败: $e')));
        }
      }
    }
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
                      color: Colors.blueAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.history, color: Colors.blueAccent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    '播放历史',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '(${_list.length})',
                    style: const TextStyle(color: Colors.white38, fontSize: 13, fontFamily: 'monospace'),
                  ),
                  const Spacer(),
                  if (_list.isNotEmpty)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                      icon: const Icon(Icons.delete_sweep, size: 18),
                      label: const Text('清空'),
                      onPressed: _clearHistory,
                    ),
                ],
              ),
            ),

            // Content List
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
                  : _list.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.history_toggle_off, color: Colors.white24, size: 48),
                              SizedBox(height: 12),
                              Text('暂无播放历史记录', style: TextStyle(color: Colors.white38, fontSize: 13)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _list.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, idx) {
                            final item = _list[idx];
                            final percent = (item.progressPercent).clamp(0.0, 100.0);

                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1B2230),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFF263044)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.videoName,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),

                                  // Progress bar
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(3),
                                    child: LinearProgressIndicator(
                                      value: percent / 100.0,
                                      backgroundColor: Colors.white12,
                                      color: item.isFinished ? Colors.greenAccent : Colors.blueAccent,
                                      minHeight: 4,
                                    ),
                                  ),
                                  const SizedBox(height: 10),

                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        item.isFinished
                                            ? '已看完'
                                            : '播放至 ${percent.toInt()}% (${_formatDuration(item.currentTime)} / ${_formatDuration(item.duration)})',
                                        style: TextStyle(
                                          color: item.isFinished ? Colors.greenAccent : Colors.white54,
                                          fontSize: 11,
                                        ),
                                      ),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blueAccent.withValues(alpha: 0.15),
                                          foregroundColor: Colors.blueAccent,
                                          elevation: 0,
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          minimumSize: Size.zero,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                        ),
                                        icon: const Icon(Icons.play_arrow, size: 14),
                                        label: const Text('继续观看', style: TextStyle(fontSize: 11)),
                                        onPressed: () {
                                          Navigator.pop(context);
                                          widget.onResume(item);
                                        },
                                      ),
                                    ],
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
}
