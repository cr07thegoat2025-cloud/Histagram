import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../util.dart';
import 'chat_helpers.dart';

/// Pick someone by username to start a new conversation.
class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  bool _searching = false;
  bool _searched = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  Future<void> _search(String q) async {
    final clean = q.trim().toLowerCase().replaceAll(RegExp(r'[%,()*@]'), '');
    if (clean.isEmpty) {
      if (mounted) {
        setState(() {
          _results = [];
          _searched = false;
        });
      }
      return;
    }
    setState(() => _searching = true);
    try {
      final me = db.auth.currentUser!.id;
      final rows = await db
          .from('hg_profiles')
          .select('id,username,display_name,avatar_path')
          .ilike('username', '%$clean%')
          .neq('id', me)
          .limit(25);
      if (!mounted ||
          _controller.text.trim().toLowerCase() != q.trim().toLowerCase()) {
        return;
      }
      setState(() {
        _results = (rows as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _searching = false;
        _searched = true;
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
          autofocus: true,
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
      body: _results.isEmpty
          ? Center(
              child: Text(_searching
                  ? 'Searching...'
                  : _searched
                      ? 'No people found.'
                      : 'Type a username to start a conversation.'))
          : ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, i) {
                final r = _results[i];
                final username = r['username'] as String;
                final display = (r['display_name'] as String?) ?? '';
                return ListTile(
                  leading: Avatar(
                      path: r['avatar_path'] as String?,
                      name: username,
                      radius: 22),
                  title: Text(username,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: display.isEmpty ? null : Text(display),
                  onTap: () => openChatWith(
                    context,
                    userId: r['id'] as String,
                    name: username,
                    avatarPath: r['avatar_path'] as String?,
                  ),
                );
              },
            ),
    );
  }
}
