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
import 'internet_archive.dart';
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
            const _ArchiveBrowser(),
            const SectionHeader('Short films'),
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


/// Search & browse thousands of legal public-domain feature films.
class _ArchiveBrowser extends ConsumerStatefulWidget {
  const _ArchiveBrowser();
  @override
  ConsumerState<_ArchiveBrowser> createState() => _ArchiveBrowserState();
}

class _ArchiveBrowserState extends ConsumerState<_ArchiveBrowser> {
  final _q = TextEditingController();
  String _genre = 'Most watched';
  Future<List<ArchiveFilm>>? _results;
  String? _opening;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() => _results = InternetArchive.search(query: _q.text, genre: InternetArchive.genres[_genre] ?? ''));

  Future<void> _watch(ArchiveFilm f) async {
    setState(() => _opening = f.id);
    try {
      final url = await InternetArchive.playableUrl(f.id);
      if (url == null) {
        if (mounted) showToast(context, 'That film has no playable copy. Try another one.');
        return;
      }
      final cid = ref.read(circleIdProvider);
      final row = await sb
          .from('movie_sessions')
          .insert({
            'circle_id': cid,
            'title': f.year == null ? f.title : '${f.title} (${f.year})',
            'source_url': url,
            'source_kind': 'catalog',
            'catalog_id': 'ia:${f.id}',
            'created_by': requireUserId(),
          })
          .select('id')
          .single();
      final id = row['id'] as String;
      await TogetherRepo.start(circleId: cid, activity: 'watch', refType: 'movie', refId: id, title: '🎬 ${f.title}');
      if (mounted) context.push('/movie/$id');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionHeader('Classic movies'),
      Text('Thousands of full-length films that are free and legal to watch, from the Internet Archive\'s public-domain collection.', style: t.bodySmall),
      const SizedBox(height: 12),
      TextField(
        controller: _q,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _load(),
        decoration: InputDecoration(
          hintText: 'Search films, actors, genres…',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(tooltip: 'Search', icon: const Icon(Icons.arrow_forward), onPressed: _load),
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(
        height: 40,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final g in InternetArchive.genres.keys)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(g),
                selected: _genre == g,
                onSelected: (_) {
                  _genre = g;
                  _load();
                },
              ),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      FutureBuilder<List<ArchiveFilm>>(
        future: _results,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const SizedBox(height: 220, child: LoadingView(label: 'Finding films…'));
          if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _load);
          final films = snap.data ?? const [];
          if (films.isEmpty) return const EmptyState(emoji: '🎞️', title: 'No films found', message: 'Try another search or genre.');
          return LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth > 900 ? 5 : (c.maxWidth > 600 ? 4 : 3);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, crossAxisSpacing: 10, mainAxisSpacing: 14, childAspectRatio: 0.52),
              itemCount: films.length,
              itemBuilder: (context, i) {
                final f = films[i];
                return Semantics(
                  button: true,
                  label: 'Watch ${f.title}${f.year != null ? ', ${f.year}' : ''}',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _opening != null ? null : () => _showDetails(f),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Stack(fit: StackFit.expand, children: [
                            Image.network(
                              f.posterUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                decoration: const BoxDecoration(gradient: LBColors.heroGradient),
                                alignment: Alignment.center,
                                child: const Text('🎬', style: TextStyle(fontSize: 34)),
                              ),
                            ),
                            if (_opening == f.id) const ColoredBox(color: Color(0x88000000), child: Center(child: CircularProgressIndicator(color: Colors.white))),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(f.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.titleSmall),
                      if (f.year != null) Text(f.year!, style: t.bodySmall),
                    ]),
                  ),
                );
              },
            );
          });
        },
      ),
    ]);
  }

  void _showDetails(ArchiveFilm f) {
    final t = Theme.of(context).textTheme;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(f.posterUrl, width: 90, height: 130, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(width: 90, height: 130))),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(f.title, style: t.titleLarge),
                  if (f.year != null) Text(f.year!, style: t.bodyMedium),
                  const SizedBox(height: 6),
                  const PillTag('Public domain · Internet Archive'),
                ]),
              ),
            ]),
            if (f.description != null && f.description!.isNotEmpty) ...[
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(child: Text(f.description!, style: t.bodyMedium)),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _watch(f);
              },
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Watch together'),
            ),
          ]),
        ),
      ),
    );
  }
}
