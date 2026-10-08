import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/supabase.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/widgets.dart';
import '../../data/ai_repo.dart';
import '../../state/session.dart';
import '../games/game_engine.dart';

final _recapProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, int>((ref, year) async {
  final cid = ref.watch(circleIdProvider);
  final res = await sb.rpc('circle_year_recap', params: {'p_circle': cid, 'p_year': year});
  return Map<String, dynamic>.from(res as Map);
});

/// ❤️ Our Year Together (brief §29). Private to the couple.
class RecapScreen extends ConsumerStatefulWidget {
  const RecapScreen({super.key, this.year});
  final int? year;
  @override
  ConsumerState<RecapScreen> createState() => _RecapScreenState();
}

class _RecapScreenState extends ConsumerState<RecapScreen> {
  late int _year = widget.year ?? DateTime.now().year;
  String? _story;
  bool _storyLoading = false;

  Future<void> _aiStory(Map<String, dynamic> stats) async {
    setState(() => _storyLoading = true);
    try {
      final me = ref.read(myProfileProvider).valueOrNull?.displayName ?? '';
      final partner = ref.read(partnerProvider).valueOrNull?.displayName ?? '';
      // Only aggregate counts go to the AI — never messages or diary text.
      final counts = Map.of(stats)..remove('highlights');
      final r = await AiRepo.ask('recap_story', {'stats': counts, 'names': '$me & $partner'});
      setState(() => _story = r['story'] as String?);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _storyLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final circle = ref.watch(circleProvider).valueOrNull;
    final firstYear = (circle?.activatedAt ?? DateTime.now()).year;
    return Scaffold(
      appBar: AppBar(title: const Text('Our Year Together')),
      body: AsyncView<Map<String, dynamic>>(
        value: ref.watch(_recapProvider(_year)),
        onRetry: () => ref.invalidate(_recapProvider(_year)),
        data: (r) {
          int n(String k) => (r[k] as num?)?.toInt() ?? 0;
          final stats = [
            ('❤️', 'date nights', n('date_nights')),
            ('🎮', 'games played', n('games_played')),
            ('🎬', 'movie nights', n('movie_nights')),
            ('📚', 'books finished', n('books_finished')),
            ('📸', 'memories saved', n('memories')),
            ('📔', 'diary entries', n('diary_entries')),
            ('😂', 'funny moments', n('funny_moments')),
            ('💬', 'messages', n('messages')),
            ('✅', 'plans completed', n('plans_completed')),
          ];
          final fav = r['favorite_activity'] as String?;
          final favGame = GameCatalog.byKey(r['favorite_game'] as String? ?? '');
          final highlights = (r['highlights'] as List?) ?? const [];
          return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
            Constrained(
              maxWidth: 720,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(gradient: LBColors.heroGradient, borderRadius: BorderRadius.circular(28)),
                  child: Column(children: [
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      IconButton(
                        tooltip: 'Previous year',
                        color: Colors.white,
                        onPressed: _year > firstYear ? () => setState(() {
                              _year--;
                              _story = null;
                            }) : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Text('Your $_year Together', style: t.headlineMedium?.copyWith(color: Colors.white)),
                      IconButton(
                        tooltip: 'Next year',
                        color: Colors.white,
                        onPressed: _year < DateTime.now().year ? () => setState(() {
                              _year++;
                              _story = null;
                            }) : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Text('Private to you two — share it only if you want to.', style: t.bodySmall?.copyWith(color: Colors.white)),
                  ]),
                ),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: MediaQuery.sizeOf(context).width > 600 ? 3 : 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.4,
                  children: [
                    for (final s in stats)
                      LBCard(
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text(s.$1, style: const TextStyle(fontSize: 24)),
                          Text('${s.$3}', style: t.headlineMedium?.copyWith(color: Theme.of(context).colorScheme.primary)),
                          Text(s.$2, style: t.bodySmall, textAlign: TextAlign.center),
                        ]),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (fav != null || favGame != null)
                  LBCard(
                    child: Text(
                      [
                        if (fav != null) 'Your favourite thing to do together: ${switch (fav) { 'play' => 'playing games 🎮', 'watch' => 'Movie Night 🎬', 'read' => 'reading together 📖', 'talk' => 'talking 💬', 'date' => 'date nights ❤️', 'create' => 'creating together ✍️', _ => fav }}',
                        if (favGame != null) 'Most-played game: ${favGame.emoji} ${favGame.title}',
                      ].join('\n'),
                      style: t.bodyLarge,
                    ),
                  ),
                if (highlights.isNotEmpty) ...[
                  const SectionHeader('Moments you kept'),
                  for (final h in highlights)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Text(switch ((h as Map)['type']) { 'funny' => '😂', 'romantic' => '❤️', _ => '🎉' }, style: const TextStyle(fontSize: 22)),
                      title: Text(h['title'] as String? ?? 'A moment'),
                    ),
                ],
                const SizedBox(height: 16),
                Text('And countless moments together. ❤️', style: t.titleLarge, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                if (_story != null)
                  LBCard(color: Theme.of(context).colorScheme.primaryContainer, child: Text(_story!, style: t.bodyLarge))
                else
                  OutlinedButton.icon(
                    onPressed: _storyLoading ? null : () => _aiStory(r),
                    icon: _storyLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome),
                    label: const Text('Write our year as a little story'),
                  ),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}
