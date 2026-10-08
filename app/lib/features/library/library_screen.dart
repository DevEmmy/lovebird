import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../state/session.dart';
import 'library_repo.dart';

Color bookColor(String hex) => Color(int.parse('FF${hex.substring(1)}', radix: 16));

class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.book, this.width = 96, this.height = 136});
  final Book book;
  final double width;
  final double height;
  @override
  Widget build(BuildContext context) {
    final emoji = switch (book.category) {
      'poetry' => '🌹',
      'interactive' => '💌',
      'love_letter' => '💌',
      'relationship' => '💞',
      _ => '📖',
    };
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bookColor(book.coverColor),
        borderRadius: const BorderRadius.only(topRight: Radius.circular(10), bottomRight: Radius.circular(10), topLeft: Radius.circular(4), bottomLeft: Radius.circular(4)),
        boxShadow: [BoxShadow(color: bookColor(book.coverColor).withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(2, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(emoji, style: TextStyle(fontSize: width * 0.22)),
        const Spacer(),
        Text(book.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: width * 0.12, height: 1.15)),
      ]),
    );
  }
}

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  Future<void> _upload(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    final body = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add to our private shelf'),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('A love letter, a poem you wrote, a story for each other — only you two can see it.', style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 12),
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Title'), maxLength: 120),
            TextField(controller: body, minLines: 6, maxLines: 12, decoration: const InputDecoration(labelText: 'Text', alignLabelWithHint: true)),
            const SizedBox(height: 8),
            Text('Only add writing you created or have the right to share.', style: Theme.of(ctx).textTheme.bodySmall),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true || title.text.trim().isEmpty || body.text.trim().isEmpty || !context.mounted) return;
    await guard(context, () async {
      final cid = ref.read(circleIdProvider);
      final id = await LibraryRepo.uploadPrivate(circleId: cid, title: title.text.trim(), body: body.text.trim());
      await LibraryRepo.addToShelf(cid, id);
      ref.invalidate(catalogProvider);
      ref.invalidate(shelfProvider);
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final shelf = ref.watch(shelfProvider);
    final catalog = ref.watch(catalogProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Our Library 📚')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _upload(context, ref),
        icon: const Icon(Icons.edit_note_rounded),
        label: const Text('Add our writing'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(shelfProvider);
          ref.invalidate(catalogProvider);
        },
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 96), children: [
          Constrained(
            maxWidth: 900,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SectionHeader('Our shelf'),
              shelf.when(
                loading: () => const SizedBox(height: 160, child: LoadingView()),
                error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(shelfProvider)),
                data: (list) => list.isEmpty
                    ? const LBCard(
                        child: Text('Find something beautiful to read together. Tap a book below to add it to your shelf.'),
                      )
                    : SizedBox(
                        height: 200,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 14),
                          itemBuilder: (context, i) {
                            final cb = list[i];
                            if (cb.book == null) return const SizedBox.shrink();
                            return Semantics(
                              button: true,
                              label: '${cb.book!.title}, ${cb.status}',
                              child: InkWell(
                                onTap: () => context.push('/book/${cb.bookId}'),
                                borderRadius: BorderRadius.circular(10),
                                child: SizedBox(
                                  width: 100,
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    BookCover(book: cb.book!),
                                    const SizedBox(height: 6),
                                    PillTag(switch (cb.status) { 'reading' => 'Reading', 'finished' => 'Finished ✓', _ => 'Saved' }),
                                  ]),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
              const SectionHeader('Discover'),
              catalog.when(
                loading: () => const SizedBox(height: 160, child: LoadingView()),
                error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(catalogProvider)),
                data: (books) => Column(children: [
                  for (final b in books.where((b) => !b.isPrivate))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: LBCard(
                        onTap: () => context.push('/book/${b.id}'),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          BookCover(book: b, width: 70, height: 100),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(b.title, style: t.titleMedium),
                              Text(b.author, style: t.bodySmall),
                              const SizedBox(height: 6),
                              if (b.description != null) Text(b.description!, style: t.bodyMedium, maxLines: 3, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 8),
                              Wrap(spacing: 6, runSpacing: 6, children: [
                                PillTag(b.licenseLabel),
                                if (b.chapterCount != null) PillTag('${b.chapterCount} chapters'),
                              ]),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
