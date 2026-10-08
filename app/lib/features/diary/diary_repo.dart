import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase.dart';
import '../../data/models.dart';
import '../../state/session.dart';

final diaryProvider = StreamProvider<List<DiaryEntry>>((ref) {
  final circle = ref.watch(circleProvider).valueOrNull;
  if (circle == null) return Stream.value(const []);
  return sb
      .from('diary_entries')
      .stream(primaryKey: ['id'])
      .eq('circle_id', circle.id)
      .order('entry_date', ascending: false)
      .map((rows) => rows.map(DiaryEntry.fromJson).toList()
        ..sort((a, b) {
          final d = b.entryDate.compareTo(a.entryDate);
          return d != 0 ? d : b.createdAt.compareTo(a.createdAt);
        }));
});

final diaryEntryProvider = Provider.family<DiaryEntry?, String>((ref, id) {
  final list = ref.watch(diaryProvider).valueOrNull ?? const [];
  for (final e in list) {
    if (e.id == id) return e;
  }
  return null;
});

class DiaryTypes {
  static const all = <String, (String emoji, String label)>{
    'written': ('✍️', 'Written'),
    'memory': ('📸', 'Memory'),
    'funny': ('😂', 'Funny moment'),
    'romantic': ('❤️', 'Romantic moment'),
    'game': ('🎮', 'Game moment'),
    'movie': ('🎬', 'Movie night'),
    'reading': ('📖', 'Reading moment'),
    'milestone': ('🎉', 'Milestone'),
    'chat': ('💬', 'Chat moment'),
  };
  static String emoji(String t) => all[t]?.$1 ?? '✍️';
  static String label(String t) => all[t]?.$2 ?? 'Entry';
}

class DiaryRepo {
  static Future<String> create({
    required String circleId,
    required String entryType,
    String origin = 'partner',
    String? title,
    String? body,
    List<String> photoPaths = const [],
    Map<String, dynamic> payload = const {},
    String? mood,
    DateTime? entryDate,
  }) async {
    final row = await sb
        .from('diary_entries')
        .insert({
          'circle_id': circleId,
          'author_id': requireUserId(),
          'origin': origin,
          'entry_type': entryType,
          'title': title,
          'body': body,
          'photo_paths': photoPaths,
          'payload': payload,
          'mood': mood,
          if (entryDate != null) 'entry_date': entryDate.toIso8601String().substring(0, 10),
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  static Future<void> update(String id, Map<String, dynamic> fields) => sb.from('diary_entries').update(fields).eq('id', id);
  static Future<void> delete(String id) => sb.from('diary_entries').delete().eq('id', id);
}
