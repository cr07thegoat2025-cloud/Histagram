import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../main.dart';

/// Private bucket holding photos, videos and voice notes sent in chats.
const chatBucket = 'tc-media';

/// A photo or video inside a chat bubble. Files are private, so each one is
/// shown through a temporary signed link (valid for one hour).
class MediaThumb extends StatefulWidget {
  final String path;
  final String type; // 'image' or 'video'

  const MediaThumb({super.key, required this.path, required this.type});

  @override
  State<MediaThumb> createState() => _MediaThumbState();
}

class _MediaThumbState extends State<MediaThumb> {
  late final Future<String> _url =
      db.storage.from(chatBucket).createSignedUrl(widget.path, 3600);

  Widget _box(BuildContext context, Widget child) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 220,
        height: 220,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _url,
      builder: (context, snap) {
        if (snap.hasError) {
          return _box(context,
              const Center(child: Icon(Icons.broken_image_outlined, size: 40)));
        }
        if (!snap.hasData) {
          return _box(context,
              const Center(child: CircularProgressIndicator(strokeWidth: 2)));
        }
        final url = snap.data!;
        if (widget.type == 'image') {
          return GestureDetector(
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => ImagePage(url: url))),
            child: _box(
              context,
              Image.network(
                url,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image_outlined, size: 40)),
              ),
            ),
          );
        }
        return GestureDetector(
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => VideoPage(url: url))),
          child: _box(
            context,
            Container(
              color: Colors.black87,
              child: const Center(
                child:
                    Icon(Icons.play_circle_fill, size: 56, color: Colors.white),
              ),
            ),
          ),
        );
      },
    );
  }
}

class ImagePage extends StatelessWidget {
  final String url;
  const ImagePage({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar:
          AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Text('Could not load photo',
                style: TextStyle(color: Colors.white)),
          ),
        ),
      ),
    );
  }
}

class VideoPage extends StatefulWidget {
  final String url;
  const VideoPage({super.key, required this.url});

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  late final VideoPlayerController _c;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _c.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _c.play();
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar:
          AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Center(
        child: _failed
            ? const Text('Could not play this video',
                style: TextStyle(color: Colors.white))
            : !_c.value.isInitialized
                ? const CircularProgressIndicator()
                : GestureDetector(
                    onTap: () => _c.value.isPlaying ? _c.pause() : _c.play(),
                    child: AspectRatio(
                      aspectRatio: _c.value.aspectRatio,
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          VideoPlayer(_c),
                          ValueListenableBuilder<VideoPlayerValue>(
                            valueListenable: _c,
                            builder: (context, v, _) => v.isPlaying
                                ? const SizedBox.shrink()
                                : const Positioned.fill(
                                    child: Center(
                                      child: Icon(Icons.play_circle_fill,
                                          size: 72, color: Colors.white70),
                                    ),
                                  ),
                          ),
                          VideoProgressIndicator(_c, allowScrubbing: true),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }
}

String _mmss(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// A voice note: tap to play or pause, with a progress bar and the length.
class VoiceBubble extends StatefulWidget {
  final String path;
  final int? durationMs; // recorded length, shown before the file is loaded

  const VoiceBubble({super.key, required this.path, this.durationMs});

  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble> {
  VideoPlayerController? _c;
  bool _loading = false;
  bool _failed = false;

  @override
  void dispose() {
    _c?.removeListener(_tick);
    _c?.dispose();
    super.dispose();
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  Future<void> _toggle() async {
    if (_loading) return;
    final existing = _c;
    if (existing != null) {
      if (existing.value.isPlaying) {
        await existing.pause();
      } else {
        final v = existing.value;
        if (v.duration > Duration.zero && v.position >= v.duration) {
          await existing.seekTo(Duration.zero);
        }
        await existing.play();
      }
      return;
    }
    // First tap: fetch a link and load the audio.
    setState(() {
      _loading = true;
      _failed = false;
    });
    VideoPlayerController? created;
    try {
      final url =
          await db.storage.from(chatBucket).createSignedUrl(widget.path, 3600);
      created = VideoPlayerController.networkUrl(Uri.parse(url));
      await created.initialize();
      created.addListener(_tick);
      _c = created;
      await created.play();
    } catch (_) {
      created?.dispose();
      _c = null;
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = _c;
    final playing = c?.value.isPlaying ?? false;
    final total = (c != null && c.value.duration > Duration.zero)
        ? c.value.duration
        : Duration(milliseconds: widget.durationMs ?? 0);
    final pos = c?.value.position ?? Duration.zero;
    final progress = total.inMilliseconds == 0
        ? 0.0
        : (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

    return SizedBox(
      width: 220,
      child: Row(
        children: [
          IconButton.filled(
            tooltip: playing ? 'Pause' : 'Play voice message',
            onPressed: _toggle,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(playing ? Icons.pause : Icons.play_arrow),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: scheme.onSurface.withAlpha(30),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _failed
                      ? 'Could not play. Tap to retry.'
                      : (c != null && c.value.isInitialized
                          ? '${_mmss(pos)} / ${_mmss(total)}'
                          : (total > Duration.zero
                              ? _mmss(total)
                              : 'Voice message')),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
