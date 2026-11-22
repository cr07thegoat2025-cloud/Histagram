import 'package:flutter/material.dart';

import '../main.dart';
import '../util.dart';

class CommentsScreen extends StatefulWidget {
  final String postId; // the post's id (or the reel's id)
  final String postOwnerId;
  final String table; // 'hg_comments' for posts, 'hg_reel_comments' for reels
  final String idColumn; // 'post_id' or 'reel_id'

  const CommentsScreen({
    super.key,
    required this.postId,
    required this.postOwnerId,
    this.table = 'hg_comments',
    this.idColumn = 'post_id',
  });

  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _comments = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  String get _me => db.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await db
          .from(widget.table)
          .select('id,user_id,body,created_at,hg_profiles(username,avatar_path)')
          .eq(widget.idColumn, widget.postId)
          .order('created_at', ascending: true);
      if (!mounted) return;
      setState(() {
        _comments = (rows as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load comments.';
      });
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await db.from(widget.table).insert({
        widget.idColumn: widget.postId,
        'user_id': _me,
        'body': text,
      });
      _controller.clear();
      await _load();
    } catch (_) {
      if (mounted) showSnack(context, 'Could not post your comment.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(String id) async {
    try {
      await db.from(widget.table).delete().eq('id', id);
      await _load();
    } catch (_) {
      if (mounted) showSnack(context, 'Could not delete the comment.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Comments')),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _comments.isEmpty
                        ? const Center(
                            child: Text('No comments yet. Start the conversation.'))
                        : ListView.builder(
                            itemCount: _comments.length,
                            itemBuilder: (context, i) {
                              final c = _comments[i];
                              final profile = Map<String, dynamic>.from(
                                  (c['hg_profiles'] as Map?) ?? {});
                              final username =
                                  profile['username'] as String? ?? 'user';
                              final canDelete = c['user_id'] == _me ||
                                  widget.postOwnerId == _me;
                              return ListTile(
                                leading: Avatar(
                                    path: profile['avatar_path'] as String?,
                                    name: username,
                                    radius: 18),
                                title: Text.rich(TextSpan(children: [
                                  TextSpan(
                                      text: '$username ',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  TextSpan(text: c['body'] as String? ?? ''),
                                ])),
                                subtitle: Text(
                                  timeAgo(DateTime.parse(
                                          c['created_at'] as String)
                                      .toLocal()),
                                  style: TextStyle(color: scheme.onSurfaceVariant),
                                ),
                                trailing: canDelete
                                    ? IconButton(
                                        tooltip: 'Delete comment',
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () =>
                                            _delete(c['id'] as String),
                                      )
                                    : null,
                              );
                            },
                          ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 500,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Add a comment...',
                        counterText: '',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: _sending ? null : _send,
                    child: const Text('Post'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
