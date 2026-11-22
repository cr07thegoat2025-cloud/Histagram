import 'package:flutter/material.dart';

import '../main.dart';
import '../util.dart';
import 'chat_screen.dart';

/// Opens (or creates) the 1:1 chat with another person and shows it.
Future<void> openChatWith(
  BuildContext context, {
  required String userId,
  required String name,
  String? avatarPath,
}) async {
  try {
    final chatId = await db.rpc('tc_start_chat', params: {'p_other': userId});
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
            chatId: chatId as String, otherName: name, otherAvatarPath: avatarPath),
      ),
    );
  } catch (e) {
    if (context.mounted) showSnack(context, 'Could not open the chat: $e');
  }
}
