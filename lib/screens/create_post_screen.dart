import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import '../util.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _picker = ImagePicker();
  final _caption = TextEditingController();
  XFile? _file;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Open the gallery straight away, like a camera roll.
    WidgetsBinding.instance.addPostFrameCallback((_) => _pick());
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final f = await _picker.pickImage(
          source: ImageSource.gallery, imageQuality: 85, maxWidth: 1440);
      if (f != null && mounted) setState(() => _file = f);
    } catch (_) {
      if (mounted) showSnack(context, 'Could not open your gallery.');
    }
  }

  Future<void> _share() async {
    final f = _file;
    if (f == null || _busy) return;
    setState(() => _busy = true);
    final me = db.auth.currentUser!.id;
    final ext = imageExt(f.name);
    final path = '$me/${DateTime.now().microsecondsSinceEpoch}.$ext';
    try {
      await db.storage.from(mediaBucket).upload(
            path,
            File(f.path),
            fileOptions: FileOptions(contentType: imageMime(ext)),
          );
      await db.from('hg_posts').insert({
        'user_id': me,
        'image_path': path,
        'caption': _caption.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showSnack(context, 'Could not share your post. Check your internet.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('New post'),
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
            child: AspectRatio(
              aspectRatio: 1,
              child: _file == null
                  ? Container(
                      color: scheme.surfaceContainerHighest,
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_photo_alternate_outlined, size: 48),
                            SizedBox(height: 8),
                            Text('Tap to choose a photo'),
                          ],
                        ),
                      ),
                    )
                  : Image.file(File(_file!.path), fit: BoxFit.cover),
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
