import 'package:flutter/material.dart';

import '../main.dart';
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
  int _page = 0; // 0 feed, 1 search, 2 profile
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
          ProfileScreen(key: ValueKey('me$_version'), userId: me, isTab: true),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _page == 2 ? 3 : _page,
        onDestinationSelected: (i) {
          if (i == 2) {
            _newPost();
          } else {
            setState(() => _page = i == 3 ? 2 : i);
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
              label: 'New post'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile'),
        ],
      ),
    );
  }
}
