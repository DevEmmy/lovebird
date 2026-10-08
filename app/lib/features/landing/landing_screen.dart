import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/colors.dart';
import '../shell/splash_screen.dart';

/// First thing a new visitor sees (web landing + app welcome).
class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  static const _features = [
    ('💬', 'Talk', 'A private chat only you two can ever see — with voice notes, photos and reactions.'),
    ('🎮', 'Play', 'Real two-player games: answers stay hidden until you both reveal.'),
    ('🎬', 'Watch', 'Movie Night with synced play, pause and seek — plus chat on the side.'),
    ('📖', 'Read', 'Read the same story, highlight lines for each other, talk about each chapter.'),
    ('📔', 'Remember', 'Our Diary catches the funny and tender moments before they slip away.'),
    ('💡', 'Plan', 'Date ideas for any budget, distance and mood — and a shared list for what\'s next.'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final wide = MediaQuery.sizeOf(context).width > 820;
    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: Container(
            decoration: const BoxDecoration(gradient: LBColors.heroGradient),
            padding: EdgeInsets.fromLTRB(24, MediaQuery.paddingOf(context).top + 28, 24, 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    LovebirdMark(size: 34, color: Colors.white),
                    SizedBox(width: 10),
                    Text('Lovebird', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                  ]),
                  SizedBox(height: wide ? 72 : 48),
                  Text(
                    'Two people.\nOne private world.',
                    style: (wide ? t.displayLarge : t.displayMedium)?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Text(
                      'A thousand ways to spend time together — even when you\'re apart. Chat, play, watch, read and keep your story, all in one place built only for you two.',
                      style: t.bodyLarge?.copyWith(color: Colors.white, fontSize: 17),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: LBColors.roseDeep),
                      onPressed: () => context.go('/sign-up'),
                      child: const Text('Create our world'),
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white, width: 1.5)),
                      onPressed: () => context.go('/sign-in'),
                      child: const Text('I have an account'),
                    ),
                  ]),
                ]),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 40, 20, 12),
                child: Text('Everything you two do together, in one place', style: t.headlineMedium),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final f in _features)
                      SizedBox(
                        width: wide ? 300 : double.infinity,
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(f.$1, style: const TextStyle(fontSize: 30)),
                              const SizedBox(height: 10),
                              Text(f.$2, style: t.titleMedium),
                              const SizedBox(height: 4),
                              Text(f.$3, style: t.bodyMedium),
                            ]),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 36, 20, 48),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Private by design', style: t.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'A Love Circle holds exactly two people — never a third. Your messages, diary, photos and memories are locked to your circle in the database itself, not just hidden in the app. Not even Lovebird admins can read them. Lovebird is for adults 18+ and is not a dating app: you connect only with the person you invite.',
                    style: t.bodyLarge,
                  ),
                  const SizedBox(height: 28),
                  Center(child: Text('Even when we\'re apart, we\'re still together. ❤️', style: t.titleMedium?.copyWith(color: Theme.of(context).colorScheme.primary))),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
