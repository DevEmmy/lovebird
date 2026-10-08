import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/supabase.dart';
import '../state/session.dart';
import 'models.dart';

// Circle-scoped realtime collections. RLS guarantees only this couple's rows arrive.

final memoriesProvider = StreamProvider<List<Memory>>((ref) {
  final circle = ref.watch(circleProvider).valueOrNull;
  if (circle == null) return Stream.value(const []);
  return sb
      .from('memories')
      .stream(primaryKey: ['id'])
      .eq('circle_id', circle.id)
      .order('happened_on', ascending: false)
      .map((rows) => rows.map(Memory.fromJson).toList()..sort((a, b) => b.happenedOn.compareTo(a.happenedOn)));
});

final memoryProvider = Provider.family<Memory?, String>((ref, id) {
  for (final m in ref.watch(memoriesProvider).valueOrNull ?? const <Memory>[]) {
    if (m.id == id) return m;
  }
  return null;
});

final specialDatesProvider = FutureProvider<List<SpecialDate>>((ref) async {
  final circle = ref.watch(circleProvider).valueOrNull;
  if (circle == null) return const [];
  final rows = await sb.from('special_dates').select().eq('circle_id', circle.id);
  return rows.map(SpecialDate.fromJson).toList()..sort((a, b) => a.daysUntil.compareTo(b.daysUntil));
});

final plansProvider = FutureProvider<List<Plan>>((ref) async {
  final circle = ref.watch(circleProvider).valueOrNull;
  if (circle == null) return const [];
  final rows = await sb.from('plans').select().eq('circle_id', circle.id).order('created_at');
  return rows.map(Plan.fromJson).toList();
});

final planItemsProvider = StreamProvider<List<PlanItem>>((ref) {
  final circle = ref.watch(circleProvider).valueOrNull;
  if (circle == null) return Stream.value(const []);
  return sb
      .from('plan_items')
      .stream(primaryKey: ['id'])
      .eq('circle_id', circle.id)
      .map((rows) => rows.map(PlanItem.fromJson).toList()..sort((a, b) => a.position.compareTo(b.position)));
});

final upcomingPlanItemsProvider = Provider<List<PlanItem>>((ref) {
  final items = ref.watch(planItemsProvider).valueOrNull ?? const [];
  final now = DateTime.now().subtract(const Duration(hours: 6));
  return items.where((i) => !i.done && i.dueAt != null && i.dueAt!.isAfter(now)).toList()
    ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
});

final shelfProvider = FutureProvider<List<CircleBook>>((ref) async {
  final circle = ref.watch(circleProvider).valueOrNull;
  if (circle == null) return const [];
  final rows = await sb
      .from('circle_books')
      .select('*, books(*, book_chapters(count))')
      .eq('circle_id', circle.id)
      .order('created_at', ascending: false);
  return rows.map(CircleBook.fromJson).toList();
});

final progressProvider = StreamProvider.family<List<ReadingProgress>, String>((ref, circleBookId) {
  return sb
      .from('reading_progress')
      .stream(primaryKey: ['circle_book_id', 'user_id'])
      .eq('circle_book_id', circleBookId)
      .map((rows) => rows.map(ReadingProgress.fromJson).toList());
});

final notificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final uid = ref.watch(userIdProvider);
  if (uid == null) return Stream.value(const []);
  return sb
      .from('notifications')
      .stream(primaryKey: ['id'])
      .eq('user_id', uid)
      .order('created_at', ascending: false)
      .limit(100)
      .map((rows) => rows.map(AppNotification.fromJson).toList());
});

final unreadNotificationsProvider = Provider<int>((ref) =>
    (ref.watch(notificationsProvider).valueOrNull ?? const []).where((n) => n.unread).length);

final announcementsProvider = FutureProvider<List<Announcement>>((ref) async {
  ref.watch(userIdProvider);
  final rows = await sb.from('announcements').select().order('starts_at', ascending: false).limit(3);
  return rows.map(Announcement.fromJson).toList();
});

final gameHistoryProvider = FutureProvider<List<GameSession>>((ref) async {
  final circle = ref.watch(circleProvider).valueOrNull;
  if (circle == null) return const [];
  final rows = await sb.from('game_sessions').select().eq('circle_id', circle.id).order('created_at', ascending: false).limit(30);
  return rows.map(GameSession.fromJson).toList();
});
