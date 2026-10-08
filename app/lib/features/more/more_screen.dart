import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase.dart';
import '../../core/widgets/widgets.dart';
import '../../data/providers.dart';
import '../../state/session.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(myProfileProvider).valueOrNull;
    final isAdmin = ref.watch(isAdminProvider).valueOrNull ?? false;
    final unread = ref.watch(unreadNotificationsProvider);
    final t = Theme.of(context).textTheme;

    Widget tile(IconData icon, String title, String route, {String? subtitle, Widget? trailing}) => ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
          onTap: () => context.push(route),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(padding: const EdgeInsets.fromLTRB(8, 0, 8, 32), children: [
        Constrained(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ListTile(
              leading: LBAvatar(profile: me, size: 52),
              title: Text(me?.displayName ?? '', style: t.titleLarge),
              subtitle: const Text('Edit profile'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/profile'),
            ),
            const Divider(),
            tile(Icons.notifications_none_rounded, 'Notifications', '/notifications',
                trailing: unread > 0 ? Badge(label: Text('$unread')) : null),
            tile(Icons.checklist_rounded, 'Our Plans', '/plans'),
            tile(Icons.event_rounded, 'Special dates', '/special-dates'),
            tile(Icons.auto_awesome_rounded, 'Our Year Together', '/recap'),
            tile(Icons.emoji_events_outlined, 'Couple of the Year', '/competition', subtitle: 'Optional annual celebration'),
            const Divider(),
            tile(Icons.favorite_border_rounded, 'Relationship settings', '/relationship'),
            tile(Icons.tune_rounded, 'Notification settings', '/settings/notifications'),
            tile(Icons.lock_outline_rounded, 'Privacy & data', '/settings/privacy'),
            tile(Icons.flag_outlined, 'Report a problem', '/report'),
            if (isAdmin) ...[
              const Divider(),
              tile(Icons.admin_panel_settings_outlined, 'Admin', '/admin'),
            ],
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Sign out'),
              onTap: () async {
                final ok = await confirmDialog(context, title: 'Sign out?', message: 'Your Love Circle stays exactly as it is.', confirm: 'Sign out');
                if (ok) await sb.auth.signOut();
              },
            ),
            const SizedBox(height: 24),
            Center(child: Text('Lovebird · Two people. One private world. ❤️', style: t.bodySmall)),
          ]),
        ),
      ]),
    );
  }
}
