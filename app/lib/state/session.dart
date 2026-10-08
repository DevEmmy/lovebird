import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase.dart';
import '../data/models.dart';
import 'circle_channel.dart';

/// Auth events (sign in/out, token refresh, password recovery).
final authStateProvider = StreamProvider<AuthState>((ref) => sb.auth.onAuthStateChange);

final userIdProvider = Provider<String?>((ref) {
  ref.watch(authStateProvider);
  return sb.auth.currentUser?.id;
});

final myProfileProvider = StreamProvider<Profile?>((ref) {
  final uid = ref.watch(userIdProvider);
  if (uid == null) return Stream.value(null);
  return sb
      .from('profiles')
      .stream(primaryKey: ['id'])
      .eq('id', uid)
      .map((rows) => rows.isEmpty ? null : Profile.fromJson(rows.first));
});

/// The caller's live membership → circle id (null = not in a circle).
final membershipProvider = StreamProvider<String?>((ref) {
  final uid = ref.watch(userIdProvider);
  if (uid == null) return Stream.value(null);
  return sb
      .from('circle_members')
      .stream(primaryKey: ['id'])
      .eq('user_id', uid)
      .map((rows) => rows.firstWhereOrNull((r) => r['left_at'] == null)?['circle_id'] as String?);
});

final circleProvider = StreamProvider<Circle?>((ref) {
  final membership = ref.watch(membershipProvider);
  final cid = membership.valueOrNull;
  if (membership.isLoading && cid == null) {
    return const Stream<Circle?>.empty();
  }
  if (cid == null) return Stream.value(null);
  return sb
      .from('circles')
      .stream(primaryKey: ['id'])
      .eq('id', cid)
      .map((rows) => rows.isEmpty ? null : Circle.fromJson(rows.first));
});

/// Throws if used outside an active circle — feature screens are only routable when active.
final circleIdProvider = Provider<String>((ref) {
  final c = ref.watch(circleProvider).valueOrNull;
  if (c == null) throw StateError('No active Love Circle');
  return c.id;
});

final partnerProvider = FutureProvider<Profile?>((ref) async {
  final circle = ref.watch(circleProvider).valueOrNull;
  final uid = ref.watch(userIdProvider);
  if (circle == null || uid == null || circle.isPending) return null;
  final member = await sb
      .from('circle_members')
      .select('user_id')
      .eq('circle_id', circle.id)
      .neq('user_id', uid)
      .maybeSingle();
  if (member == null) return null;
  final row = await sb.from('profiles').select().eq('id', member['user_id'] as String).maybeSingle();
  return row == null ? null : Profile.fromJson(row);
});

final isAdminProvider = FutureProvider<bool>((ref) async {
  final uid = ref.watch(userIdProvider);
  if (uid == null) return false;
  final row = await sb.from('app_admins').select('user_id').eq('user_id', uid).maybeSingle();
  return row != null;
});

/// One realtime channel per active circle: broadcast + presence.
final circleChannelProvider = Provider<CircleChannel?>((ref) {
  final circle = ref.watch(circleProvider).valueOrNull;
  final uid = ref.watch(userIdProvider);
  final showOnline = ref.watch(myProfileProvider.select((p) => p.valueOrNull?.showOnline ?? true));
  if (circle == null || !circle.isActive || uid == null) return null;
  final channel = CircleChannel(circleId: circle.id, userId: uid, trackPresence: showOnline);
  ref.onDispose(channel.dispose);
  return channel;
});

/// Display name helper for "who did this" labels.
final nameOfProvider = Provider<String Function(String?)>((ref) {
  final me = ref.watch(myProfileProvider).valueOrNull;
  final partner = ref.watch(partnerProvider).valueOrNull;
  return (String? id) {
    if (id == null) return 'Lovebird';
    if (id == me?.id) return 'You';
    if (id == partner?.id) return partner!.displayName;
    return 'Your partner';
  };
});
