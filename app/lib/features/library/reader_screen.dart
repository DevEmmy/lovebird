import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../state/circle_channel.dart';
import '../../state/session.dart';
import '../diary/diary_repo.dart';
import '../diary/moment_suggester.dart';
import 'library_repo.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.circleBookId, this.initialChapter});
  final String circleBookId;
  final int? initialChapter;
  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  int? _chapter;
  double _fontScale = 1.0;
  final _scroll = ScrollController();
  Timer? _saveDebounce;
  CircleChannel? _channel;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _channel = ref.read(circleChannelProvider));
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _scroll.dispose();
    _channel?.setActivity(null);
    super.dispose();
  }

  List<int> _myDone() {
    final uid = ref.read(userIdProvider);
    final p = (ref.read(progressProvider(widget.circleBookId)).valueOrNull ?? const []).where((p) => p.userId == uid).firstOrNull;
    return p?.chaptersDone ?? const [];
  }

  void _onScroll() {
    if (!_scroll.hasClients || _chapter == null) return;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 2), () => _save());
  }

  Future<void> _save({List<int>? done}) async {
    final cb = ref.read(circleBookProvider(widget.circleBookId)).valueOrNull;
    if (cb == null || _chapter == null) return;
    final max = _scroll.hasClients ? _scroll.position.maxScrollExtent : 0.0;
    final ratio = max <= 0 ? 1.0 : (_scroll.offset / max).clamp(0.0, 1.0);
    try {
      await LibraryRepo.saveProgress(
        circleBookId: cb.id,
        circleId: cb.circleId,
        chapter: _chapter!,
        scroll: ratio,
        chaptersDone: done ?? _myDone(),
      );
    } catch (_) {}
  }

  void _goChapter(int n) {
    setState(() => _chapter = n);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _channel?.setActivity('reading ch. $n');
    _save();
  }

  Future<void> _highlight(String quote) async {
    final cb = ref.read(circleBookProvider(widget.circleBookId)).valueOrNull;
    if (cb == null || quote.trim().isEmpty) return;
    final note = await promptText(context, title: 'Add a note? (optional)', hint: 'Why did this line stand out?', maxLength: 500, maxLines: 3);
    if (!mounted) return;
    await guard(context, () => LibraryRepo.highlight(circleBookId: cb.id, circleId: cb.circleId, chapter: _chapter!, quote: quote.trim(), note: (note?.isEmpty ?? true) ? null : note));
    if (mounted) showToast(context, 'Highlighted ❤️ Your partner will see it.');
  }

  Future<void> _finishChapter(int total) async {
    final done = {..._myDone(), _chapter!}.toList()..sort();
    await _save(done: done);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReflectionSheet(circleBookId: widget.circleBookId, chapter: _chapter!),
    );
    if (mounted && _chapter! < total) _goChapter(_chapter! + 1);
  }

  void _openHighlights() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, controller) => _HighlightsSheet(circleBookId: widget.circleBookId, controller: controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cbAsync = ref.watch(circleBookProvider(widget.circleBookId));
    final uid = ref.watch(userIdProvider);
    final partner = ref.watch(partnerProvider).valueOrNull;
    final progress = ref.watch(progressProvider(widget.circleBookId)).valueOrNull ?? const [];
    final t = Theme.of(context).textTheme;

    return cbAsync.when(
      loading: () => const Scaffold(body: LoadingView()),
      error: (e, _) => Scaffold(appBar: AppBar(), body: ErrorView(error: e, onRetry: () => ref.invalidate(circleBookProvider(widget.circleBookId)))),
      data: (cb) {
        final chapters = ref.watch(chapterIndexProvider(cb.bookId)).valueOrNull ?? const <Chapter>[];
        final mine = progress.where((p) => p.userId == uid).firstOrNull;
        _chapter ??= widget.initialChapter ?? mine?.chapter ?? 1;
        final total = chapters.isEmpty ? 1 : chapters.length;
        final chapterAsync = ref.watch(chapterProvider((cb.bookId, _chapter!)));
        final theirs = progress.where((p) => p.userId != uid).firstOrNull;
        final partnerActivity = _channel?.activityOf(partner?.id);

        return Scaffold(
          appBar: AppBar(
            title: Text(cb.book?.title ?? 'Reading', overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(tooltip: 'Smaller text', onPressed: () => setState(() => _fontScale = (_fontScale - 0.1).clamp(0.8, 1.8)), icon: const Icon(Icons.text_decrease)),
              IconButton(tooltip: 'Larger text', onPressed: () => setState(() => _fontScale = (_fontScale + 0.1).clamp(0.8, 1.8)), icon: const Icon(Icons.text_increase)),
              IconButton(tooltip: 'Highlights & notes', onPressed: _openHighlights, icon: const Icon(Icons.format_quote_rounded)),
              PopupMenuButton<int>(
                tooltip: 'Chapters',
                icon: const Icon(Icons.list_rounded),
                onSelected: _goChapter,
                itemBuilder: (_) => [
                  for (final c in chapters)
                    PopupMenuItem(
                      value: c.number,
                      child: Text('${c.number}. ${c.title}${(mine?.chaptersDone.contains(c.number) ?? false) ? '  ✓' : ''}'),
                    ),
                ],
              ),
            ],
          ),
          body: Column(children: [
            if (partner != null)
              Material(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(children: [
                    const Text('💞 '),
                    Expanded(
                      child: Text(
                        partnerActivity != null && partnerActivity.startsWith('reading')
                            ? '${partner.displayName} is ${partnerActivity.replaceFirst('ch.', 'Chapter')} right now'
                            : theirs == null
                                ? '${partner.displayName} hasn\'t started yet'
                                : '${partner.displayName} is on Chapter ${theirs.chapter} · last read ${Fmt.relative(theirs.lastReadOn)}',
                        style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onPrimaryContainer),
                      ),
                    ),
                  ]),
                ),
              ),
            Expanded(
              child: chapterAsync.when(
                loading: () => const LoadingView(),
                error: (e, _) => ErrorView(error: e),
                data: (ch) {
                  if (ch == null) return const EmptyState(emoji: '📖', title: 'Chapter not found');
                  final isPoem = cb.book?.category == 'poetry';
                  return Scrollbar(
                    controller: _scroll,
                    child: SingleChildScrollView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
                      child: Constrained(
                        maxWidth: 680,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Text('Chapter ${ch.number} of $total', style: t.labelMedium),
                          const SizedBox(height: 6),
                          Semantics(header: true, child: Text(ch.title, style: t.headlineMedium)),
                          const SizedBox(height: 20),
                          SelectableText(
                            ch.body,
                            textAlign: isPoem ? TextAlign.left : TextAlign.start,
                            style: t.bodyLarge?.copyWith(fontSize: 17 * _fontScale, height: isPoem ? 1.7 : 1.65, fontFamily: isPoem ? 'serif' : null),
                            contextMenuBuilder: (context, state) {
                              final value = state.textEditingValue;
                              final selected = value.selection.textInside(value.text);
                              return AdaptiveTextSelectionToolbar.buttonItems(
                                anchors: state.contextMenuAnchors,
                                buttonItems: [
                                  if (selected.trim().isNotEmpty)
                                    ContextMenuButtonItem(
                                      label: 'Highlight ❤️',
                                      onPressed: () {
                                        ContextMenuController.removeAny();
                                        _highlight(selected);
                                      },
                                    ),
                                  ...state.contextMenuButtonItems,
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          Text('Tip: select any line to highlight it for ${partner?.displayName ?? 'your partner'}.', style: t.bodySmall, textAlign: TextAlign.center),
                          const SizedBox(height: 28),
                          FilledButton.icon(
                            onPressed: () => _finishChapter(total),
                            icon: const Icon(Icons.check_rounded),
                            label: Text(_chapter! < total ? 'Finish chapter & share thoughts' : 'Finish the book & share thoughts'),
                          ),
                          const SizedBox(height: 10),
                          Row(children: [
                            if (_chapter! > 1) TextButton(onPressed: () => _goChapter(_chapter! - 1), child: const Text('← Previous')),
                            const Spacer(),
                            if (_chapter! < total) TextButton(onPressed: () => _goChapter(_chapter! + 1), child: const Text('Next →')),
                          ]),
                        ]),
                      ),
                    ),
                  );
                },
              ),
            ),
          ]),
        );
      },
    );
  }
}

