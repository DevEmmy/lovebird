import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/supabase.dart';
import '../../core/theme/colors.dart';
import '../../core/utils/format.dart';
import '../../core/utils/locale_data.dart';
import '../../core/widgets/widgets.dart';
import '../../data/media_repo.dart';
import '../../data/models.dart';
import '../../services/payments_service.dart';
import '../../state/session.dart';
import 'competition_repo.dart';

const _phases = [
  ('announced', 'Announcement'),
  ('registration', 'Registration'),
  ('review', 'Submission review'),
  ('finalists', 'Finalists announced'),
  ('voting', 'Voting & judging'),
  ('winner', 'Winner announced'),
  ('celebration', 'Celebration'),
];

class CompetitionScreen extends ConsumerWidget {
  const CompetitionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Couple of the Year 🏆')),
      body: AsyncView<Competition?>(
        value: ref.watch(currentCompetitionProvider),
        onRetry: () => ref.invalidate(currentCompetitionProvider),
        data: (c) {
          if (c == null) {
            return const EmptyState(
              emoji: '🏆',
              title: 'Nothing announced yet',
              message: 'Lovebird Couple of the Year is an optional celebration near the end of each year. We\'ll let you know when it opens.',
            );
          }
          final me = ref.watch(myProfileProvider).valueOrNull;
          final entry = ref.watch(myEntryProvider).valueOrNull;
          final isJudge = ref.watch(isJudgeProvider(c.id)).valueOrNull ?? false;
          final fee = c.feeFor(me?.currencyCode);
          final eligibleCountry = me?.countryCode != null && c.allowedCountries.contains(me!.countryCode);
          final phaseIndex = _phases.indexWhere((p) => p.$1 == c.status);

          return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 40), children: [
            Constrained(
              maxWidth: 760,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                LBCard(
                  gradient: const LinearGradient(colors: [Color(0xFF8E0E43), Color(0xFFC2185B), Color(0xFFE8B04B)]),
                  padding: const EdgeInsets.all(22),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.title, style: t.headlineSmall?.copyWith(color: Colors.white)),
                    const SizedBox(height: 6),
                    Text(c.description.isEmpty ? 'A celebration of love, friendship, creativity and the stories couples build together on Lovebird.' : c.description,
                        style: t.bodyMedium?.copyWith(color: Colors.white)),
                    const SizedBox(height: 10),
                    Text('Taking part is completely optional. It celebrates stories — it never ranks whose relationship is "better".',
                        style: t.bodySmall?.copyWith(color: Colors.white)),
                  ]),
                ),
                const SectionHeader('Timeline'),
                for (var i = 0; i < _phases.length; i++)
                  Row(children: [
                    Icon(
                      i < phaseIndex ? Icons.check_circle : (i == phaseIndex ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                      color: i <= phaseIndex ? LBColors.rose : Theme.of(context).colorScheme.outline,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(_phases[i].$2, style: i == phaseIndex ? t.titleSmall : t.bodyMedium))),
                  ]),
                const SectionHeader('Before you enter'),
                _Fact('Entry fee', fee == null || fee.amountMinor == 0 ? 'Free' : Fmt.money(fee.amountMinor, fee.currency)),
                if (c.freeEntryAvailable && fee != null && fee.amountMinor > 0) const _Fact('Free entry', 'A free way to enter is available — see terms.'),
                _Fact('Registration', '${c.registrationOpens == null ? 'TBA' : Fmt.day(c.registrationOpens!)} – ${c.registrationCloses == null ? 'TBA' : Fmt.day(c.registrationCloses!)}'),
                if (c.votingOpens != null) _Fact('Voting', '${Fmt.day(c.votingOpens!)} – ${c.votingCloses == null ? 'TBA' : Fmt.day(c.votingCloses!)}'),
                if (c.winnerAnnounceAt != null) _Fact('Winner announced', Fmt.day(c.winnerAnnounceAt!)),
                _Fact('Number of winners', '${c.numberOfWinners}'),
                _Fact('How winners are chosen', c.methodLabel),
                _Fact('Eligibility', '${c.minAge}+ · both partners must consent · available in ${c.allowedCountries.isEmpty ? 'no countries yet' : c.allowedCountries.map(countryName).join(', ')}'),
                const SectionHeader('Prizes'),
                if (c.prizes.isEmpty) const Text('To be announced.'),
                for (final p in c.prizes)
                  _Fact(
                    p.rank == 1 ? '🥇 Winner' : '#${p.rank}',
                    '${p.title}${p.cashAmountMinor != null && p.cashCurrency != null ? ' · ${Fmt.money(p.cashAmountMinor!, p.cashCurrency!)}' : ''}${p.description.isEmpty ? '' : '\n${p.description}'}',
                  ),
                if (c.selectionMethod != 'community') ...[
                  const SectionHeader('Judging criteria'),
                  for (final cr in c.criteria) _Fact(cr['label'] as String? ?? '', '${cr['weight']}%'),
                ],
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Terms & conditions'),
                  children: [Padding(padding: const EdgeInsets.only(bottom: 12), child: SelectableText(c.termsMd.isEmpty ? 'Terms will be published before registration opens.' : c.termsMd))],
                ),
                const SizedBox(height: 12),
                if (entry != null)
                  _EntryStatusCard(entry: entry, competition: c)
                else if (c.registrationOpen)
                  FilledButton(
                    onPressed: eligibleCountry ? () => context.push('/competition/enter') : null,
                    child: Text(eligibleCountry ? 'Enter our story' : 'Not available in your country yet'),
                  ),
                if (c.status == 'finalists' || c.status == 'voting' || c.status == 'winner' || c.status == 'celebration') ...[
                  const SizedBox(height: 10),
                  OutlinedButton(onPressed: () => context.push('/competition/finalists'), child: Text(c.votingOpen ? 'Meet the finalists & vote' : 'Meet the finalists')),
                ],
                if (isJudge) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(onPressed: () => context.push('/competition/judge'), icon: const Icon(Icons.gavel_rounded), label: const Text('Judge entries')),
                ],
              ]),
            ),
          ]);
        },
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 150, child: Text(label, style: Theme.of(context).textTheme.labelMedium)),
          Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyMedium)),
        ]),
      );
}

