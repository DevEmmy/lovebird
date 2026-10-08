import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/supabase.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../state/session.dart';

const planCategories = <String, (String, String)>{
  'dates': ('💡', 'Future dates'),
  'movies': ('🎬', 'Movies to watch'),
  'books': ('📚', 'Books to read'),
  'restaurants': ('🍽️', 'Restaurants'),
  'places': ('🗺️', 'Places to visit'),
  'gifts': ('🎁', 'Gift ideas'),
  'bucket': ('🌟', 'Bucket list'),
  'goals': ('🎯', 'Relationship goals'),
  'try': ('🧪', 'Things to try'),
  'custom': ('📝', 'Custom list'),
};

class PlansScreen extends ConsumerWidget {
  const PlansScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final cat = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final c in planCategories.entries)
            ListTile(leading: Text(c.value.$1, style: const TextStyle(fontSize: 22)), title: Text(c.value.$2), onTap: () => Navigator.pop(ctx, c.key)),
        ]),
      ),
    );
    if (cat == null || !context.mounted) return;
    final title = cat == 'custom' ? await promptText(context, title: 'List name', maxLength: 80) : planCategories[cat]!.$2;
    if (title == null || title.isEmpty || !context.mounted) return;
    await guard(context, () async {
      final row = await sb
          .from('plans')
          .insert({'circle_id': ref.read(circleIdProvider), 'title': title, 'category': cat, 'emoji': planCategories[cat]!.$1, 'created_by': requireUserId()})
          .select('id')
          .single();
      ref.invalidate(plansProvider);
      if (context.mounted) context.push('/plans/${row['id']}');
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(planItemsProvider).valueOrNull ?? const [];
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Our Plans 📝')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _create(context, ref), icon: const Icon(Icons.add), label: const Text('New list')),
      body: AsyncView<List<Plan>>(
        value: ref.watch(plansProvider),
        onRetry: () => ref.invalidate(plansProvider),
        data: (plans) => plans.isEmpty
            ? EmptyState(
                emoji: '📝',
                title: 'Plan your next moment together.',
                message: 'Dates, movies, places, gifts, goals — keep them in shared lists you can both tick off.',
                action: FilledButton(onPressed: () => _create(context, ref), child: const Text('Start a list')),
              )
            : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
                Constrained(
                  child: Column(children: [
                    for (final p in plans)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Builder(builder: (context) {
                          final mine = items.where((i) => i.planId == p.id).toList();
                          final done = mine.where((i) => i.done).length;
                          return LBCard(
                            onTap: () => context.push('/plans/${p.id}'),
                            child: Row(children: [
                              Text(p.emoji ?? planCategories[p.category]?.$1 ?? '📝', style: const TextStyle(fontSize: 26)),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(p.title, style: t.titleMedium),
                                  Text(mine.isEmpty ? 'Empty — add the first idea' : '$done of ${mine.length} done', style: t.bodySmall),
                                ]),
                              ),
                              const Icon(Icons.chevron_right_rounded),
                            ]),
                          );
                        }),
                      ),
                  ]),
                ),
              ]),
      ),
    );
  }
}

class PlanDetailScreen extends ConsumerStatefulWidget {
  const PlanDetailScreen({super.key, required this.planId});
  final String planId;
  @override
  ConsumerState<PlanDetailScreen> createState() => _PlanDetailScreenState();
}

class _PlanDetailScreenState extends ConsumerState<PlanDetailScreen> {
  final _add = TextEditingController();
  bool _private = false;

  Future<void> _addItem(Plan p) async {
    final text = _add.text.trim();
    if (text.isEmpty) return;
    _add.clear();
    await guard(context, () => sb.from('plan_items').insert({
          'plan_id': p.id,
          'circle_id': p.circleId,
          'text': text,
          'created_by': requireUserId(),
          if (_private) 'private_to': requireUserId(),
        }));
  }

  Future<void> _toggle(PlanItem i) => guard(context, () => sb.from('plan_items').update({
        'done_at': i.done ? null : DateTime.now().toUtc().toIso8601String(),
        'done_by': i.done ? null : requireUserId(),
      }).eq('id', i.id));

