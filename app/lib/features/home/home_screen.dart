import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/together_repo.dart';
import '../../state/session.dart';
import '../competition/competition_repo.dart';
import '../shell/app_shell.dart';
import '../together/together_mode_sheet.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final circle = ref.watch(circleProvider).valueOrNull;
    final me = ref.watch(myProfileProvider).valueOrNull;
    final partner = ref.watch(partnerProvider).valueOrNull;
    final unread = ref.watch(unreadNotificationsProvider);
    if (circle == null) return const Scaffold(body: LoadingView());

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(specialDatesProvider);
          ref.invalidate(shelfProvider);
          ref.invalidate(partnerProvider);
          ref.invalidate(announcementsProvider);
        },
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(child: _CoupleHeader(circle: circle, me: me, partner: partner, unread: unread)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverToBoxAdapter(
              child: Constrained(
                maxWidth: 860,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: const [
                  _WinnerBadge(),
                  _Announcements(),
                  _AnniversaryCard(),
                  _LiveActivityCard(),
                  SectionHeader('What should you two do?'),
                  _QuickActions(),
                  _UpcomingSection(),
                  _ReadingSection(),
                  _RecentMemories(),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _CoupleHeader extends ConsumerWidget {
  const _CoupleHeader({required this.circle, required this.me, required this.partner, required this.unread});
  final Circle circle;
  final Profile? me;
  final Profile? partner;
  final int unread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final channel = ref.watch(circleChannelProvider);
    final days = circle.daysTogether;
    final names = circle.coupleName ?? '${me?.displayName ?? 'You'} & ${partner?.displayName ?? '…'}';
    return Container(
      decoration: const BoxDecoration(
        gradient: LBColors.heroGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 8, 12, 28),
      child: Column(children: [
        Row(children: [
          const Text('Lovebird', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
          const Spacer(),
          IconButton(
            tooltip: unread > 0 ? '$unread unread notifications' : 'Notifications',
            color: Colors.white,
            onPressed: () => context.push('/notifications'),
            icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.notifications_none_rounded)),
          ),
        ]),
        const SizedBox(height: 8),
        Semantics(
          label: '$names. ${partner == null ? '' : (channel?.isOnline(partner!.id) ?? false) ? '${partner!.displayName} is online.' : ''}',
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            LBAvatar(profile: me, size: 76, ring: true),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Icon(Icons.favorite_rounded, color: Colors.white, size: 30),
            ),
            if (channel == null)
              LBAvatar(profile: partner, size: 76, ring: true)
            else
              ValueListenableBuilder<Map<String, Map<String, dynamic>>>(
                valueListenable: channel.online,
                builder: (_, __, ___) => LBAvatar(profile: partner, size: 76, ring: true, online: channel.isOnline(partner?.id)),
              ),
          ]),
        ),
        const SizedBox(height: 14),
        Text(names, style: t.headlineMedium?.copyWith(color: Colors.white), textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(
          days <= 0
              ? 'Your story starts today ❤️'
              : circle.relationshipStart != null
                  ? 'Together for $days ${days == 1 ? 'day' : 'days'}'
                  : '$days ${days == 1 ? 'day' : 'days'} in your Love Circle',
          style: t.bodyLarge?.copyWith(color: Colors.white),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: LBColors.roseDeep),
          onPressed: () => showTogetherMode(context, ref),
          icon: const Icon(Icons.favorite_rounded),
          label: const Text('Together Mode'),
        ),
      ]),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();
  static const _actions = [
    ('❤️', 'Chat', '/chat', true),
    ('🎬', 'Movie Night', '/movie', false),
    ('🎮', 'Play', '/games', false),
    ('📖', 'Read Together', '/library', false),
    ('📔', 'Our Diary', '/memories?tab=diary', true),
    ('📸', 'Memories', '/memories', true),
    ('💡', 'Date Ideas', '/date-ideas', false),
    ('📝', 'Our Plans', '/plans', false),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 600 ? 8 : 4;
      return GridView.count(
        crossAxisCount: cols,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.82,
        children: [
          for (final a in _actions)
            LBCard(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              onTap: () => a.$4 ? context.go(a.$3) : context.push(a.$3),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(a.$1, style: const TextStyle(fontSize: 26)),
                const SizedBox(height: 6),
                Text(a.$2, textAlign: TextAlign.center, maxLines: 2, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface)),
              ]),
            ),
        ],
      );
    });
  }
}

