import 'package:flutter/material.dart';

import 'main.dart';

const mediaBucket = 'hg-media';

/// Images are private, so each is shown through a temporary signed link.
/// Links are cached so scrolling doesn't request them again.
class _CachedUrl {
  final Future<String> future;
  final DateTime at = DateTime.now();
  _CachedUrl(this.future);
}

final Map<String, _CachedUrl> _urlCache = {};

Future<String> signedUrl(String path) {
  final hit = _urlCache[path];
  if (hit != null &&
      DateTime.now().difference(hit.at) < const Duration(minutes: 45)) {
    return hit.future;
  }
  final fresh =
      _CachedUrl(db.storage.from(mediaBucket).createSignedUrl(path, 3600));
  _urlCache[path] = fresh;
  fresh.future.then((_) {}, onError: (_) => _urlCache.remove(path));
  return fresh.future;
}

class SignedImage extends StatelessWidget {
  final String path;
  final BoxFit fit;

  const SignedImage({super.key, required this.path, this.fit = BoxFit.cover});

  Widget _fill(BuildContext context, Widget child) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: signedUrl(path),
      builder: (context, snap) {
        if (snap.hasError) {
          return _fill(context,
              const Center(child: Icon(Icons.broken_image_outlined, size: 32)));
        }
        if (!snap.hasData) return _fill(context, const SizedBox.expand());
        return Image.network(
          snap.data!,
          fit: fit,
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : _fill(context, const SizedBox.expand()),
          errorBuilder: (context, _, __) => _fill(context,
              const Center(child: Icon(Icons.broken_image_outlined, size: 32))),
        );
      },
    );
  }
}

class Avatar extends StatelessWidget {
  final String? path;
  final String name;
  final double radius;

  const Avatar({super.key, this.path, required this.name, this.radius = 18});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      child: path == null
          ? Text(initial,
              style: TextStyle(
                  fontSize: radius * 0.9, fontWeight: FontWeight.w700))
          : ClipOval(
              child: SizedBox(
                  width: radius * 2,
                  height: radius * 2,
                  child: SignedImage(path: path!))),
    );
  }
}

class HistagramLogo extends StatelessWidget {
  final double size;
  const HistagramLogo({super.key, this.size = 26});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: brand,
            borderRadius: BorderRadius.circular(size * 0.3),
          ),
          child: Icon(Icons.grid_view_rounded,
              size: size * 0.62, color: Colors.white),
        ),
        SizedBox(width: size * 0.35),
        Text('Histagram',
            style: TextStyle(
                fontSize: size * 0.95,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6)),
      ],
    );
  }
}

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  return '${(d.inDays / 7).floor()}w';
}

int intOf(dynamic v) => (v as num?)?.toInt() ?? 0;

void showSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

const _mimeByExt = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'gif': 'image/gif',
  'heic': 'image/heic',
  'heif': 'image/heif',
};

String imageExt(String fileName) {
  final dot = fileName.lastIndexOf('.');
  var e = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  e = e.replaceAll(RegExp(r'[^a-z0-9]'), '');
  return _mimeByExt.containsKey(e) ? e : 'jpg';
}

String imageMime(String ext) => _mimeByExt[ext] ?? 'image/jpeg';
