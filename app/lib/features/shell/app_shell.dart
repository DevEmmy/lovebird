import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/colors.dart';
import '../../data/models.dart';
import '../../data/together_repo.dart';
import '../../state/session.dart';
import '../chat/chat_repo.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'Chat'),
    (Icons.favorite_border_rounded, Icons.favorite_rounded, 'Together'),
    (Icons.photo_library_outlined, Icons.photo_library_rounded, 'Memories'),
    (Icons.more_horiz_rounded, Icons.more_horiz_rounded, 'More'),
  ];

  void _go(int i) => shell.goBranch(i, initialLocation: i == shell.currentIndex);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the realtime channel alive for the whole signed-in session.
    ref.watch(circleChannelProvider);
    final unread = ref.watch(unreadCountProvider).valueOrNull ?? 0;
    final wide = MediaQuery.sizeOf(context).width >= 840;

    Widget icon(int i, bool selected) {
      final ic = Icon(selected ? _items[i].$2 : _items[i].$1);
      if (i == 1 && unread > 0) return Badge(label: Text(unread > 99 ? '99+' : '$unread'), child: ic);
      return ic;
    }

    final session = ref.watch(liveTogetherProvider).valueOrNull;
    final uid = ref.watch(userIdProvider);
    final showBanner = session != null && session.startedBy != uid && session.status == 'inviting';
    final body = Column(children: [
      if (showBanner) _TogetherInviteBanner(session: session),
      Expanded(
        child: showBanner ? MediaQuery.removePadding(context: context, removeTop: true, child: shell) : shell,
      ),
    ]);

    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: _go,
            labelType: NavigationRailLabelType.all,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Icon(Icons.favorite_rounded, color: LBColors.rose, size: 32, semanticLabel: 'Lovebird'),
            ),
            destinations: [
              for (var i = 0; i < _items.length; i++)
                NavigationRailDestination(icon: icon(i, false), selectedIcon: icon(i, true), label: Text(_items[i].$3)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: _go,
        destinations: [
          for (var i = 0; i < _items.length; i++)
            NavigationDestination(icon: icon(i, false), selectedIcon: icon(i, true), label: _items[i].$3),
        ],
      ),
    );
  }
}

/// "David wants to play 🎮 — Join" — shown anywhere in the app when the partner starts something.
class _TogetherInviteBanner extends ConsumerWidget {
  const _TogetherInviteBanner({required this.session});
  final TogetherSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partner = ref.watch(partnerProvider).valueOrNull;
    final verb = switch (session.activity) {
      'play' => 'wants to play 🎮',
      'watch' => 'started Movie Night 🎬',
      'read' => 'wants to read together 📖',
      'talk' => 'wants to talk 💬',
      'date' => 'planned a date ❤️',
      'create' => 'wants to create something ✍️',
      _ => 'wants to spend time together ❤️',
    };
    return Material(
      color: LBColors.rose,
      child: SafeArea(
        bottom: false,
        child: Semantics(
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(children: [
              const Icon(Icons.favorite, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${partner?.displayName ?? 'Your partner'} $verb${session.title != null && !session.title!.contains('|') ? ' · ${session.title}' : ''}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: () => TogetherRepo.end(session.id),
                child: const Text('Not now'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: LBColors.roseDeep, minimumSize: const Size(64, 40)),
                onPressed: () async {
                  await TogetherRepo.join(session.id);
                  if (context.mounted) context.push(TogetherRepo.routeFor(session));
                },
                child: const Text('Join'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

extension TogetherSessionX on TogetherSession {
  String get emoji => switch (activity) {
        'play' => '🎮',
        'watch' => '🎬',
        'read' => '📖',
        'talk' => '💬',
        'date' => '❤️',
        'create' => '✍️',
        _ => '🎲',
      };
}
