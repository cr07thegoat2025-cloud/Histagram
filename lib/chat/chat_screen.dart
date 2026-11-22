import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import '../util.dart' show Avatar;
import 'chat_media.dart';

const maxMediaBytes = 50 * 1024 * 1024; // matches the 50 MB bucket limit
const maxVoiceSeconds = 5 * 60;

const _mimeByExt = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'gif': 'image/gif',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
  'webm': 'video/webm',
  '3gp': 'video/3gpp',
  'mkv': 'video/x-matroska',
};

/// "just now", "5 min ago", "3 h ago", "2 d ago". Older than a week: a date.
String chatTimeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 10) return 'just now'; // also covers small clock skew
  if (d.inSeconds < 60) return '${d.inSeconds} sec ago';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays < 7) return '${d.inDays} d ago';
  return DateFormat.yMMMd().format(t);
}

DateTime? _parse(dynamic v) =>
    v == null ? null : DateTime.parse(v as String).toLocal();

String _clock(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String otherName;
  final String? otherAvatarPath;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.otherName,
    this.otherAvatarPath,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _meId = db.auth.currentUser!.id;
  late final Stream<List<Map<String, dynamic>>> _stream = db
      .from('tc_messages')
      .stream(primaryKey: ['id'])
      .eq('chat_id', widget.chatId)
      .order('created_at', ascending: false)
      .limit(200);

  final _picker = ImagePicker();
  final _recorder = AudioRecorder();
  Timer? _ticker;
  Timer? _recTimer;
  Stopwatch? _recWatch;
  bool _foreground = true;
  bool _marking = false;
  bool _uploading = false;
  bool _recording = false;
  bool _hasText = false;
  int _recSeconds = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText && mounted) setState(() => _hasText = has);
    });
    // Re-draw every 15 s so "5 min ago" keeps counting up.
    _ticker = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _recTimer?.cancel();
    if (_recording) _recorder.cancel();
    _recorder.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _markRead();
  }

  /// Tell the server that the messages you can see on screen have been seen.
  Future<void> _markRead() async {
    if (_marking || !_foreground || !mounted) return;
    _marking = true;
    try {
      await db.rpc('tc_mark_read', params: {'p_chat': widget.chatId});
    } catch (_) {
      // Best effort. It will be retried on the next message or app resume.
    } finally {
      _marking = false;
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    try {
      await db.from('tc_messages').insert({
        'chat_id': widget.chatId,
        'sender_id': _meId,
        'body': text,
      });
    } catch (e) {
      if (!mounted) return;
      _controller.text = text;
      _snack('Message not sent: $e');
    }
  }

  // ---- photos and videos ----

  Future<void> _attach() async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('Photo'),
              onTap: () => Navigator.pop(ctx, 'image'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Video'),
              onTap: () => Navigator.pop(ctx, 'video'),
            ),
          ],
        ),
      ),
    );
    if (kind == null) return;
    try {
      final XFile? file = kind == 'image'
          ? await _picker.pickImage(
              source: ImageSource.gallery, imageQuality: 85, maxWidth: 2048)
          : await _picker.pickVideo(source: ImageSource.gallery);
      if (file == null) return;
      await _sendMedia(file, kind);
    } catch (e) {
      _snack('Could not open your gallery: $e');
    }
  }

  String _extension(String name, String kind) {
    final dot = name.lastIndexOf('.');
    var e = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    e = e.replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (e.isEmpty || e.length > 5) e = kind == 'image' ? 'jpg' : 'mp4';
    return e;
  }

  Future<void> _sendMedia(XFile file, String kind) async {
    final size = await file.length();
    if (size > maxMediaBytes) {
      _snack('That file is too big. The limit is 50 MB.');
      return;
    }
    if (!mounted) return;
    setState(() => _uploading = true);
    final ext = _extension(file.name, kind);
    final mime =
        _mimeByExt[ext] ?? (kind == 'image' ? 'image/jpeg' : 'video/mp4');
    final path = '${widget.chatId}/${DateTime.now().microsecondsSinceEpoch}.$ext';
    try {
      await db.storage.from(chatBucket).upload(
            path,
            File(file.path),
            fileOptions: FileOptions(contentType: mime),
          );
      // Anything typed in the box is sent as the caption.
      final caption = _controller.text.trim();
      await db.from('tc_messages').insert({
        'chat_id': widget.chatId,
        'sender_id': _meId,
        'body': caption,
        'media_path': path,
        'media_type': kind,
      });
      _controller.clear();
    } catch (e) {
      _snack('Could not send the ${kind == 'image' ? 'photo' : 'video'}: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ---- voice notes ----

  Future<void> _startRecording() async {
    if (_recording || _uploading) return;
    try {
      if (!await _recorder.hasPermission()) {
        _snack('Allow microphone access to send voice messages.');
        return;
      }
      final path =
          '${Directory.systemTemp.path}/voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path,
      );
      _recWatch = Stopwatch()..start();
      _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        final s = _recWatch?.elapsed.inSeconds ?? 0;
        if (mounted) setState(() => _recSeconds = s);
        if (s >= maxVoiceSeconds) _finishRecording(send: true);
      });
      if (mounted) {
        setState(() {
          _recording = true;
          _recSeconds = 0;
        });
      }
    } catch (e) {
      _snack('Could not start recording: $e');
    }
  }

  Future<void> _finishRecording({required bool send}) async {
    if (!_recording) return;
    _recTimer?.cancel();
    final ms = _recWatch?.elapsedMilliseconds ?? 0;
    _recWatch?.stop();
    if (mounted) setState(() => _recording = false);

    String? path;
    try {
      if (send) {
        path = await _recorder.stop();
      } else {
        await _recorder.cancel();
      }
    } catch (_) {
      // fall through: nothing to send
    }
    if (!send || path == null) return;

    if (ms < 700) {
      _snack('That was too short. Hold on a little longer.');
      try {
        await File(path).delete();
      } catch (_) {}
      return;
    }
    await _sendVoice(File(path), ms);
  }

  Future<void> _sendVoice(File file, int ms) async {
    if (!mounted) return;
    setState(() => _uploading = true);
    final path = '${widget.chatId}/${DateTime.now().microsecondsSinceEpoch}.m4a';
    try {
      await db.storage.from(chatBucket).upload(
            path,
            file,
            fileOptions: const FileOptions(contentType: 'audio/mp4'),
          );
      await db.from('tc_messages').insert({
        'chat_id': widget.chatId,
        'sender_id': _meId,
        'body': '',
        'media_path': path,
        'media_type': 'audio',
        'media_ms': ms,
      });
    } catch (e) {
      _snack('Could not send the voice message: $e');
    } finally {
      try {
        await file.delete();
      } catch (_) {}
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ---- UI ----

  Widget _inputBar(ColorScheme scheme) {
    if (_recording) {
      return Row(
        children: [
          IconButton(
            tooltip: 'Discard recording',
            onPressed: () => _finishRecording(send: false),
            icon: const Icon(Icons.delete_outline),
          ),
          Icon(Icons.fiber_manual_record, color: scheme.error, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Recording  ${_clock(_recSeconds)}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          IconButton.filled(
            tooltip: 'Send voice message',
            onPressed: () => _finishRecording(send: true),
            icon: const Icon(Icons.send),
          ),
        ],
      );
    }
    return Row(
      children: [
        IconButton(
          tooltip: 'Send a photo or video',
          onPressed: _uploading ? null : _attach,
          icon: const Icon(Icons.attach_file),
        ),
        Expanded(
          child: TextField(
            controller: _controller,
            minLines: 1,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Message',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (_hasText)
          IconButton.filled(
              tooltip: 'Send', onPressed: _send, icon: const Icon(Icons.send))
        else
          IconButton.filled(
            tooltip: 'Record a voice message',
            onPressed: _uploading ? null : _startRecording,
            icon: const Icon(Icons.mic),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.labelSmall;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Avatar(
                path: widget.otherAvatarPath,
                name: widget.otherName,
                radius: 16),
            const SizedBox(width: 10),
            Flexible(
                child: Text(widget.otherName, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _stream,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final msgs = snap.data!;
                if (msgs.isEmpty) {
                  return const Center(child: Text('Say hi 👋'));
                }

                // Any message from them that I haven't marked as seen yet?
                final hasUnseen = msgs
                    .any((m) => m['sender_id'] != _meId && m['read_at'] == null);
                if (hasUnseen) {
                  WidgetsBinding.instance
                      .addPostFrameCallback((_) => _markRead());
                }

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: msgs.length,
                  itemBuilder: (context, i) {
                    final m = msgs[i];
                    final mine = m['sender_id'] == _meId;
                    final sent = _parse(m['created_at']);
                    final seen = _parse(m['read_at']);
                    final mediaPath = m['media_path'] as String?;
                    final mediaType = (m['media_type'] as String?) ?? 'image';
                    final body = m['body'] as String? ?? '';
                    return Align(
                      key: ValueKey(m['id']),
                      alignment:
                          mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75),
                        decoration: BoxDecoration(
                          color: mine
                              ? scheme.primaryContainer
                              : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (mediaPath != null)
                              Padding(
                                padding: EdgeInsets.only(
                                    bottom: body.isEmpty ? 0 : 6),
                                child: mediaType == 'audio'
                                    ? VoiceBubble(
                                        path: mediaPath,
                                        durationMs: (m['media_ms'] as num?)?.toInt(),
                                      )
                                    : MediaThumb(
                                        path: mediaPath, type: mediaType),
                              ),
                            if (body.isNotEmpty) Text(body),
                            const SizedBox(height: 2),
                            if (sent != null)
                              Text(
                                  mine
                                      ? 'Sent ${chatTimeAgo(sent)}'
                                      : chatTimeAgo(sent),
                                  style: small),
                            if (mine)
                              Text(
                                seen != null
                                    ? 'Seen ${chatTimeAgo(seen)}'
                                    : 'Not seen yet',
                                style: small?.copyWith(
                                  color: seen != null ? scheme.primary : null,
                                  fontWeight: seen != null
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (_uploading) const LinearProgressIndicator(minHeight: 3),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: _inputBar(scheme),
            ),
          ),
        ],
      ),
    );
  }
}
