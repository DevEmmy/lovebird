import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/supabase.dart';
import '../state/session.dart';
import 'models.dart';

class TogetherRepo {
  /// Starts a shared activity and notifies the partner. Ends any previous live session.
  static Future<String> start({
    required String circleId,
    required String activity,
    String? refType,
    String? refId,
    String? title,
  }) async {
    return await sb.rpc('start_together', params: {
      'p_circle': circleId,
      'p_activity': activity,
      'p_ref_type': refType,
      'p_ref_id': refId,
      'p_title': title,
    }) as String;
  }

  static Future<void> join(String sessionId) =>
      sb.from('together_sessions').update({'status': 'active', 'joined_at': DateTime.now().toUtc().toIso8601String()}).eq('id', sessionId);

  static Future<void> end(String sessionId) =>
      sb.from('together_sessions').update({'status': 'ended', 'ended_at': DateTime.now().toUtc().toIso8601String()}).eq('id', sessionId);

  /// Route for a session's activity.
  static String routeFor(TogetherSession s) {
    switch (s.refType) {
      case 'game':
        return '/game/${s.refId}';
      case 'movie':
        return '/movie/${s.refId}';
      case 'reading':
        return '/read/${s.refId}';
      case 'date':
        return '/date-night/${s.title?.split('|').first ?? 'surprise'}';
    }
    return switch (s.activity) {
      'play' => '/games',
      'watch' => '/movie',
      'read' => '/library',
      'talk' => '/talk',
      'create' => '/create',
      'date' => '/date-night',
      _ => '/together',
    };
  }
}

/// The live Together session in this circle (at most one), realtime.
final liveTogetherProvider = StreamProvider<TogetherSession?>((ref) {
  final circle = ref.watch(circleProvider).valueOrNull;
  if (circle == null || !circle.isActive) return Stream.value(null);
  return sb
      .from('together_sessions')
      .stream(primaryKey: ['id'])
      .eq('circle_id', circle.id)
      .order('created_at', ascending: false)
      .limit(5)
      .map((rows) {
        for (final r in rows) {
          final s = TogetherSession.fromJson(r);
          if (s.live) return s;
        }
        return null;
      });
});