class _EntryStatusCard extends ConsumerWidget {
  const _EntryStatusCard({required this.entry, required this.competition});
  final CompetitionEntry entry;
  final Competition competition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(userIdProvider)!;
    final partner = ref.watch(partnerProvider).valueOrNull;
    final t = Theme.of(context).textTheme;
    final iConsented = entry.consentedBy(uid);
    final label = switch (entry.status) {
      'draft' => 'Draft — not submitted yet',
      'awaiting_consent' => iConsented ? 'Waiting for ${partner?.displayName ?? 'your partner'} to consent' : 'Your consent is needed',
      'pending_payment' => 'Entry fee pending',
      'submitted' => 'Submitted ✓ — good luck!',
      'under_review' => 'Under review',
      'finalist' => '🏆 You\'re a finalist!',
      'winner' => '🏆 Lovebird Couple of the Year!',
      'rejected' => 'Not selected this year — thank you for sharing your story ❤️',
      'withdrawn' => 'Withdrawn',
      _ => entry.status,
    };
    final editable = entry.status == 'draft' || entry.status == 'awaiting_consent';
    return LBCard(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Our entry: ${entry.coupleName}', style: t.titleMedium),
        const SizedBox(height: 4),
        Text(label, style: t.bodyLarge),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (editable) OutlinedButton(onPressed: () => context.push('/competition/enter'), child: const Text('Review entry')),
          if (editable && !iConsented) FilledButton(onPressed: () => context.push('/competition/enter'), child: const Text('Give consent')),
          if (entry.status == 'pending_payment')
            FilledButton(
              onPressed: () async {
                final r = await payments.payCompetitionEntry(entryId: entry.id, currency: entry.feeCurrency ?? 'USD', amountMinor: entry.feeAmountMinor ?? 0);
                if (context.mounted && r.message != null) showToast(context, r.message!);
              },
              child: Text('Pay ${Fmt.money(entry.feeAmountMinor ?? 0, entry.feeCurrency ?? 'USD')}'),
            ),
          if (iConsented && entry.status != 'withdrawn' && entry.status != 'winner')
            TextButton(
              onPressed: () async {
                final ok = await confirmDialog(context, title: 'Withdraw consent?', message: 'Your entry will be hidden and won\'t be considered unless you both consent again.', confirm: 'Withdraw');
                if (!ok || !context.mounted) return;
                await guard(context, () async {
                  await CompetitionRepo.withdrawConsent(entry.id);
                  if (editable) await CompetitionRepo.withdrawEntry(entry.id);
                });
                ref.invalidate(myEntryProvider);
              },
              child: const Text('Withdraw'),
            ),
        ]),
      ]),
    );
  }
}

