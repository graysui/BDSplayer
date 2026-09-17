import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class NativePlayerTheater extends StatefulWidget {
  final FileItem video;
  final PlayResult playData;
  final List<FileItem> playlist;
  final VoidCallback onClose;
  final Function(FileItem) onSwitchVideo;

  const NativePlayerTheater({
    super.key,
    required this.video,
    required this.playData,
    required this.playlist,
    required this.onClose,
    required this.onSwitchVideo,
  });

  @override
  State<NativePlayerTheater> createState() => _NativePlayerTheaterState();
}

class _NativePlayerTheaterState extends State<NativePlayerTheater> {
  late final Player player;
  late final VideoController controller;
  final ApiService _api = ApiService();

  bool _showControls = true;
  Timer? _hideTimer;
  Timer? _progressSyncTimer;
  bool _showPlaylistDrawer = false;
  double _volume = 100.0;
  double _playbackSpeed = 1.0;
  bool _hasRestoredPosition = false;

  @override
  void initState() {
    super.initState();
    player = Player(
      configuration: const PlayerConfiguration(
        title: 'Baidu Share Player',
        bufferSize: 32 * 1024 * 1024,
      ),
    );
    controller = VideoController(player);

    _startPlayback();
    _resetHideTimer();

    // Listen for playback stream to accurately seek when player starts playing
    player.stream.playing.listen((isPlaying) {
      if (isPlaying && !_hasRestoredPosition) {
        if (widget.playData.currentTime > 3.0) {
          _hasRestoredPosition = true;
          player.seek(Duration(milliseconds: (widget.playData.currentTime * 1000).toInt()));
        }
      }
    });

    // Sync progress every 3 seconds
    _progressSyncTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _syncProgress();
    });
  }

  void _startPlayback() async {
    final targetUrl = widget.playData.rawDlink.isNotEmpty 
        ? widget.playData.rawDlink 
        : widget.playData.streamUrl;

    await player.open(
      Media(
        targetUrl,
        httpHeaders: {
          'User-Agent': 'pan.baidu.com',
          'Referer': 'https://pan.baidu.com',
        },
      ),
      play: true,
    );
  }

  void _syncProgress() {
    final pos = player.state.position.inMilliseconds / 1000.0;
    final dur = player.state.duration.inMilliseconds / 1000.0;
    if (dur > 0 && pos > 0) {
      _api.saveProgress(
        videoId: widget.playData.videoId,
        shareKey: widget.playData.videoId.split('_').first,
        shareFsId: widget.video.fsId,
        videoName: widget.video.name,
        currentTime: pos,
        duration: dur,
      );
    }
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    setState(() => _showControls = true);
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && player.state.playing) {
        setState(() => _showControls = false);
      }
    });
  }

  @override
  void dispose() {
    _syncProgress();
    _hideTimer?.cancel();
    _progressSyncTimer?.cancel();
    player.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.space) {
            player.playOrPause();
            _resetHideTimer();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            player.seek(player.state.position + const Duration(seconds: 10));
            _resetHideTimer();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            player.seek(player.state.position - const Duration(seconds: 10));
            _resetHideTimer();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.escape) {
            if (_showPlaylistDrawer) {
              setState(() => _showPlaylistDrawer = false);
            } else {
              widget.onClose();
            }
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onHover: (_) => _resetHideTimer(),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              // 1. Hardware-accelerated Video Frame (Rendered as GPU texture)
              Center(
                child: Video(
                  controller: controller,
                  controls: NoVideoControls,
                ),
              ),

              // 2. Overlay Controls (Pure Flutter Widgets - Zero Airspace issue!)
              AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: Stack(
                    children: [
                      // Top Bar
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.black.withValues(alpha: 0.85), Colors.transparent],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back, color: Colors.white),
                                tooltip: '返回 (Esc)',
                                onPressed: widget.onClose,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      widget.video.name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.blueAccent.withValues(alpha: 0.25),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.5)),
                                          ),
                                          child: const Text(
                                            '⚡ MPV GPU 极速直连 (无 Chromium 缺陷)',
                                            style: TextStyle(color: Colors.blueAccent, fontSize: 11),
                                          ),
                                        ),
                                        if (widget.playData.currentTime > 3.0) ...[
                                          const SizedBox(width: 8),
                                          Text(
                                            '已从上次进度继续播放',
                                            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.playlist_play, color: Colors.white),
                                tooltip: '播放列表',
                                onPressed: () => setState(() => _showPlaylistDrawer = !_showPlaylistDrawer),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Bottom Controls
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Progress Bar Stream
                              StreamBuilder<Duration>(
                                stream: player.stream.position,
                                builder: (context, snapshot) {
                                  final pos = snapshot.data ?? Duration.zero;
                                  final dur = player.state.duration;
                                  final maxMs = dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
                                  final currMs = pos.inMilliseconds.clamp(0, dur.inMilliseconds).toDouble();

                                  return Row(
                                    children: [
                                      Text(
                                        _formatDuration(pos),
                                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: SliderTheme(
                                          data: SliderTheme.of(context).copyWith(
                                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                                            activeTrackColor: Colors.blueAccent,
                                            inactiveTrackColor: Colors.white24,
                                            thumbColor: Colors.blueAccent,
                                          ),
                                          child: Slider(
                                            value: currMs,
                                            min: 0,
                                            max: maxMs,
                                            onChanged: (val) {
                                              player.seek(Duration(milliseconds: val.toInt()));
                                              _resetHideTimer();
                                            },
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        _formatDuration(dur),
                                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                                      ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 6),

                              // Button Controls
                              Row(
                                children: [
                                  StreamBuilder<bool>(
                                    stream: player.stream.playing,
                                    builder: (context, snapshot) {
                                      final playing = snapshot.data ?? false;
                                      return IconButton(
                                        icon: Icon(
                                          playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
                                          color: Colors.white,
                                          size: 36,
                                        ),
                                        onPressed: () {
                                          player.playOrPause();
                                          _resetHideTimer();
                                        },
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 8),

                                  // Quick 10s Rewind / Forward
                                  IconButton(
                                    icon: const Icon(Icons.replay_10, color: Colors.white70),
                                    tooltip: '后退 10 秒',
                                    onPressed: () => player.seek(player.state.position - const Duration(seconds: 10)),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.forward_10, color: Colors.white70),
                                    tooltip: '前进 10 秒',
                                    onPressed: () => player.seek(player.state.position + const Duration(seconds: 10)),
                                  ),
                                  const SizedBox(width: 16),

                                  // Volume Slider
                                  const Icon(Icons.volume_up, color: Colors.white70, size: 20),
                                  SizedBox(
                                    width: 100,
                                    child: Slider(
                                      value: _volume,
                                      min: 0,
                                      max: 100,
                                      onChanged: (val) {
                                        setState(() => _volume = val);
                                        player.setVolume(val);
                                        _resetHideTimer();
                                      },
                                    ),
                                  ),
                                  const Spacer(),

                                  // Playback Rate selector
                                  PopupMenuButton<double>(
                                    initialValue: _playbackSpeed,
                                    tooltip: '倍速播放',
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.white12,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '${_playbackSpeed}x',
                                        style: const TextStyle(color: Colors.white, fontSize: 13),
                                      ),
                                    ),
                                    onSelected: (rate) {
                                      setState(() => _playbackSpeed = rate);
                                      player.setRate(rate);
                                    },
                                    itemBuilder: (context) => [
                                      for (final rate in [0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0])
                                        PopupMenuItem(value: rate, child: Text('${rate}x')),
                                    ],
                                  ),
                                  const SizedBox(width: 16),

                                  // Playlist Drawer Toggle
                                  IconButton(
                                    icon: const Icon(Icons.video_library, color: Colors.white70),
                                    tooltip: '选集',
                                    onPressed: () => setState(() => _showPlaylistDrawer = !_showPlaylistDrawer),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 3. Slide-in Playlist Drawer (Right Side)
              if (_showPlaylistDrawer)
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  width: 320,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF141820).withValues(alpha: 0.95),
                      border: const Border(left: BorderSide(color: Colors.white12)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 20,
                          offset: const Offset(-5, 0),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '播放列表 (${widget.playlist.length})',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                                onPressed: () => setState(() => _showPlaylistDrawer = false),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: Colors.white12),
                        Expanded(
                          child: ListView.builder(
                            itemCount: widget.playlist.length,
                            itemBuilder: (context, idx) {
                              final item = widget.playlist[idx];
                              final isCurrent = item.fsId == widget.video.fsId;

                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  isCurrent ? Icons.play_circle_fill : Icons.movie_outlined,
                                  color: isCurrent ? Colors.blueAccent : Colors.white38,
                                  size: 20,
                                ),
                                title: Text(
                                  item.name,
                                  style: TextStyle(
                                    color: isCurrent ? Colors.blueAccent : Colors.white,
                                    fontSize: 13,
                                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () {
                                  if (!isCurrent) {
                                    setState(() => _showPlaylistDrawer = false);
                                    widget.onSwitchVideo(item);
                                  }
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
