import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/together_repo.dart';
import '../../state/session.dart';
import 'library_repo.dart';
import 'library_screen.dart';

class BookScreen extends ConsumerWidget {
  const BookScreen({super.key, required this.bookId});
  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final bookAsync = ref.watch(bookProvider(bookId));
    final chapters = ref.watch(chapterIndexProvider(bookId)).valueOrNull ?? const [];
    final shelf = ref.watch(shelfProvider).valueOrNull ?? const [];
    final cb = shelf.where((s) => s.bookId == bookId).firstOrNull;
    final uid = ref.watch(userIdProvider);
    final progress = cb == null ? const <ReadingProgress>[] : (ref.watch(progressProvider(cb.id)).valueOrNull ?? const []);
    final partner = ref.watch(partnerProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(),
      body: AsyncView<Book>(
        value: bookAsync,
        onRetry: () => ref.invalidate(bookProvider(bookId)),
        data: (b) {
          final mine = progress.where((p) => p.userId == uid).firstOrNull;
          final theirs = progress.where((p) => p.userId != uid).firstOrNull;
          final total = chapters.isEmpty ? (b.chapterCount ?? 1) : chapters.length;
          int pct(ReadingProgress? p) => p == null ? 0 : ((p.chaptersDone.length / total) * 100).round();
          return ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
            Constrained(
              maxWidth: 720,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  BookCover(book: b, width: 110, height: 156),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(b.title, style: t.headlineSmall),
                      const SizedBox(height: 4),
                      Text(b.author, style: t.bodyMedium),
                      const SizedBox(height: 10),
                      Wrap(spacing: 6, runSpacing: 6, children: [PillTag(b.licenseLabel), PillTag('$total chapters')]),
                    ]),
                  ),
                ]),
                if (b.description != null) ...[const SizedBox(height: 16), Text(b.description!, style: t.bodyLarge)],
                const SizedBox(height: 20),
                if (cb == null)
                  AsyncButton(
                    icon: Icons.bookmark_add_outlined,
                    onPressed: () async {
                      await LibraryRepo.addToShelf(ref.read(circleIdProvider), b.id);
                      ref.invalidate(shelfProvider);
                    },
                    child: const Text('Add to our shelf'),
                  )
                else ...[
                  if (cb.status != 'reading' && cb.status != 'finished')
                    AsyncButton(
                      icon: Icons.menu_book_rounded,
                      onPressed: () async {
                        await LibraryRepo.startReading(cb.id);
                        await TogetherRepo.start(circleId: cb.circleId, activity: 'read', refType: 'reading', refId: cb.id, title: '📖 ${b.title}');
                        ref.invalidate(shelfProvider);
                        if (context.mounted) context.push('/read/${cb.id}');
                      },
                      child: const Text('Start reading together'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: () => context.push('/read/${cb.id}${mine == null ? '' : '?chapter=${mine.chapter}'}'),
                      icon: const Icon(Icons.menu_book_rounded),
                      label: Text(mine == null ? 'Open book' : 'Continue · Chapter ${mine.chapter}'),
                    ),
                  const SizedBox(height: 16),
                  LBCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Our progress', style: t.titleMedium),
                      const SizedBox(height: 10),
                      _ProgressRow(label: 'You', pct: pct(mine), chapter: mine?.chapter, streak: mine?.streakDays),
                      const SizedBox(height: 8),
                      _ProgressRow(label: partner?.displayName ?? 'Partner', pct: pct(theirs), chapter: theirs?.chapter, streak: theirs?.streakDays),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  _BookClubCard(cb: cb),
                  if (cb.status == 'reading' && mine != null && mine.chaptersDone.length >= total) ...[
                    const SizedBox(height: 12),
                    AsyncButton(
                      outlined: true,
                      icon: Icons.celebration_outlined,
                      onPressed: () async {
                        await LibraryRepo.markFinished(cb.id);
                        ref.invalidate(shelfProvider);
                        if (context.mounted) showToast(context, 'You finished "${b.title}" together 🎉');
                      },
                      child: const Text('We finished this book!'),
                    ),
                  ],
                ],
                const SectionHeader('Chapters'),
                for (final ch in chapters)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(child: Text('${ch.number}')),
                    title: Text(ch.title),
                    trailing: (mine?.chaptersDone.contains(ch.number) ?? false) ? const Icon(Icons.check_circle, semanticLabel: 'Read') : null,
                    onTap: cb == null ? null : () => context.push('/read/${cb.id}?chapter=${ch.number}'),
                  ),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.label, required this.pct, this.chapter, this.streak});
  final String label;
  final int pct;
  final int? chapter;
  final int? streak;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: t.titleSmall),
        const Spacer(),
        Text(chapter == null ? 'Not started' : 'Ch. $chapter · $pct%${(streak ?? 0) > 1 ? ' · 🔥 $streak-day streak' : ''}', style: t.bodySmall),
      ]),
      const SizedBox(height: 4),
      ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: pct / 100, minHeight: 6)),
    ]);
  }
}

class _BookClubCard extends ConsumerWidget {
  const _BookClubCard({required this.cb});
  final CircleBook cb;

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    var weekday = (cb.schedule['weekday'] as num?)?.toInt() ?? 5;
    var time = TimeOfDay(
      hour: int.tryParse((cb.schedule['time'] as String? ?? '20:00').split(':').first) ?? 20,
      minute: int.tryParse((cb.schedule['time'] as String? ?? '20:00').split(':').last) ?? 0,
    );
    final goal = TextEditingController(text: cb.goal);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Our book club'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Reading night'),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (var i = 1; i <= 7; i++) ChoiceChip(label: Text(_days[i - 1]), selected: weekday == i, onSelected: (_) => setLocal(() => weekday = i)),
            ]),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.schedule),
              label: Text(time.format(ctx)),
              onPressed: () async {
                final picked = await showTimePicker(context: ctx, initialTime: time);
                if (picked != null) setLocal(() => time = picked);
              },
            ),
            const SizedBox(height: 12),
            TextField(controller: goal, decoration: const InputDecoration(labelText: 'Goal (e.g. 2 chapters a week)'), maxLength: 200),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    await guard(context, () => LibraryRepo.setClub(cb.id, weekday: weekday, time: '$hh:$mm', tz: DateTime.now().timeZoneName, goal: goal.text.trim().isEmpty ? null : goal.text.trim()));
    ref.invalidate(shelfProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    return LBCard(
      onTap: () => _edit(context, ref),
      child: Row(children: [
        const Text('☕', style: TextStyle(fontSize: 26)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(cb.isClub ? 'Our book club' : 'Make it a book club', style: t.titleSmall),
            Text(
              cb.isClub && cb.nextSessionAt != null
                  ? 'Next reading session: ${Fmt.weekdayTime(cb.nextSessionAt!)}${cb.goal != null ? '\nGoal: ${cb.goal}' : ''}'
                  : 'Set a weekly reading night and a goal.',
              style: t.bodySmall,
            ),
          ]),
        ),
        const Icon(Icons.edit_calendar_outlined),
      ]),
    );
  }
}