class _LiveActivityCard extends ConsumerWidget {
  const _LiveActivityCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(liveTogetherProvider).valueOrNull;
    if (s == null) return const SizedBox.shrink();
    final uid = ref.watch(userIdProvider);
    final nameOf = ref.watch(nameOfProvider);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: LBCard(
        color: Theme.of(context).colorScheme.primaryContainer,
        onTap: () => context.push(TogetherRepo.routeFor(s)),
        child: Row(children: [
          Text(s.emoji, style: const TextStyle(fontSize: 30)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Happening now', style: Theme.of(context).textTheme.labelMedium),
              Text(s.title?.split('|').last ?? 'Together Mode', style: Theme.of(context).textTheme.titleMedium),
              Text(s.startedBy == uid ? 'You started this' : '${nameOf(s.startedBy)} started this', style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded),
        ]),
      ),
    );
  }
}

class _AnniversaryCard extends ConsumerWidget {
  const _AnniversaryCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dates = ref.watch(specialDatesProvider).valueOrNull ?? const [];
    SpecialDate? anniv;
    for (final d in dates) {
      if (d.kind == 'anniversary' && d.daysUntil <= 14) {
        anniv = d;
        break;
      }
    }
    if (anniv == null) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    final years = anniv.upcomingYears;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: LBCard(
        gradient: const LinearGradient(colors: [Color(0xFF8E0E43), Color(0xFFC2185B)]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('🎉 ${Fmt.countdown(anniv.daysUntil, years > 0 ? 'your ${_ordinal(years)} anniversary' : anniv.title)}',
              style: t.titleLarge?.copyWith(color: Colors.white)),
          const SizedBox(height: 6),
          Text('Make it special — Lovebird put a few things together for you two.', style: t.bodyMedium?.copyWith(color: Colors.white)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final a in const [
              ('Our year recap', '/recap'),
              ('Anniversary questions', '/games?key=deep_questions'),
              ('Date ideas', '/date-ideas?mood=romantic'),
              ('Write a love letter', '/diary/new?prompt=anniversary'),
            ])
              ActionChip(
                label: Text(a.$1),
                onPressed: () => context.push(a.$2),
                backgroundColor: Colors.white,
                labelStyle: const TextStyle(color: LBColors.roseDeep, fontWeight: FontWeight.w600),
              ),
          ]),
        ]),
      ),
    );
  }

  static String _ordinal(int n) {
    if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
    return switch (n % 10) { 1 => '${n}st', 2 => '${n}nd', 3 => '${n}rd', _ => '${n}th' };
  }
}

class _UpcomingSection extends ConsumerWidget {
  const _UpcomingSection();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dates = (ref.watch(specialDatesProvider).valueOrNull ?? const []).where((d) => d.daysUntil >= 0 && d.daysUntil <= 60).take(3).toList();
    final items = ref.watch(upcomingPlanItemsProvider).take(3).toList();
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader('Coming up', action: 'Dates', onAction: () => context.push('/special-dates')),
      if (dates.isEmpty && items.isEmpty)
        LBCard(
          onTap: () => context.push('/special-dates'),
          child: Row(children: [
            const Text('🗓️', style: TextStyle(fontSize: 26)),
            const SizedBox(width: 12),
            Expanded(child: Text('What should you two do next? Add your anniversary, birthdays or your next date.', style: t.bodyMedium)),
          ]),
        ),
      for (final d in dates)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: LBCard(
            onTap: () => context.push('/special-dates'),
            child: Row(children: [
              _DayBubble(days: d.daysUntil),
              const SizedBox(width: 14),
              Expanded(child: Text(Fmt.countdown(d.daysUntil, d.title), style: t.titleSmall)),
            ]),
          ),
        ),
      for (final i in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: LBCard(
            onTap: () => context.push('/plans/${i.planId}'),
            child: Row(children: [
              const Icon(Icons.event_note_rounded, color: LBColors.rose),
              const SizedBox(width: 14),
              Expanded(child: Text(i.text, style: t.titleSmall)),
              Text(Fmt.dayShort(i.dueAt!), style: t.bodySmall),
            ]),
          ),
        ),
    ]);
  }
}

