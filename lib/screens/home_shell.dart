import 'package:flutter/material.dart';

import '../main.dart';
import '../reels/create_reel_screen.dart';
import '../reels/reels_screen.dart';
import '../util.dart';
import 'create_post_screen.dart';
import 'feed_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _page = 0; // 0 feed, 1 search, 2 reels, 3 profile
  int _version = 0; // bumped after posting so the feed and profile reload
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() => _error = null);
    try {
      // Creates your Histagram profile the first time you open the app.
      await db.rpc('hg_ensure_profile');
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not set up your profile. Check your '
            'internet and try again.');
      }
    }
  }

  Future<void> _create() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Post'),
              subtitle: const Text('Share a photo'),
              onTap: () => Navigator.pop(ctx, 'post'),
            ),
            ListTile(
              leading: const Icon(Icons.movie_creation_outlined),
              title: const Text('Reel'),
              subtitle: const Text('Share a short video'),
              onTap: () => Navigator.pop(ctx, 'reel'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'post') {
      await _newPost();
    } else if (choice == 'reel') {
      await _newReel();
    }
  }

  Future<void> _newReel() async {
    final posted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CreateReelScreen()),
    );
    if (posted == true && mounted) {
      setState(() {
        _version++;
        _page = 2;
      });
      showSnack(context, 'Reel shared');
    }
  }

  Future<void> _newPost() async {
    final posted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CreatePostScreen()),
    );
    if (posted == true && mounted) {
      setState(() {
        _version++;
        _page = 0;
      });
      showSnack(context, 'Posted');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const HistagramLogo(size: 36),
                const SizedBox(height: 20),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: _init, child: const Text('Try again')),
                TextButton(
                    onPressed: () => db.auth.signOut(),
                    child: const Text('Log out')),
              ],
            ),
          ),
        ),
      );
    }
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final me = db.auth.currentUser!.id;
    return Scaffold(
      body: IndexedStack(
        index: _page,
        children: [
          FeedScreen(key: ValueKey('feed$_version')),
          const SearchScreen(),
          ReelsScreen(key: ValueKey('reels$_version'), active: _page == 2),
          ProfileScreen(key: ValueKey('me$_version'), userId: me, isTab: true),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _page < 2 ? _page : _page + 1,
        onDestinationSelected: (i) {
          if (i == 2) {
            _create();
          } else {
            setState(() => _page = i < 2 ? i : i - 1);
          }
        },
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.search), label: 'Search'),
          NavigationDestination(
              icon: Icon(Icons.add_box_outlined),
              selectedIcon: Icon(Icons.add_box),
              label: 'Create'),
          NavigationDestination(
              icon: Icon(Icons.play_circle_outline),
              selectedIcon: Icon(Icons.play_circle),
              label: 'Reels'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile'),
        ],
      ),
    );
  }
}