class CompetitionEntryScreen extends ConsumerStatefulWidget {
  const CompetitionEntryScreen({super.key});
  @override
  ConsumerState<CompetitionEntryScreen> createState() => _CompetitionEntryScreenState();
}

class _CompetitionEntryScreenState extends ConsumerState<CompetitionEntryScreen> {
  final _name = TextEditingController();
  final _story = TextEditingController();
  final _met = TextEditingController();
  final _activity = TextEditingController();
  final _memory = TextEditingController();
  final _why = TextEditingController();
  List<String> _photos = [];
  bool _public = false;
  bool _terms = false;
  bool _loaded = false;
  bool _busy = false;

  void _load(CompetitionEntry? e) {
    if (_loaded) return;
    _loaded = true;
    if (e == null) {
      final me = ref.read(myProfileProvider).valueOrNull;
      final partner = ref.read(partnerProvider).valueOrNull;
      _name.text = ref.read(circleProvider).valueOrNull?.coupleName ?? '${me?.displayName ?? ''} & ${partner?.displayName ?? ''}';
      return;
    }
    _name.text = e.coupleName;
    _story.text = e.story;
    _met.text = e.howWeMet;
    _activity.text = e.favoriteActivity;
    _memory.text = e.favoriteMemory;
    _why.text = e.whyLovebird;
    _photos = List.of(e.photoPaths);
  }

  Map<String, dynamic> get _fields => {
        'couple_name': _name.text.trim(),
        'story': _story.text.trim(),
        'how_we_met': _met.text.trim(),
        'favorite_activity': _activity.text.trim(),
        'favorite_memory': _memory.text.trim(),
        'why_lovebird': _why.text.trim(),
        'photo_paths': _photos,
      };

  Future<String> _ensureEntry(Competition c, CompetitionEntry? e) async {
    if (e != null) {
      await CompetitionRepo.updateEntry(e.id, _fields);
      return e.id;
    }
    return CompetitionRepo.createEntry(c.id, ref.read(circleIdProvider), _fields);
  }

