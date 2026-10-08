import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors.dart';
import '../../core/supabase.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../../state/session.dart';

/// Admin console. Every action here is ALSO enforced by RLS (`is_admin()`),
/// and admins have no access to couples' private content by design.
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);
    return isAdmin.when(
      loading: () => const Scaffold(body: LoadingView()),
      error: (e, _) => Scaffold(appBar: AppBar(), body: ErrorView(error: e)),
      data: (ok) => !ok
          ? Scaffold(appBar: AppBar(), body: const EmptyState(emoji: '🔒', title: 'Admins only'))
          : DefaultTabController(
              length: 4,
              child: Scaffold(
                appBar: AppBar(
                  title: const Text('Admin'),
                  bottom: const TabBar(isScrollable: true, tabs: [
                    Tab(text: 'Reports'),
                    Tab(text: 'Couple of the Year'),
                    Tab(text: 'Library'),
                    Tab(text: 'Announcements'),
                  ]),
                ),
                body: const TabBarView(children: [_ReportsTab(), _CompetitionTab(), _LibraryTab(), _AnnouncementsTab()]),
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------- Reports
final _reportsProvider = FutureProvider.autoDispose<List<Report>>((ref) async {
  final rows = await sb.from('reports').select().order('created_at', ascending: false).limit(200);
  return rows.map(Report.fromJson).toList();
});

class _ReportsTab extends ConsumerWidget {
  const _ReportsTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView<List<Report>>(
      value: ref.watch(_reportsProvider),
      onRetry: () => ref.invalidate(_reportsProvider),
      data: (list) => list.isEmpty
          ? const EmptyState(emoji: '🛡️', title: 'No reports')
          : ListView(children: [
              for (final r in list)
                ListTile(
                  leading: Icon(r.status == 'open' ? Icons.error_outline : Icons.check_circle_outline),
                  title: Text('${r.category} · ${r.status}'),
                  subtitle: Text('${Fmt.relative(r.createdAt)} · ${r.description}', maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () => _open(context, ref, r),
                ),
            ]),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref, Report r) async {
    var status = r.status;
    final notes = TextEditingController(text: r.adminNotes);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Report: ${r.category}'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.description),
                const SizedBox(height: 12),
                const Text('Snapshot shared by reporter:', style: TextStyle(fontWeight: FontWeight.w700)),
                SelectableText(r.snapshot.isEmpty ? '(none)' : const JsonEncoder.withIndent('  ').convert(r.snapshot)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: 'open', child: Text('Open')),
                    DropdownMenuItem(value: 'reviewing', child: Text('Reviewing')),
                    DropdownMenuItem(value: 'resolved', child: Text('Resolved')),
                    DropdownMenuItem(value: 'dismissed', child: Text('Dismissed')),
                  ],
                  onChanged: (v) => setLocal(() => status = v ?? status),
                ),
                const SizedBox(height: 8),
                TextField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Admin notes')),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Close')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    await guard(context, () => sb.from('reports').update({
          'status': status,
          'admin_notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
          if (status == 'resolved' || status == 'dismissed') 'resolved_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', r.id));
    ref.invalidate(_reportsProvider);
  }
}

// ---------------------------------------------------------------- Competition
final _adminCompsProvider = FutureProvider.autoDispose<List<Competition>>((ref) async {
  final rows = await sb.from('competitions').select('*, competition_fees(*), competition_prizes(*)').order('year', ascending: false);
  return rows.map(Competition.fromJson).toList();
});

final _adminEntriesProvider = FutureProvider.autoDispose.family<List<CompetitionEntry>, String>((ref, compId) async {
  final rows = await sb.from('competition_entries').select('*, competition_consents(*)').eq('competition_id', compId).order('created_at');
  return rows.map(CompetitionEntry.fromJson).toList();
});

class _CompetitionTab extends ConsumerWidget {
  const _CompetitionTab();

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final year = await promptText(context, title: 'Competition year', initial: '${DateTime.now().year}', maxLength: 4);
    final y = int.tryParse(year ?? '');
    if (y == null || !context.mounted) return;
    await guard(context, () => sb.from('competitions').insert({'year': y, 'title': 'Lovebird Couple of the Year $y'}));
    ref.invalidate(_adminCompsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _create(context, ref), icon: const Icon(Icons.add), label: const Text('New year')),
      body: AsyncView<List<Competition>>(
        value: ref.watch(_adminCompsProvider),
        onRetry: () => ref.invalidate(_adminCompsProvider),
        data: (list) => ListView(padding: const EdgeInsets.all(12), children: [
          for (final c in list) _CompetitionEditor(c: c),
          const SizedBox(height: 80),
        ]),
      ),
    );
  }
}

