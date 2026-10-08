import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/colors.dart';
import '../../core/widgets/widgets.dart';
import '../../data/together_repo.dart';
import '../../state/session.dart';
import '../shell/app_shell.dart';
import 'together_mode_sheet.dart';

class TogetherScreen extends ConsumerWidget {
  const TogetherScreen({super.key});

  static const _sections = [
    ('play', '🎮', 'Games', 'Truth or Dare, Would You Rather, quizzes and more', '/games'),
    ('watch', '🎬', 'Movie Night', 'Watch in sync with chat on the side', '/movie'),
    ('date', '🍿', 'Date Night', 'Guided dates: cooking, deep talk, study, relax…', '/date-night'),
    ('surprise', '💡', 'Date Ideas', 'Any budget, any distance, any mood', '/date-ideas'),
    ('read', '📚', 'Our Library', 'Read together, highlight, discuss', '/library'),
    ('talk', '💬', 'Conversation Starters', 'Questions worth asking tonight', '/talk'),
    ('create', '✍️', 'Create Together', 'Write, draw and make something', '/create'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final live = ref.watch(liveTogetherProvider).valueOrNull;
    final partner = ref.watch(partnerProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Together')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        Constrained(
          maxWidth: 860,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            LBCard(
              gradient: LBColors.heroGradient,
              padding: const EdgeInsets.all(22),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('❤️ Together Mode', style: t.headlineSmall?.copyWith(color: Colors.white)),
                const SizedBox(height: 6),
                Text(
                  live == null
                      ? 'Spend time with ${partner?.displayName ?? 'your partner'} right now. Pick something and they\'ll get an invite.'
                      : 'You\'re in Together Mode: ${live.title?.split('|').last ?? live.activity}',
                  style: t.bodyMedium?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 16),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: LBColors.roseDeep),
                    onPressed: () => live == null ? showTogetherMode(context, ref) : context.push(TogetherRepo.routeFor(live)),
                    child: Text(live == null ? 'What should we do?' : 'Continue ${live.emoji}'),
                  ),
                  if (live != null)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white)),
                      onPressed: () => TogetherRepo.end(live.id),
                      child: const Text('End session'),
                    ),
                ]),
              ]),
            ),
            const SectionHeader('Things to do'),
            for (final s in _sections)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: LBCard(
                  onTap: () => context.push(s.$5),
                  child: Row(children: [
                    Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: (LBColors.activity[s.$1] ?? LBColors.rose).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(s.$2, style: const TextStyle(fontSize: 26)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s.$3, style: t.titleMedium),
                        const SizedBox(height: 2),
                        Text(s.$4, style: t.bodySmall),
                      ]),
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ]),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}
