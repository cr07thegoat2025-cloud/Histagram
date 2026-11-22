import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../main.dart';
import '../screens/comments_screen.dart';
import '../screens/profile_screen.dart';
import '../util.dart';

class ReelsScreen extends StatefulWidget {
  /// False while another tab is showing, so the video stops playing.
  final bool active;
  const ReelsScreen({super.key, required this.active});

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
  static const _pageSize = 20;
  final _pages = PageController();
  final List<Map<String, dynamic>> _reels = [];
  int _index = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _fetch(String? before) async {
    final rows = await db.rpc('hg_reels_feed', params: {
      'p_limit': _pageSize,
      'p_before': before,
    });
    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _fetch(null);
      if (!mounted) return;
      setState(() {
        _reels
          ..clear()
          ..addAll(rows);
        _done = rows.length < _pageSize;
        _loading = false;
        _index = 0;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load reels. Check your internet.';
      });
    }
  }

  Future<void> _more() async {
    if (_loadingMore || _done || _reels.isEmpty) return;
    _loadingMore = true;
    try {
      final rows = await _fetch(_reels.last['created_at'] as String);
      if (!mounted) return;
      setState(() {
        _reels.addAll(rows);
        _done = rows.length < _pageSize;
      });
    } catch (_) {
      // Try again on the next swipe.
    } finally {
      _loadingMore = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_loading) {
      body = const Center(
          child: CircularProgressIndicator(color: Colors.white));
    } else if (_error != null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    } else if (_reels.isEmpty) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No reels yet. Tap the + button and choose "Reel" to share the first one.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    } else {
      body = PageView.builder(
        controller: _pages,
        scrollDirection: Axis.vertical,
        itemCount: _reels.length,
        onPageChanged: (i) {
          setState(() => _index = i);
          if (i >= _reels.length - 3) _more();
        },
        itemBuilder: (context, i) => ReelPage(
          key: ValueKey(_reels[i]['id']),
          reel: _reels[i],
          playing: widget.active && i == _index,
          onDeleted: () => setState(() {
            _reels.removeAt(i);
          }),
        ),
      );
    }
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(child: body),
          SafeArea(
            child: const Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text('Reels',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}

class ReelPage extends StatefulWidget {
  final Map<String, dynamic> reel;
  final bool playing;
  final VoidCallback onDeleted;

  const ReelPage({
    super.key,
    required this.reel,
    required this.playing,
    required this.onDeleted,
  });

  @override
  State<ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<ReelPage> {
  VideoPlayerController? _c;
  bool _failed = false;
  bool _paused = false;
  late bool _liked;
  late int _likes;
  late int _comments;

  Map<String, dynamic> get r => widget.reel;
  String get _me => db.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _liked = r['liked_by_me'] == true;
    _likes = intOf(r['like_count']);
    _comments = intOf(r['comment_count']);
    if (widget.playing) _start();
  }

  @override
  void didUpdateWidget(ReelPage old) {
    super.didUpdateWidget(old);
    if (widget.playing && !old.playing) {
      _start();
    } else if (!widget.playing && old.playing) {
      _stop();
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_c != null) {
      if (!_paused) _c!.play();
      return;
    }
    try {
      final url =
          await signedUrl(r['video_path'] as String, bucket: reelsBucket);
      final c = VideoPlayerController.networkUrl(Uri.parse(url));
      await c.initialize();
      await c.setLooping(true);
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _c = c);
      if (widget.playing && !_paused) await c.play();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _stop() {
    final c = _c;
    if (c == null) return;
    c.pause();
    c.seekTo(Duration.zero);
    // Free the decoder when scrolled away; it is recreated on return.
    c.dispose();
    setState(() {
      _c = null;
      _paused = false;
    });
  }

  void _toggle() {
    final c = _c;
    if (c == null) return;
    setState(() {
      _paused = !_paused;
      _paused ? c.pause() : c.play();
    });
  }

  Future<void> _like() async {
    final was = _liked;
    setState(() {
      _liked = !was;
      _likes += was ? -1 : 1;
    });
    try {
      if (was) {
        await db
            .from('hg_reel_likes')
            .delete()
            .eq('reel_id', r['id'])
            .eq('user_id', _me);
      } else {
        await db
            .from('hg_reel_likes')
            .insert({'reel_id': r['id'], 'user_id': _me});
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _liked = was;
        _likes += was ? 1 : -1;
      });
      showSnack(context, 'Could not update your like.');
    }
  }

  Future<void> _openComments() async {
    _c?.pause();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CommentsScreen(
          postId: r['id'] as String,
          postOwnerId: r['user_id'] as String,
          table: 'hg_reel_comments',
          idColumn: 'reel_id',
        ),
      ),
    );
    if (!mounted) return;
    if (widget.playing && !_paused) _c?.play();
    try {
      final rows = await db
          .from('hg_reel_comments')
          .select('id')
          .eq('reel_id', r['id']);
      if (mounted) setState(() => _comments = (rows as List).length);
    } catch (_) {}
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this reel?'),
        content: const Text('This can\'t be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await db.from('hg_reels').delete().eq('id', r['id']);
      try {
        await db.storage
            .from(reelsBucket)
            .remove([r['video_path'] as String]);
      } catch (_) {}
      widget.onDeleted();
    } catch (_) {
      if (mounted) showSnack(context, 'Could not delete the reel.');
    }
  }

  void _openProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => ProfileScreen(userId: r['user_id'] as String)),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap,
      {Color color = Colors.white}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            children: [
              Icon(icon, size: 32, color: color),
              if (label.isNotEmpty)
                Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final username = r['username'] as String? ?? 'user';
    final caption = (r['caption'] as String?) ?? '';
    final mine = r['user_id'] == _me;
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          onDoubleTap: () {
            if (!_liked) _like();
          },
          child: Center(
            child: _failed
                ? const Text('Could not play this reel.',
                    style: TextStyle(color: Colors.white70))
                : (c == null || !c.value.isInitialized)
                    ? const CircularProgressIndicator(color: Colors.white)
                    : FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: c.value.size.width,
                          height: c.value.size.height,
                          child: VideoPlayer(c),
                        ),
                      ),
          ),
        ),
        if (_paused)
          const IgnorePointer(
            child: Center(
              child: Icon(Icons.play_arrow_rounded,
                  size: 88, color: Colors.white70),
            ),
          ),
        // Dark gradient so the text stays readable on bright videos.
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 220,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xAA000000)],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 8,
          bottom: 24,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _action(
                _liked ? Icons.favorite : Icons.favorite_border,
                '$_likes',
                _like,
                color: _liked ? Colors.redAccent : Colors.white,
              ),
              _action(Icons.mode_comment_outlined, '$_comments',
                  _openComments),
              if (mine) _action(Icons.delete_outline, '', _delete),
            ],
          ),
        ),
        Positioned(
          left: 16,
          right: 84,
          bottom: 24,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: _openProfile,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Avatar(
                        path: r['avatar_path'] as String?,
                        name: username,
                        radius: 16),
                    const SizedBox(width: 8),
                    Text(username,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                  ],
                ),
              ),
              if (caption.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(caption,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white)),
              ],
            ],
          ),
        ),
        if (c != null && c.value.isInitialized)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: VideoProgressIndicator(
              c,
              allowScrubbing: true,
              padding: EdgeInsets.zero,
              colors: const VideoProgressColors(
                playedColor: Colors.white,
                bufferedColor: Colors.white24,
                backgroundColor: Colors.white12,
              ),
            ),
          ),
      ],
    );
  }
}
