import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/config.dart';
import '../../core/errors.dart';
import '../../core/supabase.dart';
import '../../core/theme/colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/widgets.dart';
import '../../data/circle_repo.dart';
import '../../data/models.dart';
import '../../state/session.dart';
import '../shell/splash_screen.dart';

/// Create or join a Love Circle; or wait for your partner to accept.
class CircleSetupScreen extends ConsumerWidget {
  const CircleSetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final circle = ref.watch(circleProvider).valueOrNull;
    final profile = ref.watch(myProfileProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(tooltip: 'Profile', onPressed: () => context.push('/profile'), icon: const Icon(Icons.person_outline)),
          TextButton(onPressed: () => sb.auth.signOut(), child: const Text('Sign out')),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Constrained(
            maxWidth: 480,
            child: circle != null && circle.isPending
                ? _WaitingForPartner(circle: circle)
                : _ChooseOrJoin(name: profile?.displayName),
          ),
        ),
      ),
    );
  }
}

class _ChooseOrJoin extends StatefulWidget {
  const _ChooseOrJoin({this.name});
  final String? name;
  @override
  State<_ChooseOrJoin> createState() => _ChooseOrJoinState();
}

class _ChooseOrJoinState extends State<_ChooseOrJoin> {
  final _code = TextEditingController();
  String? _inviter;
  bool _busy = false;
  late Future<List<Circle>> _past = CircleRepo.pastCircles();

  String get _normalized => _code.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      await CircleRepo.createCircle();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _preview() async {
    if (_normalized.length != 8) return showToast(context, 'Invitation codes have 8 characters.');
    setState(() => _busy = true);
    try {
      final name = await CircleRepo.preview(_normalized);
      if (!mounted) return;
      if (name == null) {
        showToast(context, 'This invitation is invalid or has expired. Ask your partner for a new code.');
      } else {
        setState(() => _inviter = name);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    setState(() => _busy = true);
    try {
      final id = await CircleRepo.join(_normalized);
      if (id == null && mounted) {
        setState(() => _inviter = null);
        showToast(context, 'This invitation is invalid or has expired. Ask your partner for a new code.');
      }
      // Success: router redirects to /home when the circle becomes active.
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Center(child: LovebirdMark(size: 64)),
      const SizedBox(height: 16),
      Text(widget.name == null ? 'Welcome to Lovebird' : 'Hi ${widget.name} 👋', style: t.headlineMedium, textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Text(
        'A Love Circle is your private world for two. Create one and invite your person, or join theirs.',
        style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 28),
      LBCard(
        gradient: LBColors.heroGradient,
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Start our Love Circle', style: t.titleLarge?.copyWith(color: Colors.white)),
          const SizedBox(height: 6),
          Text('You\'ll get a private code to send to your partner.', style: t.bodyMedium?.copyWith(color: Colors.white)),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: LBColors.roseDeep),
            onPressed: _busy ? null : _create,
            child: const Text('Create Love Circle'),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      LBCard(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Join with a code', style: t.titleLarge),
          const SizedBox(height: 6),
          Text('Your partner shared an 8-character code with you.', style: t.bodyMedium),
          const SizedBox(height: 14),
          TextField(
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            maxLength: 9,
            onChanged: (_) => setState(() => _inviter = null),
            onSubmitted: (_) => _preview(),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 -]'))],
            style: t.titleLarge?.copyWith(letterSpacing: 4),
            decoration: const InputDecoration(hintText: 'ABCD2345', counterText: ''),
          ),
          const SizedBox(height: 12),
          if (_inviter == null)
            OutlinedButton(onPressed: _busy ? null : _preview, child: const Text('Find invitation'))
          else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(14)),
              child: Text('💌 $_inviter invited you to their Love Circle.', style: t.bodyLarge),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _busy ? null : _join, child: Text('Join $_inviter')),
          ],
        ]),
      ),
      FutureBuilder<List<Circle>>(
        future: _past,
        builder: (context, snap) {
          final past = snap.data ?? const [];
          if (past.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final c in past) _PastCircleCard(circle: c, onChanged: () => setState(() => _past = CircleRepo.pastCircles())),
            ]),
          );
        },
      ),
    ]);
  }
}

class _PastCircleCard extends StatelessWidget {
  const _PastCircleCard({required this.circle, required this.onChanged});
  final Circle circle;
  final VoidCallback onChanged;

