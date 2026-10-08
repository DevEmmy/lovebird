import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/errors.dart';
import '../../core/supabase.dart';
import '../../core/theme/colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/widgets.dart';
import '../../data/media_repo.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../state/session.dart';
import '../diary/diary_screens.dart';

const memoryCategories = <String, (String, String)>{
  'moment': ('✨', 'Moment'),
  'date': ('❤️', 'Date'),
  'milestone': ('🎉', 'Milestone'),
  'trip': ('✈️', 'Trip'),
  'movie': ('🎬', 'Movie night'),
  'game': ('🎮', 'Game'),
  'reading': ('📖', 'Reading'),
  'chat': ('💬', 'Chat'),
  'photo': ('📸', 'Photo'),
  'other': ('💫', 'Other'),
};

class MemoriesScreen extends ConsumerStatefulWidget {
  const MemoriesScreen({super.key});
  @override
  ConsumerState<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends ConsumerState<MemoriesScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this);
  bool _grid = false;
  String? _lastTabParam;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tab = GoRouterState.of(context).uri.queryParameters['tab'];
    if (tab != _lastTabParam) {
      _lastTabParam = tab;
      if (tab == 'diary') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _tabs.animateTo(1);
        });
      }
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Memories'),
        actions: [
          IconButton(tooltip: 'Special dates', onPressed: () => context.push('/special-dates'), icon: const Icon(Icons.event_rounded)),
          IconButton(tooltip: 'Our year recap', onPressed: () => context.push('/recap'), icon: const Icon(Icons.auto_awesome_rounded)),
        ],
        bottom: TabBar(controller: _tabs, tabs: const [Tab(text: '📸 Our Memories'), Tab(text: '📔 Our Diary')]),
      ),
      floatingActionButton: ListenableBuilder(
        listenable: _tabs,
        builder: (context, _) => FloatingActionButton.extended(
          onPressed: () => context.push(_tabs.index == 0 ? '/memory/new' : '/diary/new'),
          icon: Icon(_tabs.index == 0 ? Icons.add_a_photo_outlined : Icons.edit_outlined),
          label: Text(_tabs.index == 0 ? 'New memory' : 'Write'),
        ),
      ),
      body: TabBarView(controller: _tabs, children: [
        _MemoriesTab(grid: _grid, onToggle: () => setState(() => _grid = !_grid)),
        const DiaryList(),
      ]),
    );
  }
}

class _MemoriesTab extends ConsumerWidget {
  const _MemoriesTab({required this.grid, required this.onToggle});
  final bool grid;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    return AsyncView<List<Memory>>(
      value: ref.watch(memoriesProvider),
      onRetry: () => ref.invalidate(memoriesProvider),
      data: (list) {
        if (list.isEmpty) {
          return EmptyState(
            emoji: '📸',
            title: 'Your story starts here ❤️',
            message: 'Save photos, dates and little moments. They\'ll become your timeline.',
            action: FilledButton(onPressed: () => context.push('/memory/new'), child: const Text('Save our first memory')),
          );
        }
        final toggle = Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            tooltip: grid ? 'Timeline view' : 'Gallery view',
            onPressed: onToggle,
            icon: Icon(grid ? Icons.view_agenda_outlined : Icons.grid_view_rounded),
          ),
        );
        if (grid) {
          final photos = [for (final m in list) for (final p in m.photoPaths) (m, p)];
          return ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 96), children: [
            toggle,
            if (photos.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No photos yet.')),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 160, mainAxisSpacing: 6, crossAxisSpacing: 6),
              itemCount: photos.length,
              itemBuilder: (context, i) => InkWell(
                onTap: () => context.push('/memory/${photos[i].$1.id}'),
                child: ClipRRect(borderRadius: BorderRadius.circular(12), child: StorageImage(photos[i].$2, semanticLabel: photos[i].$1.title)),
              ),
            ),
          ]);
        }
        // Timeline grouped by month
        final groups = <String, List<Memory>>{};
        for (final m in list) {
          (groups[Fmt.monthYear(m.happenedOn)] ??= []).add(m);
        }
        return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 96), children: [
          toggle,
          for (final g in groups.entries) ...[
            Padding(padding: const EdgeInsets.fromLTRB(4, 8, 4, 10), child: Text(g.key, style: t.titleMedium)),
            for (final m in g.value) _TimelineTile(m: m),
          ],
        ]);
      },
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({required this.m});
  final Memory m;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cat = memoryCategories[m.category] ?? ('✨', 'Moment');
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 28,
          child: Column(children: [
            Container(width: 12, height: 12, margin: const EdgeInsets.only(top: 18), decoration: const BoxDecoration(color: LBColors.rose, shape: BoxShape.circle)),
            Expanded(child: Container(width: 2, color: Theme.of(context).colorScheme.outlineVariant)),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: LBCard(
              padding: EdgeInsets.zero,
              onTap: () => context.push('/memory/${m.id}'),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (m.photoPaths.isNotEmpty)
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    child: SizedBox(height: 180, child: StorageImage(m.photoPaths.first, semanticLabel: m.title)),
                  ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${cat.$1} ${cat.$2} · ${Fmt.day(m.happenedOn)}', style: t.labelMedium),
                    const SizedBox(height: 4),
                    Text(m.title, style: t.titleMedium),
                    if (m.description != null && m.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(m.description!, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodyMedium),
                    ],
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class MemoryDetailScreen extends ConsumerWidget {
  const MemoryDetailScreen({super.key, required this.memoryId});
  final String memoryId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(memoryProvider(memoryId));
    final nameOf = ref.watch(nameOfProvider);
    final uid = ref.watch(userIdProvider);
    final t = Theme.of(context).textTheme;
    if (m == null) {
      return Scaffold(appBar: AppBar(), body: ref.watch(memoriesProvider).isLoading ? const LoadingView() : const EmptyState(emoji: '🕊️', title: 'Memory not found'));
    }
    final cat = memoryCategories[m.category] ?? ('✨', 'Moment');
    return Scaffold(
      appBar: AppBar(actions: [
        IconButton(tooltip: 'Edit', onPressed: () => context.push('/memory/${m.id}/edit'), icon: const Icon(Icons.edit_outlined)),
        if (m.authorId == uid)
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final ok = await confirmDialog(context, title: 'Delete this memory?', message: 'It will be removed for both of you.', confirm: 'Delete', destructive: true);
              if (!ok || !context.mounted) return;
              await guard(context, () => sb.from('memories').delete().eq('id', m.id));
              ref.invalidate(memoriesProvider);
              if (context.mounted) context.pop();
            },
          ),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        Constrained(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (m.photoPaths.isNotEmpty)
              SizedBox(
                height: 320,
                child: PageView(children: [
                  for (final p in m.photoPaths)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ClipRRect(borderRadius: BorderRadius.circular(20), child: StorageImage(p, fit: BoxFit.cover, semanticLabel: m.title)),
                    ),
                ]),
              ),
            const SizedBox(height: 16),
            Text('${cat.$1} ${cat.$2} · ${Fmt.day(m.happenedOn)}', style: t.labelMedium),
            const SizedBox(height: 6),
            Text(m.title, style: t.headlineMedium),
            if (m.description != null) ...[const SizedBox(height: 12), Text(m.description!, style: t.bodyLarge)],
            const SizedBox(height: 16),
            Text('Saved by ${nameOf(m.authorId)}${m.source == 'suggested' ? ' · suggested by Lovebird ✨' : ''}', style: t.bodySmall),
          ]),
        ),
      ]),
    );
  }
}

