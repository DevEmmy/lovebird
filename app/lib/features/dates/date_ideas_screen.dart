import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/supabase.dart';
import '../../core/utils/locale_data.dart';
import '../../core/widgets/widgets.dart';
import '../../data/ai_repo.dart';
import '../../data/providers.dart';
import '../../state/session.dart';
import 'date_ideas_engine.dart';

class DateIdeasScreen extends ConsumerStatefulWidget {
  const DateIdeasScreen({super.key});
  @override
  ConsumerState<DateIdeasScreen> createState() => _DateIdeasScreenState();
}

class _DateIdeasScreenState extends ConsumerState<DateIdeasScreen> {
  final _budget = TextEditingController();
  final _location = TextEditingController();
  final _food = TextEditingController();
  String? _currency;
  int _minutes = 60;
  Distance _distance = Distance.longDistance;
  String _setting = 'any';
  String _mood = 'romantic';
  String _energy = 'medium';
  bool _spend = true;
  int _seed = 0;
  bool _aiLoading = false;
  List<Map<String, dynamic>>? _aiIdeas;
  bool _initFromQuery = false;

  DateQuery get _query => DateQuery(
        budget: double.tryParse(_budget.text.replaceAll(',', '')),
        currency: _currency ?? 'USD',
        location: _location.text,
        minutes: _minutes,
        distance: _distance,
        setting: _setting,
        mood: _mood,
        food: _food.text,
        energy: _energy,
        spendMoney: _spend,
      );