class _DayBubble extends StatelessWidget {
  const _DayBubble({required this.days});
  final int days;
  @override
  Widget build(BuildContext context) => Container(
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(16)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(days == 0 ? '🎉' : '$days', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Theme.of(context).colorScheme.onPrimaryContainer)),
          if (days > 0) Text(days == 1 ? 'day' : 'days', style: Theme.of(context).textTheme.labelMedium),
        ]),
      );
}

class _ReadingSection extends ConsumerWidget {
  const _ReadingSection();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shelf = ref.watch(shelfProvider).valueOrNull ?? const [];
    CircleBook? current;
    for (final b in shelf) {
      if (b.status == 'reading') {
        current = b;
        break;
      }
    }
    if (current == null || current.book == null) return const SizedBox.shrink();
    final cb = current;
    final progress = ref.watch(progressProvider(cb.id)).valueOrNull ?? const [];
    final total = cb.book!.chapterCount ?? 1;
    final uid = ref.watch(userIdProvider);
    final mine = progress.where((p) => p.userId == uid).firstOrNull;
    final pct = mine == null ? 0 : ((mine.chaptersDone.length / total) * 100).round();
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionHeader('Our current book'),
      LBCard(
        onTap: () => context.push('/read/${cb.id}'),
        child: Row(children: [
          Container(
            width: 54,
            height: 76,
            decoration: BoxDecoration(color: _hex(cb.book!.coverColor), borderRadius: BorderRadius.circular(8)),
            alignment: Alignment.center,
            child: const Text('📖', style: TextStyle(fontSize: 24)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(cb.book!.title, style: t.titleMedium),
              const SizedBox(height: 2),
              Text('Chapter ${mine?.chapter ?? 1} of $total · $pct% complete ❤️', style: t.bodySmall),
              const SizedBox(height: 8),
              ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: pct / 100, minHeight: 6)),
              if (cb.nextSessionAt != null) ...[
                const SizedBox(height: 6),
                Text('Next reading session: ${Fmt.weekdayTime(cb.nextSessionAt!)}', style: t.bodySmall),
              ],
            ]),
          ),
        ]),
      ),
    ]);
  }
}

Color _hex(String hex) => Color(int.parse('FF${hex.substring(1)}', radix: 16));

class _RecentMemories extends ConsumerWidget {
  const _RecentMemories();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memories = (ref.watch(memoriesProvider).valueOrNull ?? const []).take(8).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader('Recent memories', action: memories.isEmpty ? null : 'See all', onAction: () => context.go('/memories')),
      if (memories.isEmpty)
        LBCard(
          onTap: () => context.push('/memory/new'),
          child: Row(children: [
            const Text('📸', style: TextStyle(fontSize: 26)),
            const SizedBox(width: 12),
            Expanded(child: Text('Your story starts here ❤️ Save your first memory.', style: Theme.of(context).textTheme.bodyMedium)),
            const Icon(Icons.add_rounded),
          ]),
        )
      else
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: memories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final m = memories[i];
              return Semantics(
                button: true,
                label: 'Memory: ${m.title}',
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => context.push('/memory/${m.id}'),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(
                      width: 130,
                      child: Stack(fit: StackFit.expand, children: [
                        if (m.photoPaths.isNotEmpty)
                          StorageImage(m.photoPaths.first)
                        else
                          Container(decoration: const BoxDecoration(gradient: LBColors.heroGradient)),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xAA000000)]),
                          ),
                        ),
                        Positioned(
                          left: 10,
                          right: 10,
                          bottom: 10,
                          child: Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        ),
                      ]),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
    ]);
  }
}

class _Announcements extends ConsumerWidget {
  const _Announcements();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(announcementsProvider).valueOrNull ?? const [];
    if (list.isEmpty) return const SizedBox.shrink();
    final a = list.first;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: LBCard(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('📣', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(a.body, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _WinnerBadge extends ConsumerWidget {
  const _WinnerBadge();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(myEntryProvider).valueOrNull;
    if (entry == null || !(entry.status == 'winner' || entry.status == 'finalist')) return const SizedBox.shrink();
    final winner = entry.status == 'winner';
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: LBCard(
        gradient: const LinearGradient(colors: [Color(0xFFE8B04B), Color(0xFFF3D27A)]),
        onTap: () => context.push('/competition'),
        child: Row(children: [
          const Text('🏆', style: TextStyle(fontSize: 30)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              winner ? 'Lovebird Couple of the Year' : 'Couple of the Year Finalist',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: const Color(0xFF3B2A06)),
            ),
          ),
        ]),
      ),
    );
  }
}
