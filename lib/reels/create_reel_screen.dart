import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../main.dart';
import '../util.dart';

class CreateReelScreen extends StatefulWidget {
  const CreateReelScreen({super.key});

  @override
  State<CreateReelScreen> createState() => _CreateReelScreenState();
}

class _CreateReelScreenState extends State<CreateReelScreen> {
  final _picker = ImagePicker();
  final _caption = TextEditingController();
  XFile? _file;
  VideoPlayerController? _video;
  int _durationMs = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pick());
  }

  @override
  void dispose() {
    _caption.dispose();
    _video?.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final f = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: maxReelSeconds),
      );
      if (f == null || !mounted) return;
      final size = await File(f.path).length();
      if (size > maxReelBytes) {
        if (mounted) showSnack(context, 'That video is over 50 MB. Pick a shorter one.');
        return;
      }
      final c = VideoPlayerController.file(File(f.path));
      await c.initialize();
      final ms = c.value.duration.inMilliseconds;
      if (ms > maxReelSeconds * 1000 + 500) {
        await c.dispose();
        if (mounted) {
          showSnack(context, 'Reels can be up to $maxReelSeconds seconds long.');
        }
        return;
      }
      await c.setLooping(true);
      await c.play();
      if (!mounted) {
        await c.dispose();
        return;
      }
      final old = _video;
      setState(() {
        _file = f;
        _video = c;
        _durationMs = ms;
      });
      await old?.dispose();
    } catch (_) {
      if (mounted) showSnack(context, 'Could not open that video.');
    }
  }

  Future<void> _share() async {
    final f = _file;
    if (f == null || _busy) return;
    setState(() => _busy = true);
    _video?.pause();
    final me = db.auth.currentUser!.id;
    final ext = videoExt(f.name);
    final path = '$me/${DateTime.now().microsecondsSinceEpoch}.$ext';
    try {
      await db.storage.from(reelsBucket).upload(
            path,
            File(f.path),
            fileOptions: FileOptions(contentType: videoMime(ext)),
          );
      await db.from('hg_reels').insert({
        'user_id': me,
        'video_path': path,
        'caption': _caption.text.trim(),
        'duration_ms': _durationMs,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        showSnack(context, 'Could not share your reel. Check your internet.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final v = _video;
    return Scaffold(
      appBar: AppBar(
        title: const Text('New reel'),
        actions: [
          TextButton(
            onPressed: (_file == null || _busy) ? null : _share,
            child: const Text('Share'),
          ),
        ],
      ),
      body: ListView(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 3),
          GestureDetector(
            onTap: _busy ? null : _pick,
            child: Container(
              height: 360,
              color: Colors.black,
              alignment: Alignment.center,
              child: v == null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.video_library_outlined,
                            size: 48, color: scheme.onSurfaceVariant),
                        const SizedBox(height: 8),
                        Text('Tap to choose a video',
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                      ],
                    )
                  : AspectRatio(
                      aspectRatio: v.value.aspectRatio,
                      child: VideoPlayer(v),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _caption,
              maxLength: 2200,
              minLines: 2,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Write a caption...',
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