  Future<void> _askAi() async {
    setState(() {
      _aiLoading = true;
      _aiIdeas = null;
    });
    try {
      final r = await AiRepo.ask('date_ideas', {
        'budget': _budget.text,
        'currency': _currency,
        'location': _location.text,
        'long_distance': _distance == Distance.longDistance,
        'time': _minutes >= 480 ? 'a whole day' : '$_minutes minutes',
        'setting': _setting,
        'mood': _mood,
        'food': _food.text,
        'energy': _energy,
        'spend_money': _spend,
      });
      setState(() => _aiIdeas = ((r['ideas'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList());
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  Future<void> _saveToPlans(String title, String? notes) async {
    final cid = ref.read(circleIdProvider);
    var plan = await sb.from('plans').select('id').eq('circle_id', cid).eq('category', 'dates').limit(1).maybeSingle();
    plan ??= await sb.from('plans').insert({'circle_id': cid, 'title': 'Future dates', 'category': 'dates', 'emoji': '💡', 'created_by': requireUserId()}).select('id').single();
    await sb.from('plan_items').insert({'plan_id': plan['id'], 'circle_id': cid, 'text': title, 'notes': notes, 'created_by': requireUserId()});
    ref.invalidate(plansProvider);
    if (mounted) showToast(context, 'Added to Our Plans → Future dates');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    _currency ??= ref.watch(myProfileProvider).valueOrNull?.currencyCode ?? 'USD';
    if (!_initFromQuery) {
      _initFromQuery = true;
      final mood = GoRouterState.of(context).uri.queryParameters['mood'];
      if (mood != null) _mood = mood;
    }
    final ideas = DateIdeaEngine.suggest(_query, seed: _seed);
    return Scaffold(
      appBar: AppBar(title: const Text('Date Ideas 💡')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        Constrained(
          maxWidth: 760,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SegmentedButton<Distance>(
              segments: const [
                ButtonSegment(value: Distance.longDistance, label: Text('Apart'), icon: Icon(Icons.public)),
                ButtonSegment(value: Distance.nearby, label: Text('Together'), icon: Icon(Icons.people_alt_outlined)),
              ],
              selected: {_distance},
              onSelectionChanged: (s) => setState(() => _distance = s.first),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _budget,
                  enabled: _spend,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Budget (optional)'),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 110,
                child: DropdownButtonFormField<String>(
                  value: currencies.contains(_currency) ? _currency : 'USD',
                  decoration: const InputDecoration(labelText: 'Currency'),
                  items: [for (final c in currencies) DropdownMenuItem(value: c, child: Text(c))],
                  onChanged: (v) => setState(() => _currency = v),
                ),
              ),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: !_spend,
              onChanged: (v) => setState(() => _spend = !v),
              title: const Text('We don\'t want to spend money'),
            ),
            Text('How much time?', style: t.titleSmall),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in const [(30, '30 min'), (60, '1 hour'), (120, '2 hours'), (240, 'An evening'), (480, 'All day')])
                ChoiceChip(label: Text(m.$2), selected: _minutes == m.$1, onSelected: (_) => setState(() => _minutes = m.$1)),
            ]),
            const SizedBox(height: 14),
            Text('Vibe', style: t.titleSmall),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in const [('romantic', '❤️ Romantic'), ('funny', '😂 Funny'), ('adventurous', '🧭 Adventurous'), ('chill', '🛋️ Chill')])
                ChoiceChip(label: Text(m.$2), selected: _mood == m.$1, onSelected: (_) => setState(() => _mood = m.$1)),
            ]),
            const SizedBox(height: 14),
            Text('Energy & setting', style: t.titleSmall),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in const [('low', '😴 Low'), ('medium', '🙂 Medium'), ('high', '⚡ High')])
                ChoiceChip(label: Text(e.$2), selected: _energy == e.$1, onSelected: (_) => setState(() => _energy = e.$1)),
              for (final s in const [('any', 'Anywhere'), ('indoor', '🏠 Indoor'), ('outdoor', '🌳 Outdoor')])
                ChoiceChip(label: Text(s.$2), selected: _setting == s.$1, onSelected: (_) => setState(() => _setting = s.$1)),
            ]),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('More details (for AI ideas)'),
              children: [
                TextField(controller: _location, decoration: const InputDecoration(labelText: 'Where are you? e.g. "Lagos & Toronto"')),
                const SizedBox(height: 10),
                TextField(controller: _food, decoration: const InputDecoration(labelText: 'Food preferences')),
                const SizedBox(height: 10),
              ],
            ),
            const SizedBox(height: 4),
            FilledButton.icon(
              onPressed: _aiLoading ? null : _askAi,
              icon: _aiLoading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome),
              label: const Text('Personalised ideas with AI'),
            ),
            if (_aiIdeas != null) ...[
              const SectionHeader('Made for you two ✨'),
              if (_aiIdeas!.isEmpty) const Text('No ideas came back — try changing the details.'),
              for (final i in _aiIdeas!)
                _IdeaCard(
                  title: i['title'] as String? ?? 'Date idea',
                  summary: i['summary'] as String? ?? '',
                  steps: ((i['steps'] as List?) ?? const []).map((e) => '$e').toList(),
                  meta: '${i['estimated_cost'] ?? ''} · ${i['duration'] ?? ''}',
                  onSave: () => guard(context, () => _saveToPlans(i['title'] as String? ?? 'Date idea', i['summary'] as String?)),
                ),
            ],
            SectionHeader('Ideas for you', action: 'Shuffle', onAction: () => setState(() => _seed++)),
            if (ideas.isEmpty)
              const EmptyState(emoji: '🤔', title: 'Nothing fits exactly', message: 'Try more time, a bigger budget, or a different vibe.')
            else
              for (final i in ideas)
                _IdeaCard(
                  title: i.title,
                  summary: i.summary,
                  steps: i.steps,
                  meta: '${i.costLabel(_currency ?? 'USD')} · ~${i.minutes >= 60 ? '${(i.minutes / 60).toStringAsFixed(i.minutes % 60 == 0 ? 0 : 1)}h' : '${i.minutes} min'}',
                  onOpen: i.route == null ? null : () => context.push(i.route!),
                  onSave: () => guard(context, () => _saveToPlans(i.title, i.summary)),
                ),
          ]),
        ),
      ]),
    );
  }
}

class _IdeaCard extends StatelessWidget {
  const _IdeaCard({required this.title, required this.summary, required this.steps, required this.meta, required this.onSave, this.onOpen});
  final String title;
  final String summary;
  final List<String> steps;
  final String meta;
  final VoidCallback onSave;
  final VoidCallback? onOpen;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LBCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: t.titleMedium),
          const SizedBox(height: 2),
          Text(meta, style: t.labelMedium),
          const SizedBox(height: 8),
          Text(summary, style: t.bodyMedium),
          if (steps.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (var i = 0; i < steps.length; i++) Text('${i + 1}. ${steps[i]}', style: t.bodySmall?.copyWith(color: t.bodyMedium?.color)),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            if (onOpen != null) FilledButton.tonal(onPressed: onOpen, child: const Text('Do it now')),
            TextButton.icon(onPressed: onSave, icon: const Icon(Icons.bookmark_add_outlined), label: const Text('Save to plans')),
          ]),
        ]),
      ),
    );
  }
}
