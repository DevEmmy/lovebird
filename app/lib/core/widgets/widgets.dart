import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/media_repo.dart';
import '../../data/models.dart';
import '../errors.dart';
import '../theme/colors.dart';
import '../utils/format.dart';

/// Constrains content width on tablets/desktop so text lines stay readable.
class Constrained extends StatelessWidget {
  const Constrained({super.key, required this.child, this.maxWidth = 720});
  final Widget child;
  final double maxWidth;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      );
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label});
  final String? label;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
          if (label != null) ...[
            const SizedBox(height: 14),
            Text(label!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ]),
      );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('🥀', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            Text(friendlyError(error), textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ]),
        ),
      );
}

/// Render an AsyncValue with consistent loading / error states.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.data, this.onRetry, this.loadingLabel});
  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;
  final String? loadingLabel;
  @override
  Widget build(BuildContext context) => value.when(
        data: data,
        loading: () => LoadingView(label: loadingLabel),
        error: (e, _) => ErrorView(error: e, onRetry: onRetry),
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
      );
}

/// Never leave a screen empty (brief §54).
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.emoji, required this.title, this.message, this.action});
  final String emoji;
  final String title;
  final String? message;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 88,
            height: 88,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, shape: BoxShape.circle),
            child: Text(emoji, style: const TextStyle(fontSize: 40)),
          ),
          const SizedBox(height: 20),
          Text(title, style: t.headlineSmall, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(message!, style: t.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ]),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
        child: Row(children: [
          Expanded(child: Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleLarge))),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
        ]),
      );
}

/// Signed-URL image from private storage, cached by path (URLs rotate, paths don't).
class StorageImage extends StatelessWidget {
  const StorageImage(this.path, {super.key, this.bucket = 'circle-media', this.fit = BoxFit.cover, this.width, this.height, this.semanticLabel});
  final String path;
  final String bucket;
  final BoxFit fit;
  final double? width;
  final double? height;
  final String? semanticLabel;
  @override
  Widget build(BuildContext context) {
    final placeholder = Container(width: width, height: height, color: Theme.of(context).colorScheme.surfaceContainer);
    return FutureBuilder<String>(
      future: MediaRepo.instance.signedUrl(path, bucket: bucket),
      initialData: MediaRepo.instance.cachedUrl(path, bucket: bucket),
      builder: (context, snap) {
        if (!snap.hasData) return placeholder;
        return Semantics(
          image: true,
          label: semanticLabel ?? 'Photo',
          child: CachedNetworkImage(
            imageUrl: snap.data!,
            cacheKey: '$bucket/$path',
            fit: fit,
            width: width,
            height: height,
            fadeInDuration: const Duration(milliseconds: 180),
            placeholder: (_, __) => placeholder,
            errorWidget: (_, __, ___) => Container(
              width: width,
              height: height,
              color: Theme.of(context).colorScheme.surfaceContainer,
              child: const Icon(Icons.broken_image_outlined),
            ),
          ),
        );
      },
    );
  }
}

class LBAvatar extends StatelessWidget {
  const LBAvatar({super.key, required this.profile, this.size = 44, this.online, this.ring = false});
  final Profile? profile;
  final double size;
  final bool? online;
  final bool ring;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = profile?.displayName ?? '';
    Widget inner;
    if (profile?.avatarPath != null) {
      inner = ClipOval(child: StorageImage(profile!.avatarPath!, bucket: 'avatars', width: size, height: size, semanticLabel: '$name\'s photo'));
    } else {
      inner = Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LBColors.heroGradient),
        child: Text(Fmt.initials(name), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.38)),
      );
    }
    if (ring) {
      inner = Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.surface, boxShadow: [
          BoxShadow(color: LBColors.rose.withValues(alpha: 0.18), blurRadius: 16, offset: const Offset(0, 6)),
        ]),
        child: inner,
      );
    }
    return Semantics(
      label: online == null ? name : '$name, ${online! ? 'online' : 'offline'}',
      child: Stack(clipBehavior: Clip.none, children: [
        inner,
        if (online != null)
          Positioned(
            right: ring ? 4 : 0,
            bottom: ring ? 4 : 0,
            child: Container(
              width: size * 0.26,
              height: size * 0.26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: online! ? LBColors.mint : scheme.outline,
                border: Border.all(color: scheme.surface, width: 2),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Soft card with optional tap, used everywhere for consistency.
class LBCard extends StatelessWidget {
  const LBCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(16), this.color, this.gradient});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Gradient? gradient;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(20);
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: gradient == null ? (color ?? scheme.surfaceContainerLowest) : null,
          gradient: gradient,
          borderRadius: radius,
          border: gradient == null ? Border.all(color: scheme.outlineVariant) : null,
        ),
        child: InkWell(onTap: onTap, borderRadius: radius, child: Padding(padding: padding, child: child)),
      ),
    );
  }
}

class PillTag extends StatelessWidget {
  const PillTag(this.label, {super.key, this.color, this.icon});
  final String label;
  final Color? color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color ?? scheme.primaryContainer, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: scheme.onPrimaryContainer), const SizedBox(width: 4)],
        Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onPrimaryContainer)),
      ]),
    );
  }
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirm = 'Confirm',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<String?> promptText(BuildContext context, {required String title, String? hint, String? initial, int maxLength = 120, int maxLines = 1}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        maxLength: maxLength,
        maxLines: maxLines,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: maxLines == 1 ? (v) => Navigator.pop(ctx, v.trim()) : null,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
      ],
    ),
  );
}

/// Busy-state wrapper for async buttons.
class AsyncButton extends StatefulWidget {
  const AsyncButton({super.key, required this.onPressed, required this.child, this.outlined = false, this.icon});
  final Future<void> Function()? onPressed;
  final Widget child;
  final bool outlined;
  final IconData? icon;
  @override
  State<AsyncButton> createState() => _AsyncButtonState();
}

class _AsyncButtonState extends State<AsyncButton> {
  bool _busy = false;
  Future<void> _run() async {
    if (_busy || widget.onPressed == null) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = _busy
        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
        : widget.child;
    final onPressed = widget.onPressed == null ? null : _run;
    if (widget.outlined) {
      return widget.icon == null
          ? OutlinedButton(onPressed: onPressed, child: child)
          : OutlinedButton.icon(onPressed: onPressed, icon: Icon(widget.icon), label: child);
    }
    return widget.icon == null
        ? FilledButton(onPressed: onPressed, child: child)
        : FilledButton.icon(onPressed: onPressed, icon: Icon(widget.icon), label: child);
  }
}
