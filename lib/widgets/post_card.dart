import 'package:flutter/material.dart';

import '../main.dart';
import '../screens/comments_screen.dart';
import '../screens/profile_screen.dart';
import '../util.dart';

class PostCard extends StatefulWidget {
  final Map<String, dynamic> post;
  final VoidCallback? onDeleted;

  const PostCard({super.key, required this.post, this.onDeleted});

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  late bool _liked = widget.post['liked_by_me'] == true;
  late int _likes = intOf(widget.post['like_count']);
  late int _comments = intOf(widget.post['comment_count']);
  bool _heart = false;

  String get _id => widget.post['id'] as String;
  String get _me => db.auth.currentUser!.id;

  Future<void> _toggleLike() async {
    final was = _liked;
    setState(() {
      _liked = !was;
      _likes += was ? -1 : 1;
    });
    try {
      if (was) {
        await db.from('hg_likes').delete().eq('post_id', _id).eq('user_id', _me);
      } else {
        await db.from('hg_likes').insert({'post_id': _id, 'user_id': _me});
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

  void _doubleTap() {
    if (!_liked) _toggleLike();
    setState(() => _heart = true);
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _heart = false);
    });
  }

  Future<void> _openComments() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            CommentsScreen(postId: _id, postOwnerId: widget.post['user_id'] as String),
      ),
    );
    try {
      final rows = await db.rpc('hg_get_post', params: {'p_id': _id});
      if (!mounted || (rows as List).isEmpty) return;
      setState(() => _comments = intOf((rows.first as Map)['comment_count']));
    } catch (_) {}
  }

  void _openProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => ProfileScreen(userId: widget.post['user_id'] as String)),
    );
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this post?'),
        content: const Text('This can\'t be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await db.from('hg_posts').delete().eq('id', _id);
      try {
        await db.storage
            .from(mediaBucket)
            .remove([widget.post['image_path'] as String]);
      } catch (_) {}
      widget.onDeleted?.call();
    } catch (_) {
      if (mounted) showSnack(context, 'Could not delete the post.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final mine = p['user_id'] == _me;
    final username = p['username'] as String? ?? '';
    final caption = (p['caption'] as String?) ?? '';
    final created = DateTime.parse(p['created_at'] as String).toLocal();
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _openProfile,
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      children: [
                        Avatar(
                            path: p['avatar_path'] as String?,
                            name: username,
                            radius: 16),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(username,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                ),
                if (mine)
                  PopupMenuButton<String>(
                    onSelected: (_) => _delete(),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'delete', child: Text('Delete post')),
                    ],
                  ),
              ],
            ),
          ),
          GestureDetector(
            onDoubleTap: _doubleTap,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: SignedImage(path: p['image_path'] as String),
                ),
                AnimatedOpacity(
                  opacity: _heart ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: const Icon(Icons.favorite,
                      size: 96, color: Colors.white),
                ),
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                tooltip: _liked ? 'Unlike' : 'Like',
                onPressed: _toggleLike,
                icon: Icon(_liked ? Icons.favorite : Icons.favorite_border,
                    color: _liked ? Colors.redAccent : null),
              ),
              IconButton(
                tooltip: 'Comments',
                onPressed: _openComments,
                icon: const Icon(Icons.mode_comment_outlined),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$_likes ${_likes == 1 ? 'like' : 'likes'}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                if (caption.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text.rich(TextSpan(children: [
                    TextSpan(
                        text: '$username ',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: caption),
                  ])),
                ],
                if (_comments > 0)
                  GestureDetector(
                    onTap: _openComments,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                          _comments == 1
                              ? 'View 1 comment'
                              : 'View all $_comments comments',
                          style: TextStyle(color: scheme.onSurfaceVariant)),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(timeAgo(created),
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
