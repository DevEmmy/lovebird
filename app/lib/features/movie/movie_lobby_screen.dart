import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/supabase.dart';
import '../../core/theme/colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../../data/together_repo.dart';
import '../../state/session.dart';
import 'movie_catalog.dart';

final _recentMoviesProvider = FutureProvider.autoDispose<List<MovieSession>>((ref) async {
  final cid = ref.watch(circleIdProvider);
  final rows = await sb.from('movie_sessions').select().eq('circle_id', cid).order('created_at', ascending: false).limit(10);
  return rows.map(MovieSession.fromJson).toList();
});

class MovieLobbyScreen extends ConsumerStatefulWidget {
  const MovieLobbyScreen({super.key});
  @override
  ConsumerState<MovieLobbyScreen> createState() => _MovieLobbyScreenState();
}

class _MovieLobbyScreenState extends ConsumerState<MovieLobbyScreen> {
  bool _busy = false;

  Future<void> _start({required String title, required String url, required String kind, String? catalogId, bool rights = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final cid = ref.read(circleIdProvider);
      final row = await sb
          .from('movie_sessions')
          .insert({
            'circle_id': cid,
            'title': title,
            'source_url': url,
            'source_kind': kind,
            'catalog_id': catalogId,
            'rights_confirmed': rights,
            'created_by': requireUserId(),
          })
          .select('id')
          .single();
      final id = row['id'] as String;
      await TogetherRepo.start(circleId: cid, activity: 'watch', refType: 'movie', refId: id, title: '🎬 $title');
      if (mounted) context.push('/movie/$id');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _ownLink() async {
    final url = TextEditingController();
    final title = TextEditingController();
    var rights = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Watch your own video'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Title'), maxLength: 120),
              const SizedBox(height: 8),
              TextField(
                controller: url,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'Direct video link (https://….mp4)'),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: rights,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (v) => setLocal(() => rights = v ?? false),
                title: const Text('I own this video or have permission to stream it.'),
              ),
              Text(
                'Lovebird can\'t sync Netflix, Prime or other services that don\'t allow it — and won\'t try to get around their rules.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: rights ? () => Navigator.pop(ctx, true) : null, child: const Text('Start')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final u = Uri.tryParse(url.text.trim());
    if (u == null || u.scheme != 'https' || u.host.isEmpty) {
      if (mounted) showToast(context, 'Please use a secure https:// video link.');
      return;
    }
    await _start(title: title.text.trim().isEmpty ? 'Our video' : title.text.trim(), url: u.toString(), kind: 'user_link', rights: true);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final recent = ref.watch(_recentMoviesProvider).valueOrNull ?? const [];
    final live = recent.where((m) => m.endedAt == null && DateTime.now().difference(m.createdAt).inHours < 6).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Movie Night 🎬')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        Constrained(
          maxWidth: 900,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Press play together. Pause together. Laugh at the same moment.', style: t.bodyLarge),
            if (live.isNotEmpty) ...[
              const SectionHeader('Rejoin'),
              for (final m in live.take(2))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: LBCard(
                    onTap: () => context.push('/movie/${m.id}'),
                    child: Row(children: [
                      const Text('🍿', style: TextStyle(fontSize: 26)),
                      const SizedBox(width: 12),
                      Expanded(child: Text(m.title, style: t.titleSmall)),
                      Text(Fmt.relative(m.createdAt), style: t.bodySmall),
                    ]),
                  ),
                ),
            ],
            const SectionHeader('Free to watch together'),
            LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth > 700 ? 4 : 2;
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.78,
                children: [
                  for (final f in movieCatalog)
                    Semantics(
                      button: true,
                      label: '${f.title}, ${f.minutes} minutes. ${f.description}',
                      child: LBCard(
                        padding: EdgeInsets.zero,
                        onTap: _busy ? null : () => _start(title: f.title, url: f.url, kind: 'catalog', catalogId: f.id),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Expanded(
                            child: Container(
                              decoration: const BoxDecoration(
                                gradient: LBColors.heroGradient,
                                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                              ),
                              alignment: Alignment.center,
                              child: Text(f.emoji, style: const TextStyle(fontSize: 48)),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(f.title, style: t.titleSmall),
                              Text('${f.year} · ${f.minutes} min', style: t.bodySmall),
                              const SizedBox(height: 4),
                              Text(f.description, style: t.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                ],
              );
            }),
            const SizedBox(height: 16),
            OutlinedButton.icon(onPressed: _busy ? null : _ownLink, icon: const Icon(Icons.link_rounded), label: const Text('Watch your own video')),
            const SizedBox(height: 12),
            Text(
              'More licensed films are coming. Lovebird only streams content that\'s free, public-domain, Creative Commons, or yours.',
              style: t.bodySmall,
              textAlign: TextAlign.center,
            ),
          ]),
        ),
      ]),
    );
  }
}