  Future<void> _edit(PlanItem i) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.event), title: Text(i.dueAt == null ? 'Set a date' : 'Change date (${Fmt.day(i.dueAt!)})'), onTap: () => Navigator.pop(ctx, 'date')),
          ListTile(leading: const Icon(Icons.notes), title: const Text('Notes'), onTap: () => Navigator.pop(ctx, 'notes')),
          ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Delete'), onTap: () => Navigator.pop(ctx, 'delete')),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'date') {
      final d = await showDatePicker(context: context, initialDate: i.dueAt ?? DateTime.now(), firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now().add(const Duration(days: 365 * 5)));
      if (d != null && mounted) await guard(context, () => sb.from('plan_items').update({'due_at': DateTime(d.year, d.month, d.day, 19).toUtc().toIso8601String()}).eq('id', i.id));
    } else if (action == 'notes') {
      final n = await promptText(context, title: 'Notes', initial: i.notes, maxLength: 2000, maxLines: 4);
      if (n != null && mounted) await guard(context, () => sb.from('plan_items').update({'notes': n.isEmpty ? null : n}).eq('id', i.id));
    } else if (action == 'delete') {
      await guard(context, () => sb.from('plan_items').delete().eq('id', i.id));
      ref.invalidate(planItemsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plans = ref.watch(plansProvider).valueOrNull ?? const [];
    final p = plans.where((x) => x.id == widget.planId).firstOrNull;
    final items = (ref.watch(planItemsProvider).valueOrNull ?? const []).where((i) => i.planId == widget.planId).toList();
    final nameOf = ref.watch(nameOfProvider);
    final partner = ref.watch(partnerProvider).valueOrNull;
    final t = Theme.of(context).textTheme;
    if (p == null) return Scaffold(appBar: AppBar(), body: const LoadingView());
    final open = items.where((i) => !i.done).toList();
    final done = items.where((i) => i.done).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text('${p.emoji ?? ''} ${p.title}'),
        actions: [
          IconButton(
            tooltip: 'Delete list',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final ok = await confirmDialog(context, title: 'Delete "${p.title}"?', message: 'All items will be removed for both of you.', confirm: 'Delete', destructive: true);
              if (!ok || !context.mounted) return;
              await guard(context, () => sb.from('plans').delete().eq('id', p.id));
              ref.invalidate(plansProvider);
              if (context.mounted) context.pop();
            },
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: items.isEmpty
              ? const EmptyState(emoji: '✨', title: 'Add your first idea', message: 'Both of you can add and tick things off.')
              : ListView(padding: const EdgeInsets.all(12), children: [
                  for (final i in [...open, ...done])
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: CheckboxListTile(
                        value: i.done,
                        onChanged: (_) => _toggle(i),
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(i.text, style: i.done ? t.bodyLarge?.copyWith(decoration: TextDecoration.lineThrough) : t.bodyLarge),
                        subtitle: Text(
                          [
                            if (i.privateTo != null) '🔒 Only you can see this',
                            if (i.dueAt != null) '📅 ${Fmt.day(i.dueAt!)}',
                            if (i.done) 'Done by ${nameOf(i.doneBy)}' else 'Added by ${nameOf(i.createdBy)}',
                            if (i.notes != null) i.notes!,
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        secondary: IconButton(tooltip: 'More', onPressed: () => _edit(i), icon: const Icon(Icons.more_vert)),
                      ),
                    ),
                ]),
        ),
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _add,
                      maxLength: 300,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _addItem(p),
                      decoration: const InputDecoration(hintText: 'Add an idea…', counterText: ''),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(tooltip: 'Add', onPressed: () => _addItem(p), icon: const Icon(Icons.add)),
                ]),
                if (p.category == 'gifts')
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: _private,
                    onChanged: (v) => setState(() => _private = v),
                    title: Text('Keep it a surprise (hidden from ${partner?.displayName ?? 'your partner'})'),
                  ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
