import 'package:flutter/material.dart';

import '../chat/chat_helpers.dart';
import '../main.dart';
import '../util.dart';
import 'edit_profile_screen.dart';
import 'post_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String userId;
  final bool isTab;

  const ProfileScreen({super.key, required this.userId, this.isTab = false});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _posts = [];
  bool _loading = true;
  bool _followBusy = false;
  String? _error;

  String get _me => db.auth.currentUser!.id;
  bool get _mine => widget.userId == _me;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await db
          .from('hg_profiles')
          .select()
          .eq('id', widget.userId)
          .maybeSingle();
      final stats =
          await db.rpc('hg_profile_stats', params: {'p_user': widget.userId});
      final posts = await db
          .from('hg_posts')
          .select('id,image_path')
          .eq('user_id', widget.userId)
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _profile = profile == null ? null : Map<String, dynamic>.from(profile);
        final s = stats as List;
        _stats = s.isEmpty ? {} : Map<String, dynamic>.from(s.first as Map);
        _posts = (posts as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load this profile. Pull down to try again.';
      });
    }
  }

  Future<void> _toggleFollow() async {
    if (_followBusy) return;
    final was = _stats['is_following'] == true;
    setState(() {
      _followBusy = true;
      _stats['is_following'] = !was;
      _stats['follower_count'] = intOf(_stats['follower_count']) + (was ? -1 : 1);
    });
    try {
      if (was) {
        await db
            .from('hg_follows')
            .delete()
            .eq('follower_id', _me)
            .eq('following_id', widget.userId);
      } else {
        await db
            .from('hg_follows')
            .insert({'follower_id': _me, 'following_id': widget.userId});
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _stats['is_following'] = was;
          _stats['follower_count'] =
              intOf(_stats['follower_count']) + (was ? 1 : -1);
        });
        showSnack(context, 'Could not update follow.');
      }
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Future<void> _edit() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => EditProfileScreen(profile: _profile!)),
    );
    if (changed == true) _load();
  }

  Widget _stat(String label, dynamic value) => Column(
        children: [
          Text('${intOf(value)}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Text(label),
        ],
      );

  Widget _header() {
    final p = _profile!;
    final username = p['username'] as String;
    final display = (p['display_name'] as String?) ?? '';
    final bio = (p['bio'] as String?) ?? '';
    final following = _stats['is_following'] == true;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Avatar(
                  path: p['avatar_path'] as String?, name: username, radius: 42),
              const SizedBox(width: 20),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _stat('posts', _stats['post_count']),
                    _stat('followers', _stats['follower_count']),
                    _stat('following', _stats['following_count']),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (display.isNotEmpty)
            Text(display, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (bio.isNotEmpty) Text(bio),
          const SizedBox(height: 12),
          if (_mine)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                  onPressed: _edit, child: const Text('Edit profile')),
            )
          else
            Row(
              children: [
                Expanded(
                  child: following
                      ? OutlinedButton(
                          onPressed: _followBusy ? null : _toggleFollow,
                          child: const Text('Following'))
                      : FilledButton(
                          onPressed: _followBusy ? null : _toggleFollow,
                          child: const Text('Follow')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => openChatWith(
                      context,
                      userId: widget.userId,
                      name: username,
                      avatarPath: p['avatar_path'] as String?,
                    ),
                    child: const Text('Message'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _profile == null ? '' : _profile!['username'] as String;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.isTab,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          if (_mine)
            IconButton(
              tooltip: 'Log out',
              icon: const Icon(Icons.logout),
              onPressed: () => db.auth.signOut(),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _profile == null
              ? ListView(children: [
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(_error ?? 'This profile does not exist.',
                        textAlign: TextAlign.center),
                  ),
                ])
              : RefreshIndicator(
                  onRefresh: _load,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(child: _header()),
                      if (_posts.isEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                                _mine
                                    ? 'You haven\'t posted yet. Tap the + button to share your first photo.'
                                    : 'No posts yet.',
                                textAlign: TextAlign.center),
                          ),
                        )
                      else
                        SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  mainAxisSpacing: 2,
                                  crossAxisSpacing: 2),
                          delegate: SliverChildBuilderDelegate(
                            (context, i) {
                              final post = _posts[i];
                              return GestureDetector(
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => PostScreen(
                                            postId: post['id'] as String)),
                                  );
                                  if (mounted) _load();
                                },
                                child:
                                    SignedImage(path: post['image_path'] as String),
                              );
                            },
                            childCount: _posts.length,
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
