import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../util.dart';
import 'chat_screen.dart';
import 'new_chat_screen.dart';

/// The list of conversations (Histagram's direct messages).
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final me = db.auth.currentUser!;
    // Row Level Security means this only ever returns chats you belong to.
    final stream = db
        .from('tc_chats')
        .stream(primaryKey: ['id']).order('last_time', ascending: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New message',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NewChatScreen()),
        ),
        child: const Icon(Icons.edit_outlined),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          // Hide chats nobody has written in yet.
          final chats =
              snap.data!.where((c) => c['last_message'] != null).toList();
          if (chats.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                    'No messages yet.\nTap the button to message someone, '
                    'or open a profile and tap Message.',
                    textAlign: TextAlign.center),
              ),
            );
          }
          return ListView.separated(
            itemCount: chats.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final c = chats[i];
              final otherId = c['user_a'] == me.id ? c['user_b'] : c['user_a'];
              return _InboxTile(
                key: ValueKey(c['id']),
                chatId: c['id'] as String,
                otherId: otherId as String,
                lastMessage: c['last_message'] as String? ?? '',
                lastTime: c['last_time'] == null
                    ? null
                    : DateTime.parse(c['last_time'] as String).toLocal(),
              );
            },
          );
        },
      ),
    );
  }
}

class _InboxTile extends StatefulWidget {
  final String chatId;
  final String otherId;
  final String lastMessage;
  final DateTime? lastTime;

  const _InboxTile({
    super.key,
    required this.chatId,
    required this.otherId,
    required this.lastMessage,
    required this.lastTime,
  });

  @override
  State<_InboxTile> createState() => _InboxTileState();
}

class _InboxTileState extends State<_InboxTile> {
  String _name = '…';
  String? _avatar;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // Histagram profile first (username + photo)...
      final hg = await db
          .from('hg_profiles')
          .select('username,avatar_path')
          .eq('id', widget.otherId)
          .maybeSingle();
      if (!mounted) return;
      if (hg != null) {
        setState(() {
          _name = hg['username'] as String;
          _avatar = hg['avatar_path'] as String?;
        });
        return;
      }
      // ...otherwise a TextChat-only user: show their name or email.
      final tc = await db
          .from('tc_profiles')
          .select('name,email')
          .eq('id', widget.otherId)
          .maybeSingle();
      if (!mounted) return;
      final name = (tc?['name'] as String?) ?? '';
      setState(() =>
          _name = name.isNotEmpty ? name : (tc?['email'] as String? ?? 'Unknown'));
    } catch (_) {
      if (mounted) setState(() => _name = 'Unknown');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Avatar(path: _avatar, name: _name, radius: 22),
      title: Text(_name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(widget.lastMessage,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: widget.lastTime == null
          ? null
          : Text(DateFormat.jm().format(widget.lastTime!),
              style: Theme.of(context).textTheme.bodySmall),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
              chatId: widget.chatId, otherName: _name, otherAvatarPath: _avatar),
        ),
      ),
    );
  }
}