  Future<void> _export(BuildContext context) async {
    final json = await CircleRepo.exportCircle(circle.id);
    await Share.shareXFiles(
      [XFile.fromData(Uint8List.fromList(utf8.encode(json)), mimeType: 'application/json', name: 'lovebird-export.json')],
      subject: 'Our Lovebird memories',
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return LBCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(circle.coupleName ?? 'Your previous Love Circle', style: t.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Ended ${Fmt.day(circle.endedAt!)}. Shared memories stay available until ${Fmt.day(circle.purgeAfter!)} so you can keep what matters to you.',
          style: t.bodySmall,
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          AsyncButton(outlined: true, icon: Icons.download_outlined, onPressed: () => _export(context), child: const Text('Export')),
          AsyncButton(
            outlined: true,
            icon: Icons.delete_outline,
            onPressed: () async {
              final ok = await confirmDialog(
                context,
                title: 'Delete what you wrote?',
                message: 'This removes the messages, diary entries, memories and photos YOU added to this circle. Your former partner\'s own content is theirs and is not affected.',
                confirm: 'Delete mine',
                destructive: true,
              );
              if (!ok) return;
              await CircleRepo.deleteMyContent(circle.id);
              if (context.mounted) showToast(context, 'Your content was deleted.');
              onChanged();
            },
            child: const Text('Delete my content'),
          ),
        ]),
      ]),
    );
  }
}

class _WaitingForPartner extends StatefulWidget {
  const _WaitingForPartner({required this.circle});
  final Circle circle;
  @override
  State<_WaitingForPartner> createState() => _WaitingForPartnerState();
}

class _WaitingForPartnerState extends State<_WaitingForPartner> {
  InviteInfo? _invite;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      var inv = await CircleRepo.activeInvitation(widget.circle.id);
      inv ??= await CircleRepo.regenerate(widget.circle.id);
      if (mounted) setState(() => _invite = inv);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _shareText =>
      'Join me on Lovebird ❤️ — our own private little world.\n\nMy invitation code: ${_invite!.code}\n\n${AppConfig.webOrigin}';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    if (_loading) return const Padding(padding: EdgeInsets.only(top: 120), child: LoadingView());
    final inv = _invite;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 12),
      const _PulsingHeart(),
      const SizedBox(height: 20),
      Text('Waiting for your person…', style: t.headlineMedium, textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Text('Send them this code. The moment they join, your Love Circle opens.',
          style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant), textAlign: TextAlign.center),
      const SizedBox(height: 24),
      if (inv != null)
        LBCard(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Semantics(
              label: 'Invitation code ${inv.code.split('').join(' ')}',
              child: SelectableText(inv.code, style: t.displaySmall?.copyWith(letterSpacing: 6, color: scheme.primary)),
            ),
            const SizedBox(height: 6),
            Text('Expires ${Fmt.weekdayTime(inv.expiresAt)} · single use', style: t.bodySmall),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copy'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: inv.code));
                    if (context.mounted) showToast(context, 'Code copied');
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('Share'),
                  onPressed: () => Share.share(_shareText, subject: 'Join my Lovebird Love Circle'),
                ),
              ),
            ]),
          ]),
        ),
      const SizedBox(height: 16),
      TextButton(
        onPressed: () async {
          final next = await guard(context, () => CircleRepo.regenerate(widget.circle.id));
          if (next != null && mounted) setState(() => _invite = next);
        },
        child: const Text('Get a new code'),
      ),
      TextButton(
        onPressed: () async {
          final ok = await confirmDialog(context, title: 'Cancel this Love Circle?', message: 'The code will stop working. You can create a new one any time.', confirm: 'Cancel circle');
          if (ok && context.mounted) await guard(context, () => CircleRepo.cancelPending(widget.circle.id));
        },
        child: const Text('Cancel'),
      ),
    ]);
  }
}

class _PulsingHeart extends StatefulWidget {
  const _PulsingHeart();
  @override
  State<_PulsingHeart> createState() => _PulsingHeartState();
}

class _PulsingHeartState extends State<_PulsingHeart> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect reduced-motion preferences (§46).
    if (MediaQuery.of(context).disableAnimations) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
        child: ScaleTransition(
          scale: Tween(begin: 0.92, end: 1.06).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
          child: const LovebirdMark(size: 84),
        ),
      );
}
