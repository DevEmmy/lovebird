import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  String? _route(AppNotification n) {
    final d = n.data;
    switch (n.kind) {
      case 'together_invite':
        return switch (d['ref_type']) {
          'game' => '/game/${d['ref_id']}',
          'movie' => '/movie/${d['ref_id']}',
          'reading' => '/read/${d['ref_id']}',
          _ => '/together',
        };
      case 'reading_highlight':
        return '/read/${d['circle_book_id']}';
      case 'special_date':
        return '/special-dates';
      case 'competition':
        return '/competition';
      case 'partner_joined':
        return '/home';
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: () => sb.from('notifications').update({'read_at': DateTime.now().toUtc().toIso8601String()}).isFilter('read_at', null).eq('user_id', requireUserId()),
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: AsyncView<List<AppNotification>>(
        value: ref.watch(notificationsProvider),
        data: (list) => list.isEmpty
            ? const EmptyState(emoji: '🔔', title: 'All quiet', message: 'We\'ll only nudge you about things that matter.')
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final n = list[i];
                  return ListTile(
                    tileColor: n.unread ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4) : null,
                    title: Text(n.title, style: t.titleSmall),
                    subtitle: Text([if (n.body != null) n.body!, Fmt.relative(n.createdAt)].join('\n')),
                    isThreeLine: n.body != null,
                    onTap: () async {
                      if (n.unread) {
                        await sb.from('notifications').update({'read_at': DateTime.now().toUtc().toIso8601String()}).eq('id', n.id);
                      }
                      final r = _route(n);
                      if (r != null && context.mounted) context.push(r);
                    },
                  );
                },
              ),
      ),
    );
  }
}