class _CompetitionEditor extends ConsumerStatefulWidget {
  const _CompetitionEditor({required this.c});
  final Competition c;
  @override
  ConsumerState<_CompetitionEditor> createState() => _CompetitionEditorState();
}

class _CompetitionEditorState extends ConsumerState<_CompetitionEditor> {
  late String _status = widget.c.status;
  late String _method = widget.c.selectionMethod;
  late double _judgeWeight = widget.c.judgeWeight;
  late final _desc = TextEditingController(text: widget.c.description);
  late final _terms = TextEditingController(text: widget.c.termsMd);
  late final _countries = TextEditingController(text: widget.c.allowedCountries.join(', '));
  late final _winners = TextEditingController(text: '${widget.c.numberOfWinners}');
  late bool _freeEntry = widget.c.freeEntryAvailable;
  late DateTime? _regOpen = widget.c.registrationOpens;
  late DateTime? _regClose = widget.c.registrationCloses;
  late DateTime? _voteOpen = widget.c.votingOpens;
  late DateTime? _voteClose = widget.c.votingCloses;
  late DateTime? _winnerAt = widget.c.winnerAnnounceAt;
  late DateTime? _celebrateEnd = widget.c.celebrationEndsAt;

  static const statuses = ['draft', 'announced', 'registration', 'review', 'finalists', 'voting', 'winner', 'celebration', 'closed'];

