import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/errors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/widgets.dart';
import '../../data/media_repo.dart';
import '../../data/models.dart';
import '../../state/session.dart';
import 'diary_repo.dart';

const _prompts = <String, (String title, String hint)>{
  'letter': ('A love letter', 'Dear…'),
  'six_words': ('Our story in six words', 'Six words. No more, no less.'),
  'future': ('A letter to us, one year from now', 'Dear future us…'),
  'story': ('A story we wrote together', 'Once upon a time, two lovebirds…'),
  'funny': ('Too funny to forget', 'What happened?'),
  'anniversary': ('Happy anniversary ❤️', 'What this year with you has meant…'),
};

String originLabel(DiaryEntry e, String Function(String?) nameOf) => switch (e.origin) {
      'together' => 'Written together',
      'suggested' => 'Saved by ${nameOf(e.authorId)} · suggested by Lovebird ✨',
      _ => 'Written by ${nameOf(e.authorId)}',
    };

class DiaryList extends ConsumerStatefulWidget {
  const DiaryList({super.key});
  @override
  ConsumerState<DiaryList> createState() => _DiaryListState();
}

class _DiaryListState extends ConsumerState<DiaryList> {
  String? _type;

  @override
  Widget build(BuildContext context) {
    final nameOf = ref.watch(nameOfProvider);
    final t = Theme.of(context).textTheme;
    return AsyncView<List<DiaryEntry>>(
      value: ref.watch(diaryProvider),
      onRetry: () => ref.invalidate(diaryProvider),
      data: (all) {
        if (all.isEmpty) {
          return EmptyState(
            emoji: '📔',
            title: 'Every relationship has a story.',
            message: 'Start writing yours. Lovebird will also gently suggest moments worth keeping.',
            action: FilledButton(onPressed: () => context.push('/diary/new'), child: const Text('Write the first page')),
          );
        }
        final list = _type == null ? all : all.where((e) => e.entryType == _type).toList();
        return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
          SizedBox(
            height: 42,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: const Text('All'), selected: _type == null, onSelected: (_) => setState(() => _type = null))),
              for (final e in DiaryTypes.all.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(label: Text('${e.value.$1} ${e.value.$2}'), selected: _type == e.key, onSelected: (_) => setState(() => _type = e.key)),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          for (final e in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: LBCard(
                onTap: () => context.push('/diary/${e.id}'),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(DiaryTypes.emoji(e.entryType), style: const TextStyle(fontSize: 26)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(e.title ?? DiaryTypes.label(e.entryType), style: t.titleMedium),
                      const SizedBox(height: 2),
                      Text('${Fmt.day(e.entryDate)} · ${originLabel(e, nameOf)}', style: t.bodySmall),
                      if (e.body != null && e.body!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(e.body!, maxLines: 3, overflow: TextOverflow.ellipsis, style: t.bodyMedium),
                      ] else if (e.payload['messages'] is List) ...[
                        const SizedBox(height: 6),
                        Text(
                          (e.payload['messages'] as List).map((m) => '“${(m as Map)['body']}”').join('  '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
                        ),
                      ],
                    ]),
                  ),
                ]),
              ),
            ),
        ]);
      },
    );
  }
}

class DiaryEntryScreen extends ConsumerWidget {
  const DiaryEntryScreen({super.key, required this.entryId});
  final String entryId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = ref.watch(diaryEntryProvider(entryId));
    final nameOf = ref.watch(nameOfProvider);
    final uid = ref.watch(userIdProvider);
    final t = Theme.of(context).textTheme;
    if (e == null) {
      return Scaffold(appBar: AppBar(), body: ref.watch(diaryProvider).isLoading ? const LoadingView() : const EmptyState(emoji: '🕊️', title: 'Entry not found'));
    }
    final canEdit = e.authorId == uid || e.origin == 'together';
    final messages = e.payload['messages'] is List ? (e.payload['messages'] as List).cast<Map>() : const <Map>[];
    return Scaffold(
      appBar: AppBar(actions: [
        if (canEdit) IconButton(tooltip: 'Edit', onPressed: () => context.push('/diary/${e.id}/edit'), icon: const Icon(Icons.edit_outlined)),
        if (e.authorId == uid)
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final ok = await confirmDialog(context, title: 'Delete this entry?', message: 'It will be removed from Our Diary for both of you.', confirm: 'Delete', destructive: true);
              if (!ok || !context.mounted) return;
              await guard(context, () => DiaryRepo.delete(e.id));
              if (context.mounted) context.pop();
            },
          ),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
        Constrained(
          maxWidth: 680,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${DiaryTypes.emoji(e.entryType)} ${DiaryTypes.label(e.entryType)} · ${Fmt.day(e.entryDate)}', style: t.labelMedium),
            const SizedBox(height: 6),
            if (e.title != null) Text(e.title!, style: t.headlineMedium),
            const SizedBox(height: 4),
            Text(originLabel(e, nameOf), style: t.bodySmall),
            const SizedBox(height: 20),
            for (final p in e.photoPaths)
              Padding(padding: const EdgeInsets.only(bottom: 12), child: ClipRRect(borderRadius: BorderRadius.circular(16), child: StorageImage(p, fit: BoxFit.cover))),
            if (messages.isNotEmpty)
              LBCard(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final m in messages)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('${nameOf(m['sender_id'] as String?)}: ${m['body'] ?? ''}', style: t.bodyLarge),
                    ),
                ]),
              ),
            if (e.body != null) ...[const SizedBox(height: 12), SelectableText(e.body!, style: t.bodyLarge?.copyWith(height: 1.7))],
          ]),
        ),
      ]),
    );
  }
}

