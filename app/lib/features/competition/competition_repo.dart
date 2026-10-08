import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase.dart';
import '../../data/models.dart';
import '../../state/session.dart';

const _compSelect = '*, competition_fees(*), competition_prizes(*)';

final currentCompetitionProvider = FutureProvider<Competition?>((ref) async {
  ref.watch(userIdProvider);
  final row = await sb.from('competitions').select(_compSelect).neq('status', 'draft').order('year', ascending: false).limit(1).maybeSingle();
  return row == null ? null : Competition.fromJson(row);
});

final myEntryProvider = FutureProvider<CompetitionEntry?>((ref) async {
  final comp = await ref.watch(currentCompetitionProvider.future);
  final circle = ref.watch(circleProvider).valueOrNull;
  if (comp == null || circle == null) return null;
  final row = await sb
      .from('competition_entries')
      .select('*, competition_consents(*)')
      .eq('competition_id', comp.id)
      .eq('circle_id', circle.id)
      .maybeSingle();
  return row == null ? null : CompetitionEntry.fromJson(row);
});

final finalistsProvider = FutureProvider.family<List<Finalist>, String>((ref, compId) async {
  final rows = await sb.rpc('list_finalists', params: {'p_comp': compId}) as List;
  return rows.map((r) => Finalist.fromJson(Map<String, dynamic>.from(r as Map))).toList();
});

final myVoteProvider = FutureProvider.family<String?, String>((ref, compId) async {
  final row = await sb.from('competition_votes').select('entry_id').eq('competition_id', compId).eq('voter_id', requireUserId()).maybeSingle();
  return row?['entry_id'] as String?;
});

final isJudgeProvider = FutureProvider.family<bool, String>((ref, compId) async {
  final row = await sb.from('competition_judges').select('user_id').eq('competition_id', compId).eq('user_id', requireUserId()).maybeSingle();
  return row != null;
});

class CompetitionRepo {
  static const termsVersion = 'v1';

  static Future<String> createEntry(String compId, String circleId, Map<String, dynamic> fields) async {
    final row = await sb
        .from('competition_entries')
        .insert({...fields, 'competition_id': compId, 'circle_id': circleId, 'submitted_by': requireUserId()})
        .select('id')
        .single();
    return row['id'] as String;
  }

  static Future<void> updateEntry(String entryId, Map<String, dynamic> fields) => sb.from('competition_entries').update(fields).eq('id', entryId);

  static Future<String> consent(String entryId, {required bool publicApproved}) async =>
      await sb.rpc('consent_to_entry', params: {'p_entry': entryId, 'p_public': publicApproved, 'p_terms_version': termsVersion}) as String;

  static Future<void> withdrawConsent(String entryId) => sb.from('competition_consents').delete().eq('entry_id', entryId).eq('user_id', requireUserId());

  static Future<void> withdrawEntry(String entryId) => sb.from('competition_entries').update({'status': 'withdrawn'}).eq('id', entryId);

  static Future<void> vote(String entryId) => sb.rpc('cast_vote', params: {'p_entry': entryId});

  static Future<void> score(String compId, String entryId, Map<String, int> scores, String? comment) => sb.from('competition_scores').upsert({
        'competition_id': compId,
        'entry_id': entryId,
        'judge_id': requireUserId(),
        'scores': scores,
        'comment': comment,
      }, onConflict: 'entry_id,judge_id');
}