  Widget _dateField(String label, DateTime? value, ValueChanged<DateTime?> onSet) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        subtitle: Text(value == null ? 'Not set' : DateFormat.yMMMd().add_jm().format(value.toLocal())),
        trailing: const Icon(Icons.edit_calendar_outlined),
        onTap: () async {
          final d = await showDatePicker(context: context, initialDate: value ?? DateTime.now(), firstDate: DateTime(2024), lastDate: DateTime(2100));
          if (d == null || !mounted) return;
          onSet(DateTime(d.year, d.month, d.day, 12));
        },
      );

  Future<void> _save() async {
    await guard(context, () => sb.from('competitions').update({
          'status': _status,
          'selection_method': _method,
          'judge_weight': _judgeWeight,
          'description': _desc.text,
          'terms_md': _terms.text,
          'allowed_countries': _countries.text.split(',').map((s) => s.trim().toUpperCase()).where((s) => s.length == 2).toList(),
          'number_of_winners': int.tryParse(_winners.text) ?? 1,
          'free_entry_available': _freeEntry,
          'registration_opens': _regOpen?.toUtc().toIso8601String(),
          'registration_closes': _regClose?.toUtc().toIso8601String(),
          'voting_opens': _voteOpen?.toUtc().toIso8601String(),
          'voting_closes': _voteClose?.toUtc().toIso8601String(),
          'winner_announce_at': _winnerAt?.toUtc().toIso8601String(),
          'celebration_ends_at': _celebrateEnd?.toUtc().toIso8601String(),
        }).eq('id', widget.c.id));
    ref.invalidate(_adminCompsProvider);
    if (mounted) showToast(context, 'Saved');
  }

  Future<void> _addFee() async {
    final cur = await promptText(context, title: 'Currency (ISO, e.g. NGN)', maxLength: 3);
    if (cur == null || cur.length != 3 || !mounted) return;
    final amt = await promptText(context, title: 'Amount in minor units (kobo/cents). 0 = free', maxLength: 12);
    final n = int.tryParse(amt ?? '');
    if (n == null || !mounted) return;
    await guard(context, () => sb.from('competition_fees').upsert({'competition_id': widget.c.id, 'currency': cur.toUpperCase(), 'amount_minor': n}));
    ref.invalidate(_adminCompsProvider);
  }

  Future<void> _addPrize() async {
    final title = await promptText(context, title: 'Prize title', maxLength: 120);
    if (title == null || title.isEmpty || !mounted) return;
    final desc = await promptText(context, title: 'Prize description', maxLength: 500, maxLines: 3);
    if (!mounted) return;
    await guard(context, () => sb.from('competition_prizes').insert({
          'competition_id': widget.c.id,
          'rank': widget.c.prizes.length + 1,
          'title': title,
          'description': desc ?? '',
        }));
    ref.invalidate(_adminCompsProvider);
  }

  Future<void> _addJudge() async {
    final id = await promptText(context, title: 'Judge user ID (UUID)', maxLength: 36);
    if (id == null || id.length != 36 || !mounted) return;
    final name = await promptText(context, title: 'Judge display name', maxLength: 80);
    if (name == null || !mounted) return;
    await guard(context, () => sb.from('competition_judges').insert({'competition_id': widget.c.id, 'user_id': id, 'display_name': name}));
    if (mounted) showToast(context, 'Judge added');
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final t = Theme.of(context).textTheme;
    final entries = ref.watch(_adminEntriesProvider(c.id));
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        title: Text('${c.year} · ${c.title}'),
        subtitle: Text('Status: ${c.status}'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          DropdownButtonFormField<String>(
            value: _status,
            decoration: const InputDecoration(labelText: 'Phase'),
            items: [for (final s in statuses) DropdownMenuItem(value: s, child: Text(s))],
            onChanged: (v) => setState(() => _status = v ?? _status),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _method,
            decoration: const InputDecoration(labelText: 'Winner selection'),
            items: const [
              DropdownMenuItem(value: 'judges', child: Text('Judges')),
              DropdownMenuItem(value: 'community', child: Text('Community voting')),
              DropdownMenuItem(value: 'hybrid', child: Text('Hybrid')),
            ],
            onChanged: (v) => setState(() => _method = v ?? _method),
          ),
          if (_method == 'hybrid') ...[
            Text('Judge weight: ${(_judgeWeight * 100).round()}%', style: t.labelMedium),
            Slider(value: _judgeWeight, divisions: 20, onChanged: (v) => setState(() => _judgeWeight = v)),
          ],
          TextField(controller: _desc, maxLines: 3, decoration: const InputDecoration(labelText: 'Description')),
          const SizedBox(height: 8),
          TextField(controller: _countries, decoration: const InputDecoration(labelText: 'Allowed countries (ISO codes, comma-separated)', helperText: 'Only list countries where legal review has cleared this promotion.')),
          const SizedBox(height: 8),
          TextField(controller: _winners, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Number of winners')),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: _freeEntry, onChanged: (v) => setState(() => _freeEntry = v), title: const Text('Free alternative entry available')),
          _dateField('Registration opens', _regOpen, (d) => setState(() => _regOpen = d)),
          _dateField('Registration closes', _regClose, (d) => setState(() => _regClose = d)),
          _dateField('Voting opens', _voteOpen, (d) => setState(() => _voteOpen = d)),
          _dateField('Voting closes', _voteClose, (d) => setState(() => _voteClose = d)),
          _dateField('Winner announced', _winnerAt, (d) => setState(() => _winnerAt = d)),
          _dateField('Celebration ends', _celebrateEnd, (d) => setState(() => _celebrateEnd = d)),
          TextField(controller: _terms, minLines: 4, maxLines: 12, decoration: const InputDecoration(labelText: 'Terms & conditions (published before entry)', alignLabelWithHint: true)),
          const SizedBox(height: 12),
          Text('Fees: ${c.fees.isEmpty ? 'none (free)' : c.fees.map((f) => Fmt.money(f.amountMinor, f.currency)).join(' · ')}', style: t.bodyMedium),
          Text('Prizes: ${c.prizes.isEmpty ? 'none yet' : c.prizes.map((p) => p.title).join(' · ')}', style: t.bodyMedium),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton(onPressed: _save, child: const Text('Save')),
            OutlinedButton(onPressed: _addFee, child: const Text('Set fee')),
            OutlinedButton(onPressed: _addPrize, child: const Text('Add prize')),
            OutlinedButton(onPressed: _addJudge, child: const Text('Add judge')),
            OutlinedButton(
              onPressed: () => guard(context, () async {
                final rows = await sb.rpc('compute_competition_results', params: {'p_comp': c.id}) as List;
                ref.invalidate(_adminEntriesProvider(c.id));
                if (context.mounted) showToast(context, 'Scored ${rows.length} finalists');
              }),
              child: const Text('Compute results'),
            ),
          ]),
          const Divider(height: 28),
          Text('Entries', style: t.titleMedium),
          entries.when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(error: e),
            data: (list) => Column(children: [
              if (list.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('No entries yet')),
              for (final e in list)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.coupleName),
                  subtitle: Text('${e.status} · consents ${e.consents.length}/2 · payment ${e.paymentStatus}${e.finalScore != null ? ' · score ${e.finalScore}' : ''}'),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Set status',
                    onSelected: (s) => guard(context, () async {
                      await sb.from('competition_entries').update({'status': s}).eq('id', e.id);
                      ref.invalidate(_adminEntriesProvider(c.id));
                    }),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'under_review', child: Text('Under review')),
                      PopupMenuItem(value: 'finalist', child: Text('Make finalist')),
                      PopupMenuItem(value: 'rejected', child: Text('Not selected')),
                      PopupMenuItem(value: 'winner', child: Text('Winner 🏆')),
                    ],
                  ),
                ),
            ]),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Library
