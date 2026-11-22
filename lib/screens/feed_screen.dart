import 'package:flutter/material.dart';

import '../main.dart';
import '../util.dart';
import '../widgets/post_card.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  List<Map<String, dynamic>> _posts = [];
  bool _loading = true;
  bool _explore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _posts.isEmpty;
      _error = null;
    });
    try {
      final rows = await db.rpc('hg_feed', params: {
        'p_scope': _explore ? 'explore' : 'following',
        'p_limit': 30,
      });
      if (!mounted) return;
      setState(() {
        _posts = (rows as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load posts. Pull down to try again.';
        _loading = false;
      });
    }
  }

  void _toggleScope() {
    setState(() {
      _explore = !_explore;
      _posts = [];
    });
    _load();
  }

  Widget _message(String text, {Widget? action}) => Padding(
        padding: const EdgeInsets.fromLTRB(32, 96, 32, 32),
        child: Column(
          children: [
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action],
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const HistagramLogo(),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: _explore ? 'Show people I follow' : 'Explore everyone',
            icon: Icon(_explore ? Icons.people_outline : Icons.explore_outlined),
            onPressed: _toggleScope,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: _posts.isEmpty ? 1 : _posts.length,
                itemBuilder: (context, i) {
                  if (_posts.isEmpty) {
                    if (_error != null) return _message(_error!);
                    return _message(
                      _explore
                          ? 'No posts yet. Be the first to share a photo.'
                          : 'Your feed is empty. Follow people to see their '
                              'photos here, or tap the explore button to see '
                              'everyone.',
                      action: _explore
                          ? null
                          : FilledButton(
                              onPressed: _toggleScope,
                              child: const Text('Explore')),
                    );
                  }
                  final p = _posts[i];
                  return PostCard(
                    key: ValueKey(p['id']),
                    post: p,
                    onDeleted: _load,
                  );
                },
              ),
            ),
    );
  }
}
