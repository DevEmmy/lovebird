import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/errors.dart';
import '../../core/supabase.dart';
import '../../core/widgets/widgets.dart';
import '../../data/circle_repo.dart';
import '../../data/models.dart';
import '../../state/session.dart';

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  static const kinds = [
    ('partner_joined', 'Partner joined', 'When your person accepts your invitation'),
    ('together_invite', 'Together invitations', 'Games, Movie Night, reading and dates'),
    ('reading_highlight', 'Reading highlights', 'When your partner highlights a line'),
    ('special_date', 'Special date reminders', 'Anniversaries, birthdays and countdowns'),
    ('competition', 'Couple of the Year', 'Consent requests and announcements'),
    ('circle_ended', 'Love Circle changes', 'Important changes to your circle'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(myProfileProvider).valueOrNull;
    if (p == null) return const Scaffold(body: LoadingView());
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(children: [
        Constrained(
          child: Column(children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Lovebird keeps notifications gentle. Turn off anything you don\'t want — chat messages are always shown as an unread badge.'),
            ),
            for (final k in kinds)
              SwitchListTile(
                value: p.notifies(k.$1),
                title: Text(k.$2),
                subtitle: Text(k.$3),
                onChanged: (v) => guard(context, () => sb.from('profiles').update({
                      'notification_prefs': {...p.notificationPrefs, k.$1: v},
                    }).eq('id', p.id)),
              ),
          ]),
        ),
      ]),
    );
  }
}

class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  Future<void> _update(BuildContext context, Profile p, String key, bool v) =>
      guard(context, () => sb.from('profiles').update({'privacy_prefs': {...p.privacyPrefs, key: v}}).eq('id', p.id));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(myProfileProvider).valueOrNull;
    final circle = ref.watch(circleProvider).valueOrNull;
    final t = Theme.of(context).textTheme;
    if (p == null) return const Scaffold(body: LoadingView());
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & data')),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        Constrained(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: LBCard(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  '🔒 Everything in your Love Circle — messages, diary, photos, memories, games — is locked to you two at the database level. '
                  'Lovebird staff cannot read it. Reports only include what the person reporting chooses to share.',
                  style: t.bodyMedium,
                ),
              ),
            ),
            SwitchListTile(
              value: p.showOnline,
              title: const Text('Show when I\'m online'),
              subtitle: const Text('Your partner sees a green dot and what you\'re doing in Lovebird'),
              onChanged: (v) => _update(context, p, 'show_online', v),
            ),
            SwitchListTile(
              value: p.readReceipts,
              title: const Text('Read receipts'),
              subtitle: const Text('Let your partner see when you\'ve read their messages'),
              onChanged: (v) => _update(context, p, 'read_receipts', v),
            ),
            const Divider(),
            if (circle != null)
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Download our data'),
                subtitle: const Text('A JSON copy of your shared chat, diary, memories and plans'),
                onTap: () => guard(context, () async {
                  final json = await CircleRepo.exportCircle(circle.id);
                  await Share.shareXFiles([XFile.fromData(Uint8List.fromList(utf8.encode(json)), mimeType: 'application/json', name: 'lovebird-export.json')]);
                }),
              ),
            ListTile(
              leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
              title: Text('Delete my account', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              subtitle: const Text('Permanently removes your account. Your Love Circle ends first.'),
              onTap: () => _deleteAccount(context),
            ),
          ]),
        ),
      ]),
    );
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final confirm = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Delete your account?'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(
              'This can\'t be undone.\n\n'
              '• Your account, profile and photo are deleted.\n'
              '• Your Love Circle ends. Your partner keeps read-only access to shared memories for 30 days, then everything is erased.\n'
              '• Download your data first if you want a copy.',
            ),
            const SizedBox(height: 12),
            TextField(controller: confirm, onChanged: (_) => setLocal(() {}), decoration: const InputDecoration(labelText: 'Type DELETE to confirm')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: confirm.text == 'DELETE' ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Delete account'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    await guard(context, () async {
      await sb.functions.invoke('delete-account', body: {'confirm': 'DELETE'});
      await sb.auth.signOut();
    });
  }
}
