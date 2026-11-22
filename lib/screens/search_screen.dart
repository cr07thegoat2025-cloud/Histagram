import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../util.dart';
import 'post_screen.dart';
import 'profile_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _explore = [];
  List<Map<String, dynamic>>? _results; // null = not searching
  bool _loadingExplore = true;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _loadExplore();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadExplore() async {
    try {
      final rows = await db
          .rpc('hg_feed', params: {'p_scope': 'explore', 'p_limit': 45});
      if (!mounted) return;
      setState(() {
        _explore = (rows as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loadingExplore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingExplore = false);
    }
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  Future<void> _search(String q) async {
    final clean = q.trim().toLowerCase().replaceAll(RegExp(r'[%,()*@]'), '');
    if (clean.isEmpty) {
      if (mounted) setState(() => _results = null);
      return;
    }
    setState(() => _searching = true);
    try {
      final rows = await db
          .from('hg_profiles')
          .select('id,username,display_name,avatar_path')
          .ilike('username', '%$clean%')
          .limit(25);
      if (!mounted || _controller.text.trim().toLowerCase() != q.trim().toLowerCase()) {
        return;
      }
      setState(() {
        _results = (rows as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _searching = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _searching = false);
        showSnack(context, 'Search failed. Check your internet.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          onChanged: _onChanged,
          autocorrect: false,
          decoration: InputDecoration(
            hintText: 'Search people',
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
            filled: true,
            isDense: true,
          ),
        ),
      ),
      body: _results != null ? _buildResults() : _buildExplore(),
    );
  }

  Widget _buildResults() {
    final results = _results!;
    if (results.isEmpty) {
      return Center(
          child: Text(_searching ? 'Searching...' : 'No people found.'));
    }
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, i) {
        final r = results[i];
        final username = r['username'] as String;
        final display = (r['display_name'] as String?) ?? '';
        return ListTile(
          leading: Avatar(
              path: r['avatar_path'] as String?, name: username, radius: 22),
          title: Text(username,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: display.isEmpty ? null : Text(display),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => ProfileScreen(userId: r['id'] as String)),
          ),
        );
      },
    );
  }

  Widget _buildExplore() {
    if (_loadingExplore) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_explore.isEmpty) {
      return const Center(child: Text('No posts to explore yet.'));
    }
    return RefreshIndicator(
      onRefresh: _loadExplore,
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, mainAxisSpacing: 2, crossAxisSpacing: 2),
        itemCount: _explore.length,
        itemBuilder: (context, i) {
          final p = _explore[i];
          return GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => PostScreen(postId: p['id'] as String)),
            ),
            child: SignedImage(path: p['image_path'] as String),
          );
        },
      ),
    );
  }
}
