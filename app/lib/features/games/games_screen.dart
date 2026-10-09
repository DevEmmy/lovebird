import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/widgets.dart';
import '../../data/providers.dart';
import '../../state/session.dart';
import '../arcade/arcade.dart';
import 'game_engine.dart';

class GamesScreen extends ConsumerStatefulWidget {
  const GamesScreen({super.key});
  @override
  ConsumerState<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends ConsumerState<GamesScreen> {
  bool _starting = false;
  bool _autoStarted = false;

  Future<void> _start(GameDef g) async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      final id = await GameEngine.start(
        circleId: ref.read(circleIdProvider),
        game: g,
        partnerId: ref.read(partnerProvider).valueOrNull?.id,
      );
      ref.invalidate(gameHistoryProvider);
      if (mounted) context.push('/game/$id');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _startArcade(ArcadeGame g) async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      final id = await ArcadeRepo.start(
        circleId: ref.read(circleIdProvider),
        game: g,
        partnerId: ref.read(partnerProvider).valueOrNull?.id,
      );
      ref.invalidate(gameHistoryProvider);
      if (mounted) context.push('/game/$id');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = GoRouterState.of(context).uri.queryParameters['key'];
    if (key != null && !_autoStarted) {
      _autoStarted = true;
      final g = GameCatalog.byKey(key);
      final a = ArcadeCatalog.byKey(key);
      if (g != null) WidgetsBinding.instance.addPostFrameCallback((_) => _start(g));
      if (a != null) WidgetsBinding.instance.addPostFrameCallback((_) => _startArcade(a));
    }
    final history = ref.watch(gameHistoryProvider).valueOrNull ?? const [];
    final active = history.where((s) => s.active).toList();
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Play together')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Constrained(
            maxWidth: 900,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (active.isNotEmpty) ...[
                const SectionHeader('Pick up where you left off'),
                for (final s in active.take(4))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: LBCard(
                      onTap: () => context.push('/game/${s.id}'),
                      child: Row(children: [
                        Text(GameCatalog.byKey(s.gameKey)?.emoji ?? ArcadeCatalog.byKey(s.gameKey)?.emoji ?? '🎮', style: const TextStyle(fontSize: 26)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(GameCatalog.byKey(s.gameKey)?.title ?? ArcadeCatalog.byKey(s.gameKey)?.title ?? 'Game', style: t.titleSmall),
                            Text(ArcadeCatalog.byKey(s.gameKey) != null ? 'Arcade · ${Fmt.relative(s.updatedAt)}' : 'Round ${s.round} of ${s.totalRounds} · ${Fmt.relative(s.createdAt)}', style: t.bodySmall),
                          ]),
                        ),
                        const Text('Resume'),
                        const Icon(Icons.chevron_right_rounded),
                      ]),
                    ),
                  ),
              ],
              const SectionHeader('Arcade — play live together'),
              ArcadeGrid(onStart: _startArcade, busy: _starting),
              const SectionHeader('Question games'),
              LayoutBuilder(builder: (context, c) {
                final cols = c.maxWidth > 700 ? 3 : 2;
                return GridView.count(
                  crossAxisCount: cols,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.95,
                  children: [
                    for (final g in GameCatalog.all)
                      Semantics(
                        button: true,
                        label: '${g.title}. ${g.tagline}',
                        child: Material(
                          color: g.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(22),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(22),
                            onTap: _starting ? null : () => _start(g),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(color: g.color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
                                  child: Text(g.emoji, style: const TextStyle(fontSize: 26)),
                                ),
                                const Spacer(),
                                Text(g.title, style: t.titleMedium),
                                const SizedBox(height: 2),
                                Text(g.tagline, style: t.bodySmall, maxLines: 2),
                              ]),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              }),
            ]),
          ),
        ],
      ),
    );
  }
}