class MemoryEditorScreen extends ConsumerStatefulWidget {
  const MemoryEditorScreen({super.key, this.memoryId});
  final String? memoryId;
  @override
  ConsumerState<MemoryEditorScreen> createState() => _MemoryEditorScreenState();
}

class _MemoryEditorScreenState extends ConsumerState<MemoryEditorScreen> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  DateTime _date = DateTime.now();
  String _category = 'moment';
  List<String> _existing = [];
  final List<XFile> _new = [];
  bool _saving = false;
  bool _loaded = false;

  void _loadExisting(Memory m) {
    if (_loaded) return;
    _loaded = true;
    _title.text = m.title;
    _desc.text = m.description ?? '';
    _date = m.happenedOn;
    _category = m.category;
    _existing = List.of(m.photoPaths);
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) return showToast(context, 'Give this memory a title.');
    setState(() => _saving = true);
    try {
      final cid = ref.read(circleIdProvider);
      final uploaded = await MediaRepo.instance.uploadPhotos(cid, 'memories', _new);
      final fields = {
        'title': _title.text.trim(),
        'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        'happened_on': DateFormat('yyyy-MM-dd').format(_date),
        'category': _category,
        'photo_paths': [..._existing, ...uploaded],
      };
      if (widget.memoryId == null) {
        await sb.from('memories').insert({...fields, 'circle_id': cid, 'author_id': requireUserId()});
      } else {
        await sb.from('memories').update(fields).eq('id', widget.memoryId!);
      }
      ref.invalidate(memoriesProvider);
      if (mounted) {
        showToast(context, 'Memory saved ❤️');
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
    if (widget.memoryId != null) {
      final m = ref.watch(memoryProvider(widget.memoryId!));
      if (m != null) _loadExisting(m);
    }
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.memoryId == null ? 'New memory' : 'Edit memory'),
        actions: [TextButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'))],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Constrained(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: 110,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () async {
                    final files = await MediaRepo.instance.pickPhotos();
                    setState(() => _new.addAll(files));
                  },
                  child: Container(
                    width: 110,
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(16)),
                    child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_photo_alternate_outlined), SizedBox(height: 4), Text('Add photos')]),
                  ),
                ),
                for (final p in _existing)
                  _Thumb(child: StorageImage(p), onRemove: () => setState(() => _existing.remove(p))),
                for (final f in _new)
                  _Thumb(child: FutureBuilder(future: f.readAsBytes(), builder: (_, s) => s.hasData ? Image.memory(s.data!, fit: BoxFit.cover) : const SizedBox()), onRemove: () => setState(() => _new.remove(f))),
              ]),
            ),
            const SizedBox(height: 16),
            TextField(controller: _title, maxLength: 120, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Title')),
            const SizedBox(height: 8),
            TextField(controller: _desc, minLines: 3, maxLines: 8, maxLength: 4000, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'What happened?', alignLabelWithHint: true)),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(Fmt.day(_date)),
              subtitle: const Text('When was it?'),
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(1950), lastDate: DateTime.now().add(const Duration(days: 365)));
                if (d != null) setState(() => _date = d);
              },
            ),
            const SizedBox(height: 8),
            Text('Category', style: t.titleSmall),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in memoryCategories.entries)
                ChoiceChip(label: Text('${c.value.$1} ${c.value.$2}'), selected: _category == c.key, onSelected: (_) => setState(() => _category = c.key)),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.child, required this.onRemove});
  final Widget child;
  final VoidCallback onRemove;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Stack(children: [
          ClipRRect(borderRadius: BorderRadius.circular(16), child: SizedBox(width: 110, height: 110, child: child)),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton.filledTonal(tooltip: 'Remove photo', iconSize: 16, visualDensity: VisualDensity.compact, onPressed: onRemove, icon: const Icon(Icons.close)),
          ),
        ]),
      );
}
