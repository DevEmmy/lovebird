import 'dart:convert';

import '../core/supabase.dart';
import 'models.dart';

class InviteInfo {
  InviteInfo(this.code, this.expiresAt);
  final String code;
  final DateTime expiresAt;
}

class CircleRepo {
  static Future<InviteInfo> createCircle() async {
    final rows = await sb.rpc('create_circle') as List;
    final r = Map<String, dynamic>.from(rows.first as Map);
    return InviteInfo(r['code'] as String, DateTime.parse(r['expires_at'] as String));
  }

  static Future<InviteInfo?> activeInvitation(String circleId) async {
    final row = await sb
        .from('invitations')
        .select('code, expires_at')
        .eq('circle_id', circleId)
        .isFilter('used_at', null)
        .isFilter('revoked_at', null)
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return null;
    return InviteInfo(row['code'] as String, DateTime.parse(row['expires_at'] as String));
  }

  static Future<InviteInfo> regenerate(String circleId) async {
    final rows = await sb.rpc('regenerate_invitation', params: {'p_circle': circleId}) as List;
    final r = Map<String, dynamic>.from(rows.first as Map);
    return InviteInfo(r['code'] as String, DateTime.parse(r['expires_at'] as String));
  }

  /// Returns the inviter's name, or null if the code is invalid/expired.
  static Future<String?> preview(String code) async {
    final rows = await sb.rpc('preview_invitation', params: {'p_code': code}) as List;
    if (rows.isEmpty) return null;
    return (rows.first as Map)['inviter_name'] as String?;
  }

  /// Returns the circle id, or null if the code is invalid/expired.
  static Future<String?> join(String code) async => await sb.rpc('join_circle', params: {'p_code': code}) as String?;

  static Future<void> cancelPending(String circleId) => sb.rpc('cancel_pending_circle', params: {'p_circle': circleId});

  static Future<DateTime> endCircle(String circleId) async =>
      DateTime.parse(await sb.rpc('end_circle', params: {'p_circle': circleId}) as String);

  static Future<void> deleteMyContent(String circleId) => sb.rpc('delete_my_content', params: {'p_circle': circleId});

  static Future<void> update(String circleId, Map<String, dynamic> fields) =>
      sb.from('circles').update(fields).eq('id', circleId);

  /// Ended circles still inside their 30-day export window.
  static Future<List<Circle>> pastCircles() async {
    final uid = requireUserId();
    final members = await sb.from('circle_members').select('circle_id').eq('user_id', uid).not('left_at', 'is', null);
    final ids = members.map((m) => m['circle_id'] as String).toList();
    if (ids.isEmpty) return [];
    final rows = await sb.from('circles').select().inFilter('id', ids).eq('status', 'ended');
    return rows.map(Circle.fromJson).where((c) => c.purgeAfter?.isAfter(DateTime.now()) ?? false).toList();
  }

  /// Portable JSON export of everything the user can read in a circle (§41 data rights).
  /// Photos are referenced by storage path; signed links are added so they can be downloaded.
  static Future<String> exportCircle(String circleId) async {
    Future<List<Map<String, dynamic>>> all(String table, {String order = 'created_at'}) async =>
        List<Map<String, dynamic>>.from(await sb.from(table).select().eq('circle_id', circleId).order(order));
    final data = <String, dynamic>{
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'circle': await sb.from('circles').select().eq('id', circleId).single(),
      'messages': await all('messages'),
      'diary_entries': await all('diary_entries'),
      'memories': await all('memories'),
      'plans': await all('plans'),
      'plan_items': await all('plan_items'),
      'special_dates': await all('special_dates'),
      'highlights': await all('highlights'),
      'reading_reflections': await all('reading_reflections'),
    };
    final media = await all('media');
    final links = <String, String>{};
    for (final m in media) {
      final path = m['path'] as String;
      try {
        links[path] = await sb.storage.from('circle-media').createSignedUrl(path, 60 * 60 * 24 * 7);
      } catch (_) {}
    }
    data['media'] = media;
    data['media_download_links_valid_7_days'] = links;
    return const JsonEncoder.withIndent('  ').convert(data);
  }
}
