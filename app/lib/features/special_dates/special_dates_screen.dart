import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors.dart';
import '../../core/supabase.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../state/session.dart';

const _kinds = <String, (String, String)>{
  'anniversary': ('💍', 'Anniversary'),
  'first_date': ('🌹', 'First date'),
  'first_meeting': ('✨', 'First meeting'),
  'birthday': ('🎂', 'Birthday'),
  'custom': ('📅', 'Special day'),
};

class SpecialDatesScreen extends ConsumerWidget {
  const SpecialDatesScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, {SpecialDate? existing}) async {
    var kind = existing?.kind ?? 'anniversary';
    final title = TextEditingController(text: existing?.title ?? 'Our anniversary');
    var date = existing?.date ?? DateTime.now();
    var yearly = existing?.recursYearly ?? true;
    var remind = existing?.remind ?? true;
    final me = ref.read(myProfileProvider).valueOrNull;
    final partner = ref.read(partnerProvider).valueOrNull;
    String? person = existing?.personId;

    final existingId = existing?.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? 'Add a special date' : 'Edit special date'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final k in _kinds.entries)
                  ChoiceChip(
                    label: Text('${k.value.$1} ${k.value.$2}'),
                    selected: kind == k.key,
                    onSelected: (_) => setLocal(() {
                      kind = k.key;
                      if (existing == null) {
                        title.text = switch (k.key) {
                          'anniversary' => 'Our anniversary',
                          'first_date' => 'Our first date',
                          'first_meeting' => 'The day we met',
                          'birthday' => '${partner?.displayName ?? ''}\'s birthday',
                          _ => '',
                        };
                        if (k.key == 'birthday') person = partner?.id;
                      }
                    }),
                  ),
              ]),
              if (kind == 'birthday') ...[
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: [
                    if (me != null) ButtonSegment(value: me.id, label: const Text('Mine')),
                    if (partner != null) ButtonSegment(value: partner.id, label: Text(partner.displayName)),
                  ],
                  selected: {person ?? partner?.id ?? me?.id ?? ''},
                  onSelectionChanged: (s) => setLocal(() {
                    person = s.first;
                    title.text = person == me?.id ? 'My birthday' : '${partner?.displayName ?? ''}\'s birthday';
                  }),
                ),
              ],
              const SizedBox(height: 10),
              TextField(controller: title, maxLength: 80, decoration: const InputDecoration(labelText: 'Title')),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(Fmt.day(date)),
                onTap: () async {
                  final d = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(1940), lastDate: DateTime.now().add(const Duration(days: 365 * 10)));
                  if (d != null) setLocal(() => date = d);
                },
              ),
              SwitchListTile(contentPadding: EdgeInsets.zero, value: yearly, onChanged: (v) => setLocal(() => yearly = v), title: const Text('Every year')),
              SwitchListTile(contentPadding: EdgeInsets.zero, value: remind, onChanged: (v) => setLocal(() => remind = v), title: const Text('Gentle reminders'), subtitle: const Text('14, 7 and 1 day before')),
            ]),
          ),
          actions: [
            if (existing != null)
              TextButton(
                onPressed: () async {
                  final id = existingId!;
                  await guard(ctx, () => sb.from('special_dates').delete().eq('id', id));
                  if (ctx.mounted) Navigator.pop(ctx, true);
                },
                child: const Text('Delete'),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (title.text.trim().isEmpty) return;
                final fields = {
                  'kind': kind,
                  'title': title.text.trim(),
                  'date': DateFormat('yyyy-MM-dd').format(date),
                  'recurs_yearly': yearly,
                  'remind': remind,
                  'person_id': kind == 'birthday' ? person : null,
                };
                final res = await guard(ctx, () async {
                  if (existing == null) {
                    await sb.from('special_dates').insert({...fields, 'circle_id': ref.read(circleIdProvider), 'created_by': requireUserId()});
                  } else {
                    await sb.from('special_dates').update(fields).eq('id', existingId!);
                  }
                  return true;
                });
                if (res == true && ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) ref.invalidate(specialDatesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Special dates')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(context, ref), icon: const Icon(Icons.add), label: const Text('Add date')),
      body: AsyncView<List<SpecialDate>>(
        value: ref.watch(specialDatesProvider),
        onRetry: () => ref.invalidate(specialDatesProvider),
        data: (dates) => dates.isEmpty
            ? EmptyState(
                emoji: '🗓️',
                title: 'Remember what matters',
                message: 'Add your anniversary, birthdays and first date. Lovebird will count down with you.',
                action: FilledButton(onPressed: () => _edit(context, ref), child: const Text('Add your anniversary')),
              )
            : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
                Constrained(
                  child: Column(children: [
                    for (final d in dates)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: LBCard(
                          onTap: () => _edit(context, ref, existing: d),
                          child: Row(children: [
                            Text(_kinds[d.kind]?.$1 ?? '📅', style: const TextStyle(fontSize: 28)),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(d.title, style: t.titleMedium),
                                Text('${Fmt.day(d.date)}${d.recursYearly ? ' · every year' : ''}', style: t.bodySmall),
                              ]),
                            ),
                            if (d.daysUntil >= 0)
                              Text(d.daysUntil == 0 ? 'Today! 🎉' : '${d.daysUntil}d', style: t.titleMedium?.copyWith(color: Theme.of(context).colorScheme.primary)),
                          ]),
                        ),
                      ),
                  ]),
                ),
              ]),
      ),
    );
  }
}