class DiaryEditorScreen extends ConsumerStatefulWidget {
  const DiaryEditorScreen({super.key, this.entryId, this.together = false, this.prompt});
  final String? entryId;
  final bool together;
  final String? prompt;
  @override
  ConsumerState<DiaryEditorScreen> createState() => _DiaryEditorScreenState();
}

class _DiaryEditorScreenState extends ConsumerState<DiaryEditorScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  String _type = 'written';
  DateTime _date = DateTime.now();
  final List<XFile> _photos = [];
  List<String> _existing = [];
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = _prompts[widget.prompt];
    if (p != null) _title.text = p.$1;
    if (widget.prompt == 'funny') _type = 'funny';
    if (widget.prompt == 'anniversary' || widget.prompt == 'letter') _type = 'romantic';
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty && _body.text.trim().isEmpty && _photos.isEmpty && _existing.isEmpty) {
      return showToast(context, 'Write something first ❤️');
    }
    setState(() => _saving = true);
    try {
      final cid = ref.read(circleIdProvider);
      final uploaded = await MediaRepo.instance.uploadPhotos(cid, 'diary', _photos);
      if (widget.entryId == null) {
        await DiaryRepo.create(
          circleId: cid,
          entryType: _type,
          origin: widget.together ? 'together' : 'partner',
          title: _title.text.trim().isEmpty ? null : _title.text.trim(),
          body: _body.text.trim().isEmpty ? null : _body.text.trim(),
          photoPaths: uploaded,
          entryDate: _date,
        );
      } else {
        await DiaryRepo.update(widget.entryId!, {
          'title': _title.text.trim().isEmpty ? null : _title.text.trim(),
          'body': _body.text.trim().isEmpty ? null : _body.text.trim(),
          'entry_type': _type,
          'entry_date': _date.toIso8601String().substring(0, 10),
          'photo_paths': [..._existing, ...uploaded],
        });
      }
      if (mounted) {
        showToast(context, 'Saved to Our Diary ❤️');
        context.pop();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entryId != null && !_loaded) {
      final e = ref.watch(diaryEntryProvider(widget.entryId!));
      if (e != null) {
        _loaded = true;
        _title.text = e.title ?? '';
        _body.text = e.body ?? '';
        _type = e.entryType;
        _date = e.entryDate;
        _existing = List.of(e.photoPaths);
      }
    }
    final hint = _prompts[widget.prompt]?.$2 ?? 'Dear diary…';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.together ? 'Write together' : (widget.entryId == null ? 'New entry' : 'Edit entry')),
        actions: [TextButton(onPressed: _saving ? null : _save, child: const Text('Save'))],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Constrained(
          maxWidth: 680,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (widget.together)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: LBCard(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: const Text('✍️ "Written together" entries can be edited by both of you — take turns adding to it.'),
                ),
              ),
            SizedBox(
              height: 42,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final e in DiaryTypes.all.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(label: Text('${e.value.$1} ${e.value.$2}'), selected: _type == e.key, onSelected: (_) => setState(() => _type = e.key)),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            TextField(controller: _title, maxLength: 120, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Title')),
            TextField(
              controller: _body,
              minLines: 10,
              maxLines: null,
              maxLength: 20000,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(hintText: hint, alignLabelWithHint: true),
            ),
            Row(children: [
              TextButton.icon(
                onPressed: () async {
                  final files = await MediaRepo.instance.pickPhotos();
                  setState(() => _photos.addAll(files));
                },
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(_photos.isEmpty && _existing.isEmpty ? 'Add photos' : '${_photos.length + _existing.length} photo(s)'),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () async {
                  final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(1950), lastDate: DateTime.now());
                  if (d != null) setState(() => _date = d);
                },
                icon: const Icon(Icons.event_outlined),
                label: Text(Fmt.day(_date)),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}