  Future<void> _submit(Competition c, CompetitionEntry? e) async {
    if (_name.text.trim().isEmpty || _story.text.trim().length < 40) {
      return showToast(context, 'Please add your couple name and at least a few sentences of your story.');
    }
    if (!_terms) return showToast(context, 'Please agree to the terms first.');
    setState(() => _busy = true);
    try {
      final id = await _ensureEntry(c, e);
      final status = await CompetitionRepo.consent(id, publicApproved: _public);
      ref.invalidate(myEntryProvider);
      if (!mounted) return;
      showToast(
        context,
        switch (status) {
          'awaiting_consent' => 'Saved! Your partner needs to consent too.',
          'pending_payment' => 'Both of you consented. Entry fee pending.',
          _ => 'Entry submitted 🎉',
        },
      );
      context.pop();
    } catch (err) {
      if (mounted) showError(context, err);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(currentCompetitionProvider).valueOrNull;
    final entryAsync = ref.watch(myEntryProvider);
    if (c == null || entryAsync.isLoading) return const Scaffold(body: LoadingView());
    final e = entryAsync.valueOrNull;
    _load(e);
    final partner = ref.watch(partnerProvider).valueOrNull;
    final t = Theme.of(context).textTheme;
    final partnerConsented = e != null && partner != null && e.consentedBy(partner.id);

    InputDecoration dec(String l, [String? h]) => InputDecoration(labelText: l, hintText: h, alignLabelWithHint: true);

    return Scaffold(
      appBar: AppBar(title: const Text('Our entry')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Constrained(
          maxWidth: 680,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (partnerConsented)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: LBCard(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Text('${partner!.displayName} already consented to this entry. If you change the text or photos, they\'ll need to consent again.'),
                ),
              ),
            Text('Nothing here is published automatically. Only finalists\' approved details appear publicly, and only if you BOTH allow it.', style: t.bodySmall),
            const SizedBox(height: 16),
            TextField(controller: _name, maxLength: 80, decoration: dec('Couple name')),
            TextField(controller: _story, minLines: 5, maxLines: 12, maxLength: 5000, decoration: dec('Our story')),
            TextField(controller: _met, minLines: 2, maxLines: 6, maxLength: 2000, decoration: dec('How we met')),
            TextField(controller: _activity, maxLength: 200, decoration: dec('Favourite Lovebird activity', 'e.g. Movie Night 🎬')),
            TextField(controller: _memory, minLines: 2, maxLines: 6, maxLength: 2000, decoration: dec('Favourite memory')),
            TextField(controller: _why, minLines: 2, maxLines: 6, maxLength: 2000, decoration: dec('Why our story represents Lovebird')),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in _photos)
                Stack(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(12), child: StorageImage(p, bucket: 'competition', width: 90, height: 90)),
                  Positioned(right: 0, top: 0, child: IconButton(tooltip: 'Remove', icon: const Icon(Icons.close, size: 16), onPressed: () => setState(() => _photos.remove(p)))),
                ]),
              if (_photos.length < 4)
                OutlinedButton.icon(
                  onPressed: () async {
                    final files = await MediaRepo.instance.pickPhotos(multiple: false);
                    if (files.isEmpty || !context.mounted) return;
                    await guard(context, () async {
                      final id = await _ensureEntry(c, e);
                      final path = await MediaRepo.instance.uploadCompetitionPhoto(id, files.first);
                      setState(() => _photos.add(path));
                      await CompetitionRepo.updateEntry(id, {'photo_paths': _photos});
                      ref.invalidate(myEntryProvider);
                    });
                  },
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Add an approved photo'),
                ),
            ]),
            const SizedBox(height: 16),
            CheckboxListTile(
              value: _public,
              onChanged: (v) => setState(() => _public = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('If we\'re finalists, I allow this entry (text + photos above) to be shown publicly during the competition.'),
            ),
            CheckboxListTile(
              value: _terms,
              onChanged: (v) => setState(() => _terms = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text('I\'m ${c.minAge}+ and agree to the ${c.year} terms, fee, prize and selection method shown on the previous page.'),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _busy ? null : () => _submit(c, e), child: const Text('I consent — submit our entry')),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => guard(context, () async {
                        await _ensureEntry(c, e);
                        ref.invalidate(myEntryProvider);
                        if (context.mounted) showToast(context, 'Draft saved');
                      }),
              child: const Text('Save draft'),
            ),
          ]),
        ),
      ]),
    );
  }
}