/// "What did you think about that chapter?" — sealed until both have answered.
class _ReflectionSheet extends ConsumerStatefulWidget {
  const _ReflectionSheet({required this.circleBookId, required this.chapter});
  final String circleBookId;
  final int chapter;
  @override
  ConsumerState<_ReflectionSheet> createState() => _ReflectionSheetState();
}

class _ReflectionSheetState extends ConsumerState<_ReflectionSheet> {
  final _text = TextEditingController();
  int _rating = 4;
  List<Reflection>? _reflections;
  bool _busy = false;
  Timer? _poll;
  bool _suggested = false;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 6), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await LibraryRepo.reflections(widget.circleBookId, widget.chapter);
      if (mounted) setState(() => _reflections = r);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final uid = ref.watch(userIdProvider);
    final partner = ref.watch(partnerProvider).valueOrNull;
    final cb = ref.watch(circleBookProvider(widget.circleBookId)).valueOrNull;
    final mine = _reflections?.where((r) => r.userId == uid).firstOrNull;
    final theirs = _reflections?.where((r) => r.userId != uid).firstOrNull;

    if (mine != null && theirs != null && !_suggested && cb != null) {
      _suggested = true;
      _poll?.cancel();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        MomentSuggester.maybeSuggest(
          context,
          cb.circleId,
          MomentSuggestion(
            kind: 'reading_chapter',
            headline: '📖 A reading moment',
            prompt: 'Save your thoughts on Chapter ${widget.chapter} to Our Diary?',
            entryType: 'reading',
            title: '${cb.book?.title ?? 'Our book'} — Chapter ${widget.chapter}',
            body: 'You: ${mine.body}\n\n${partner?.displayName ?? 'Partner'}: ${theirs.body}',
          ),
        );
      });
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('What did you think about that chapter?', style: t.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          if (_reflections == null)
            const LoadingView()
          else if (mine == null) ...[
            TextField(controller: _text, minLines: 3, maxLines: 6, maxLength: 4000, decoration: const InputDecoration(hintText: 'Your thoughts stay hidden until you both share.')),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  tooltip: '$i of 5',
                  onPressed: () => setState(() => _rating = i),
                  icon: Icon(i <= _rating ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: Theme.of(context).colorScheme.primary),
                ),
            ]),
            FilledButton(
              onPressed: _busy || cb == null
                  ? null
                  : () async {
                      if (_text.text.trim().isEmpty) return;
                      setState(() => _busy = true);
                      try {
                        await LibraryRepo.reflect(circleBookId: cb.id, circleId: cb.circleId, chapter: widget.chapter, body: _text.text.trim(), rating: _rating);
                        await _load();
                      } catch (e) {
                        if (context.mounted) showError(context, e);
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              child: const Text('Share 🔒'),
            ),
          ] else if (theirs == null) ...[
            LBCard(child: Text('You: ${mine.body}')),
            const SizedBox(height: 16),
            Text('Waiting for ${partner?.displayName ?? 'your partner'} to finish this chapter…', style: t.titleSmall, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text('We\'ll reveal both of your thoughts together.', style: t.bodySmall, textAlign: TextAlign.center),
          ] else ...[
            LBCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('You ${'❤' * (mine.rating ?? 0)}', style: t.labelLarge),
              const SizedBox(height: 4),
              Text(mine.body),
            ])),
            const SizedBox(height: 10),
            LBCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${partner?.displayName ?? 'Partner'} ${'❤' * (theirs.rating ?? 0)}', style: t.labelLarge),
              const SizedBox(height: 4),
              Text(theirs.body),
            ])),
          ],
          const SizedBox(height: 12),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Continue reading')),
        ]),
      ),
    );
  }
}

