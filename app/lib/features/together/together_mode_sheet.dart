import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/theme/colors.dart';
import '../../data/together_repo.dart';
import '../../state/session.dart';
import '../dates/date_night_guides.dart';
import '../games/game_engine.dart';

/// "What should we do together?" (brief §10)
Future<void> showTogetherMode(BuildContext context, WidgetRef ref) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => const _TogetherModeSheet(),
  );
  if (choice == null || !context.mounted) return;
  await startTogetherActivity(context, ref, choice);
}

Future<void> startTogetherActivity(BuildContext context, WidgetRef ref, String activity) async {
  final circleId = ref.read(circleIdProvider);
  final rnd = Random();
  var chosen = activity;
  if (activity == 'surprise') {
    chosen = ['play', 'talk', 'date', 'create', 'read'][rnd.nextInt(5)];
  }
  try {
    switch (chosen) {
      case 'play':
        if (activity == 'surprise') {
          final game = GameCatalog.all[rnd.nextInt(GameCatalog.all.length)];
          final sessionId = await GameEngine.start(circleId: circleId, game: game, partnerId: ref.read(partnerProvider).valueOrNull?.id);
          if (context.mounted) context.push('/game/$sessionId');
        } else {
          await TogetherRepo.start(circleId: circleId, activity: 'play', title: 'Pick a game together');
          if (context.mounted) context.push('/games');
        }
      case 'watch':
        await TogetherRepo.start(circleId: circleId, activity: 'watch', title: 'Movie Night');
        if (context.mounted) context.push('/movie');
      case 'read':
        await TogetherRepo.start(circleId: circleId, activity: 'read', title: 'Read together');
        if (context.mounted) context.push('/library');
      case 'talk':
        await TogetherRepo.start(circleId: circleId, activity: 'talk', title: 'Let\'s talk');
        if (context.mounted) context.push('/talk');
      case 'create':
        await TogetherRepo.start(circleId: circleId, activity: 'create', title: 'Create something together');
        if (context.mounted) context.push('/create');
      case 'date':
        if (activity == 'surprise') {
          final g = DateNightGuides.all[rnd.nextInt(DateNightGuides.all.length)];
          await TogetherRepo.start(circleId: circleId, activity: 'date', refType: 'date', title: '${g.key}|${g.title}');
          if (context.mounted) context.push('/date-night/${g.key}');
        } else {
          await TogetherRepo.start(circleId: circleId, activity: 'date', title: 'Date Night');
          if (context.mounted) context.push('/date-night');
        }
    }
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

class _TogetherModeSheet extends ConsumerWidget {
  const _TogetherModeSheet();
  static const options = [
    ('play', '🎮', 'Play', 'Games made for two'),
    ('watch', '🎬', 'Watch', 'Synced Movie Night'),
    ('read', '📖', 'Read', 'Same story, same page'),
    ('talk', '💬', 'Talk', 'Questions worth asking'),
    ('date', '❤️', 'Date', 'A guided date night'),
    ('create', '✍️', 'Create', 'Write or make something'),
    ('surprise', '🎲', 'Surprise Me', 'Lovebird picks'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partner = ref.watch(partnerProvider).valueOrNull;
    final channel = ref.watch(circleChannelProvider);
    final online = channel?.isOnline(partner?.id) ?? false;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('What should we do together?', style: t.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(
            online ? '${partner?.displayName ?? 'Your partner'} is here now ✨' : '${partner?.displayName ?? 'Your partner'} will get an invitation to join.',
            style: t.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth > 520 ? 4 : 2;
            return GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.45,
              children: [
                for (final o in options)
                  Material(
                    color: (LBColors.activity[o.$1] ?? LBColors.rose).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => Navigator.pop(context, o.$1),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text(o.$2, style: const TextStyle(fontSize: 26)),
                          const SizedBox(height: 4),
                          Text(o.$3, style: t.titleMedium),
                          Text(o.$4, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ]),
                      ),
                    ),
                  ),
              ],
            );
          }),
        ]),
      ),
    );
  }
}
