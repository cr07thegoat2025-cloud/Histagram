import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import '../util.dart';

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> profile;
  const EditProfileScreen({super.key, required this.profile});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final _name =
      TextEditingController(text: widget.profile['display_name'] as String? ?? '');
  late final _username =
      TextEditingController(text: widget.profile['username'] as String? ?? '');
  late final _bio =
      TextEditingController(text: widget.profile['bio'] as String? ?? '');
  final _picker = ImagePicker();
  XFile? _newAvatar;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    try {
      final f = await _picker.pickImage(
          source: ImageSource.gallery, imageQuality: 85, maxWidth: 600);
      if (f != null && mounted) setState(() => _newAvatar = f);
    } catch (_) {
      if (mounted) showSnack(context, 'Could not open your gallery.');
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _busy) return;
    setState(() => _busy = true);
    final me = db.auth.currentUser!.id;
    try {
      final update = <String, dynamic>{
        'display_name': _name.text.trim(),
        'username': _username.text.trim().toLowerCase(),
        'bio': _bio.text.trim(),
      };
      final f = _newAvatar;
      if (f != null) {
        final ext = imageExt(f.name);
        final path = '$me/avatar_${DateTime.now().microsecondsSinceEpoch}.$ext';
        await db.storage.from(mediaBucket).upload(
              path,
              File(f.path),
              fileOptions: FileOptions(contentType: imageMime(ext)),
            );
        update['avatar_path'] = path;
      }
      await db.from('hg_profiles').update(update).eq('id', me);
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSnack(
          context,
          e.code == '23505'
              ? 'That username is already taken.'
              : 'Could not save your profile.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSnack(context, 'Could not save your profile. Check your internet.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final username = widget.profile['username'] as String? ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit profile'),
        actions: [
          TextButton(onPressed: _busy ? null : _save, child: const Text('Save')),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_busy) const LinearProgressIndicator(minHeight: 3),
            const SizedBox(height: 8),
            Center(
              child: GestureDetector(
                onTap: _busy ? null : _pickAvatar,
                child: _newAvatar != null
                    ? CircleAvatar(
                        radius: 48,
                        backgroundImage: FileImage(File(_newAvatar!.path)))
                    : Avatar(
                        path: widget.profile['avatar_path'] as String?,
                        name: username,
                        radius: 48),
              ),
            ),
            TextButton(
                onPressed: _busy ? null : _pickAvatar,
                child: const Text('Change photo')),
            const SizedBox(height: 8),
            TextFormField(
              controller: _name,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _username,
              autocorrect: false,
              decoration: const InputDecoration(
                  labelText: 'Username', border: OutlineInputBorder()),
              validator: (v) => RegExp(r'^[a-zA-Z0-9_.]{3,24}$')
                      .hasMatch((v ?? '').trim())
                  ? null
                  : 'Use 3-24 letters, numbers, _ or .',
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _bio,
              maxLength: 150,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                  labelText: 'Bio', border: OutlineInputBorder()),
            ),
          ],
        ),
      ),
    );
  }
}