final _adminBooksProvider = FutureProvider.autoDispose<List<Book>>((ref) async {
  final rows = await sb.from('books').select('*, book_chapters(count)').isFilter('circle_id', null).order('created_at');
  return rows.map(Book.fromJson).toList();
});

class _LibraryTab extends ConsumerWidget {
  const _LibraryTab();

  Future<void> _addBook(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    final author = TextEditingController();
    final desc = TextEditingController();
    final ref0 = TextEditingController();
    var license = 'original';
    var category = 'original';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add catalog book'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
                TextField(controller: author, decoration: const InputDecoration(labelText: 'Author')),
                TextField(controller: desc, maxLines: 3, decoration: const InputDecoration(labelText: 'Description')),
                DropdownButtonFormField<String>(
                  value: license,
                  decoration: const InputDecoration(labelText: 'License'),
                  items: const [
                    DropdownMenuItem(value: 'original', child: Text('Lovebird Original')),
                    DropdownMenuItem(value: 'public_domain', child: Text('Public domain')),
                    DropdownMenuItem(value: 'licensed', child: Text('Licensed (needs contract ref)')),
                  ],
                  onChanged: (v) => setLocal(() => license = v ?? license),
                ),
                if (license == 'licensed') TextField(controller: ref0, decoration: const InputDecoration(labelText: 'License / contract reference')),
                DropdownButtonFormField<String>(
                  value: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    for (final c in const ['novel', 'short_story', 'romance', 'poetry', 'relationship', 'interactive', 'original', 'other'])
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (v) => setLocal(() => category = v ?? category),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create (unpublished)')),
          ],
        ),
      ),
    );
    if (ok != true || title.text.trim().isEmpty || !context.mounted) return;
    await guard(context, () => sb.from('books').insert({
          'title': title.text.trim(),
          'author': author.text.trim().isEmpty ? 'Unknown' : author.text.trim(),
          'description': desc.text.trim().isEmpty ? null : desc.text.trim(),
          'license': license,
          'license_ref': license == 'licensed' ? ref0.text.trim() : null,
          'category': category,
          'published': false,
          'created_by': requireUserId(),
        }));
    ref.invalidate(_adminBooksProvider);
  }

  Future<void> _addChapter(BuildContext context, WidgetRef ref, Book b) async {
    final title = TextEditingController();
    final body = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add chapter ${(b.chapterCount ?? 0) + 1}'),
        content: SizedBox(
          width: 560,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Chapter title')),
            TextField(controller: body, minLines: 8, maxLines: 16, decoration: const InputDecoration(labelText: 'Text', alignLabelWithHint: true)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await guard(context, () => sb.from('book_chapters').insert({'book_id': b.id, 'number': (b.chapterCount ?? 0) + 1, 'title': title.text.trim(), 'body': body.text}));
    ref.invalidate(_adminBooksProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _addBook(context, ref), icon: const Icon(Icons.add), label: const Text('Book')),
      body: AsyncView<List<Book>>(
        value: ref.watch(_adminBooksProvider),
        onRetry: () => ref.invalidate(_adminBooksProvider),
        data: (books) => ListView(padding: const EdgeInsets.only(bottom: 80), children: [
          for (final b in books)
            ListTile(
              title: Text(b.title),
              subtitle: Text('${b.licenseLabel} · ${b.chapterCount ?? 0} chapters · ${b.published ? 'published' : 'draft'}'),
              trailing: Wrap(children: [
                IconButton(tooltip: 'Add chapter', onPressed: () => _addChapter(context, ref, b), icon: const Icon(Icons.post_add)),
                IconButton(
                  tooltip: b.published ? 'Unpublish' : 'Publish',
                  onPressed: () => guard(context, () async {
                    await sb.from('books').update({'published': !b.published}).eq('id', b.id);
                    ref.invalidate(_adminBooksProvider);
                  }),
                  icon: Icon(b.published ? Icons.visibility_off_outlined : Icons.publish_outlined),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- Announcements
final _adminAnnouncementsProvider = FutureProvider.autoDispose<List<Announcement>>((ref) async {
  final rows = await sb.from('announcements').select().order('created_at', ascending: false);
  return rows.map(Announcement.fromJson).toList();
});

class _AnnouncementsTab extends ConsumerWidget {
  const _AnnouncementsTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final title = await promptText(context, title: 'Announcement title', maxLength: 120);
          if (title == null || title.isEmpty || !context.mounted) return;
          final body = await promptText(context, title: 'Message', maxLength: 1000, maxLines: 4);
          if (body == null || body.isEmpty || !context.mounted) return;
          await guard(context, () => sb.from('announcements').insert({'title': title, 'body': body, 'created_by': requireUserId()}));
          ref.invalidate(_adminAnnouncementsProvider);
        },
        icon: const Icon(Icons.campaign_outlined),
        label: const Text('Announce'),
      ),
      body: AsyncView<List<Announcement>>(
        value: ref.watch(_adminAnnouncementsProvider),
        data: (list) => ListView(children: [
          for (final a in list)
            ListTile(
              title: Text(a.title),
              subtitle: Text(a.body),
              trailing: IconButton(
                tooltip: 'End announcement',
                icon: const Icon(Icons.stop_circle_outlined),
                onPressed: () => guard(context, () async {
                  await sb.from('announcements').update({'ends_at': DateTime.now().toUtc().toIso8601String()}).eq('id', a.id);
                  ref.invalidate(_adminAnnouncementsProvider);
                }),
              ),
            ),
        ]),
      ),
    );
  }
}
