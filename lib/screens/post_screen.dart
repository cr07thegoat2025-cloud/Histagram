import 'package:flutter/material.dart';

import '../main.dart';
import '../util.dart';
import '../widgets/post_card.dart';

class PostScreen extends StatefulWidget {
  final String postId;
  const PostScreen({super.key, required this.postId});

  @override
  State<PostScreen> createState() => _PostScreenState();
}

class _PostScreenState extends State<PostScreen> {
  Map<String, dynamic>? _post;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await db.rpc('hg_get_post', params: {'p_id': widget.postId});
      if (!mounted) return;
      setState(() {
        final list = rows as List;
        _post = list.isEmpty ? null : Map<String, dynamic>.from(list.first as Map);
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        showSnack(context, 'Could not load the post.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Post')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _post == null
              ? const Center(child: Text('This post is no longer available.'))
              : ListView(
                  children: [
                    PostCard(
                      post: _post!,
                      onDeleted: () {
                        if (mounted) Navigator.pop(context);
                      },
                    ),
                  ],
                ),
    );
  }
}