class FinalistsScreen extends ConsumerWidget {
  const FinalistsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(currentCompetitionProvider).valueOrNull;
    final t = Theme.of(context).textTheme;
    if (c == null) return const Scaffold(body: LoadingView());
    final myVote = ref.watch(myVoteProvider(c.id)).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Finalists')),
      body: AsyncView<List<Finalist>>(
        value: ref.watch(finalistsProvider(c.id)),
        onRetry: () => ref.invalidate(finalistsProvider(c.id)),
        data: (list) => list.isEmpty
            ? const EmptyState(emoji: '🏆', title: 'Finalists coming soon')
            : ListView(padding: const EdgeInsets.all(16), children: [
                Constrained(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (c.votingOpen)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text('You have one vote this year. Votes can\'t be bought, and you can\'t vote for yourselves.', style: t.bodySmall),
                      ),
                    for (final f in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: LBCard(
                          padding: EdgeInsets.zero,
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            if (f.photoPaths.isNotEmpty)
                              ClipRRect(
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                                child: SizedBox(height: 220, child: StorageImage(f.photoPaths.first, bucket: 'competition')),
                              ),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('❤️ ${f.coupleName}', style: t.headlineSmall),
                                PillTag(f.status == 'winner' ? '🏆 Couple of the Year' : '🏆 Couple of the Year Finalist'),
                                const SizedBox(height: 10),
                                Text('Our Story', style: t.titleSmall),
                                Text(f.story),
                                if (f.favoriteActivity.isNotEmpty) ...[const SizedBox(height: 8), Text('Our Favourite Lovebird Activity', style: t.titleSmall), Text(f.favoriteActivity)],
                                if (f.favoriteMemory.isNotEmpty) ...[const SizedBox(height: 8), Text('Our Favourite Memory', style: t.titleSmall), Text(f.favoriteMemory)],
                                if (f.votes != null) ...[const SizedBox(height: 8), Text('${f.votes} votes', style: t.labelMedium)],
                                if (c.votingOpen) ...[
                                  const SizedBox(height: 12),
                                  if (myVote == f.entryId)
                                    const PillTag('✓ Your vote')
                                  else if (myVote == null)
                                    AsyncButton(
                                      onPressed: () async {
                                        await CompetitionRepo.vote(f.entryId);
                                        ref.invalidate(myVoteProvider(c.id));
                                        if (context.mounted) showToast(context, 'Vote cast ❤️');
                                      },
                                      child: const Text('Vote for us'),
                                    ),
                                ],
                                const SizedBox(height: 4),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () => context.push('/report', extra: {'type': 'competition_entry', 'entry_id': f.entryId}),
                                    child: const Text('Report'),
                                  ),
                                ),
                              ]),
                            ),
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

final _judgeEntriesProvider = FutureProvider.autoDispose.family<List<CompetitionEntry>, String>((ref, compId) async {
  final rows = await sb.from('competition_entries').select().eq('competition_id', compId).inFilter('status', ['submitted', 'under_review', 'finalist']);
  return rows.map(CompetitionEntry.fromJson).toList();
});

class JudgeScreen extends ConsumerWidget {
  const JudgeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(currentCompetitionProvider).valueOrNull;
    if (c == null) return const Scaffold(body: LoadingView());
    return Scaffold(
      appBar: AppBar(title: const Text('Judge entries')),
      body: AsyncView<List<CompetitionEntry>>(
        value: ref.watch(_judgeEntriesProvider(c.id)),
        data: (entries) => entries.isEmpty
            ? const EmptyState(emoji: '⚖️', title: 'No entries to judge yet')
            : ListView(padding: const EdgeInsets.all(16), children: [for (final e in entries) _ScoreCard(c: c, e: e)]),
      ),
    );
  }
}

class _ScoreCard extends StatefulWidget {
  const _ScoreCard({required this.c, required this.e});
  final Competition c;
  final CompetitionEntry e;
  @override
  State<_ScoreCard> createState() => _ScoreCardState();
}

class _ScoreCardState extends State<_ScoreCard> {
  late final Map<String, int> _scores = {for (final cr in widget.c.criteria) cr['key'] as String: 5};
  final _comment = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: LBCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.e.coupleName, style: t.titleLarge),
          const SizedBox(height: 6),
          Text(widget.e.story),
          const Divider(height: 24),
          for (final cr in widget.c.criteria) ...[
            Text('${cr['label']} (${cr['weight']}%) — ${_scores[cr['key']]}/10', style: t.labelLarge),
            Slider(
              value: (_scores[cr['key']] ?? 5).toDouble(),
              min: 0,
              max: 10,
              divisions: 10,
              onChanged: (v) => setState(() => _scores[cr['key'] as String] = v.round()),
            ),
          ],
          TextField(controller: _comment, decoration: const InputDecoration(labelText: 'Comment (private to admins)')),
          const SizedBox(height: 8),
          AsyncButton(
            onPressed: () async {
              await CompetitionRepo.score(widget.c.id, widget.e.id, _scores, _comment.text.trim().isEmpty ? null : _comment.text.trim());
              if (context.mounted) showToast(context, 'Score saved');
            },
            child: const Text('Save score'),
          ),
        ]),
      ),
    );
  }
}