class _HighlightsSheet extends ConsumerWidget {
  const _HighlightsSheet({required this.circleBookId, required this.controller});
  final String circleBookId;
  final ScrollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final list = ref.watch(highlightsProvider(circleBookId));
    final nameOf = ref.watch(nameOfProvider);
    final cb = ref.watch(circleBookProvider(circleBookId)).valueOrNull;
    return list.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(error: e),
      data: (hs) => hs.isEmpty
          ? const EmptyState(emoji: '✨', title: 'No highlights yet', message: 'Select a line while reading and tap "Highlight ❤️".')
          : ListView(controller: controller, padding: const EdgeInsets.all(16), children: [
              for (final h in hs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: LBCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${nameOf(h.userId)} · Chapter ${h.chapter}', style: t.labelMedium),
                      const SizedBox(height: 6),
                      Text('“${h.quote}”', style: t.bodyLarge?.copyWith(fontStyle: FontStyle.italic)),
                      if (h.note != null) ...[const SizedBox(height: 6), Text(h.note!, style: t.bodyMedium)],
                      for (final r in h.replies)
                        Padding(
                          padding: const EdgeInsets.only(top: 6, left: 12),
                          child: Text('${nameOf(r.userId)}: ${r.body}', style: t.bodySmall?.copyWith(color: t.bodyMedium?.color)),
                        ),
                      Row(children: [
                        TextButton.icon(
                          icon: const Icon(Icons.reply_rounded, size: 18),
                          label: const Text('Reply'),
                          onPressed: cb == null
                              ? null
                              : () async {
                                  final body = await promptText(context, title: 'Reply', maxLength: 2000, maxLines: 3);
                                  if (body == null || body.isEmpty || !context.mounted) return;
                                  await guard(context, () => LibraryRepo.reply(h.id, cb.circleId, body));
                                  ref.invalidate(highlightsProvider(circleBookId));
                                },
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.auto_stories_outlined, size: 18),
                          label: const Text('Save to diary'),
                          onPressed: cb == null
                              ? null
                              : () => guard(context, () async {
                                    await DiaryRepo.create(
                                      circleId: cb.circleId,
                                      entryType: 'reading',
                                      title: '${cb.book?.title ?? 'Our book'} — Chapter ${h.chapter}',
                                      body: '“${h.quote}”${h.note == null ? '' : '\n\n${h.note}'}',
                                    );
                                    if (context.mounted) showToast(context, 'Saved to Our Diary ❤️');
                                  }),
                        ),
                      ]),
                    ]),
                  ),
                ),
            ]),
    );
  }
}
