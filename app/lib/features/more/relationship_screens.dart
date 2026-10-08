import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/errors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/widgets.dart';
import '../../data/circle_repo.dart';
import '../../state/session.dart';

class RelationshipScreen extends ConsumerWidget {
  const RelationshipScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final circle = ref.watch(circleProvider).valueOrNull;
    final partner = ref.watch(partnerProvider).valueOrNull;
    final t = Theme.of(context).textTheme;
    if (circle == null) return const Scaffold(body: LoadingView());
    return Scaffold(
      appBar: AppBar(title: const Text('Relationship settings')),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        Constrained(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ListTile(
              leading: LBAvatar(profile: partner, size: 48),
              title: Text(partner?.displayName ?? 'Your partner', style: t.titleMedium),
              subtitle: Text(partner?.bio ?? 'In your Love Circle since ${Fmt.day(circle.activatedAt ?? circle.createdAt)}'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Couple name'),
              subtitle: Text(circle.coupleName ?? 'Not set — e.g. "Mercy ❤️ David"'),
              onTap: () async {
                final v = await promptText(context, title: 'Couple name', initial: circle.coupleName, maxLength: 60);
                if (v != null && context.mounted) await guard(context, () => CircleRepo.update(circle.id, {'couple_name': v.isEmpty ? null : v}));
              },
            ),
            ListTile(
              leading: const Icon(Icons.favorite_border_rounded),
              title: const Text('When did your relationship start?'),
              subtitle: Text(circle.relationshipStart == null ? 'Used for "together for N days"' : Fmt.day(circle.relationshipStart!)),
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: circle.relationshipStart ?? DateTime.now(), firstDate: DateTime(1950), lastDate: DateTime.now());
                if (d != null && context.mounted) {
                  await guard(context, () => CircleRepo.update(circle.id, {'relationship_start': DateFormat('yyyy-MM-dd').format(d)}));
                }
              },
            ),
            ListTile(leading: const Icon(Icons.notifications_none), title: const Text('Notifications'), onTap: () => context.push('/settings/notifications')),
            ListTile(leading: const Icon(Icons.lock_outline), title: const Text('Privacy'), onTap: () => context.push('/settings/privacy')),
            const Divider(),
            ListTile(
              leading: Icon(Icons.heart_broken_outlined, color: Theme.of(context).colorScheme.error),
              title: Text('End relationship', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              subtitle: const Text('Leave this Love Circle. Your account stays.'),
              onTap: () => context.push('/relationship/end'),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Clear, calm, non-manipulative (brief §40). Explains consequences, requires
/// deliberate confirmation, keeps account separate from circle.
class EndRelationshipScreen extends ConsumerStatefulWidget {
  const EndRelationshipScreen({super.key});
  @override
  ConsumerState<EndRelationshipScreen> createState() => _EndRelationshipScreenState();
}

class _EndRelationshipScreenState extends ConsumerState<EndRelationshipScreen> {
  final _confirm = TextEditingController();
  bool _understand = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final circle = ref.watch(circleProvider).valueOrNull;
    final partner = ref.watch(partnerProvider).valueOrNull;
    final t = Theme.of(context).textTheme;
    final partnerName = partner?.displayName ?? '';
    final matches = _confirm.text.trim().toLowerCase() == partnerName.trim().toLowerCase() && partnerName.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('End relationship')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Constrained(
          maxWidth: 600,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('What happens if you end your Love Circle', style: t.headlineSmall),
            const SizedBox(height: 16),
            for (final line in [
              ('🔒', 'Your shared space becomes read-only for both of you. No new messages, games or entries.'),
              ('🗓️', 'You both keep access to shared chat, diary and memories for 30 days, so each of you can download what you want to keep.'),
              ('🧹', 'During those 30 days you can delete anything you wrote. You can\'t delete what $partnerName wrote — that\'s theirs too.'),
              ('🗑️', 'After 30 days, everything shared in this circle is permanently erased.'),
              ('👤', 'Your Lovebird account is NOT deleted. You can create or join a new Love Circle any time.'),
              ('✉️', '$partnerName will get a short, neutral notice that the circle has ended.'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(line.$1, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(line.$2, style: t.bodyLarge)),
                ]),
              ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _understand,
              onChanged: (v) => setState(() => _understand = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('I understand what will happen'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _confirm,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: 'Type "$partnerName" to confirm'),
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: !_understand || !matches || _busy || circle == null
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      try {
                        await CircleRepo.endCircle(circle.id);
                        // Router redirects to setup once membership changes.
                      } catch (e) {
                        if (context.mounted) showError(context, e);
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              child: const Text('End our Love Circle'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: () => context.pop(), child: const Text('Go back')),
            const SizedBox(height: 20),
            Text(
              'If you\'re ending things because you feel unsafe, you can also report a problem from the More menu, and consider reaching out to someone you trust or a local support service.',
              style: t.bodySmall,
            ),
          ]),
        ),
      ]),
    );
  }
}
