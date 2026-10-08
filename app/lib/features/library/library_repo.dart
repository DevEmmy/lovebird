import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase.dart';
import '../../data/models.dart';
import '../../state/session.dart';

/// Published catalog + this couple's private uploads (RLS decides which they see).
final catalogProvider = FutureProvider<List<Book>>((ref) async {
  ref.watch(circleProvider);
  final rows = await sb.from('books').select('*, book_chapters(count)').order('created_at');
  return rows.map(Book.fromJson).where((b) => b.published || b.isPrivate).toList();
});

final bookProvider = FutureProvider.family<Book, String>((ref, id) async {
  final row = await sb.from('books').select('*, book_chapters(count)').eq('id', id).single();
  return Book.fromJson(row);
});

/// Chapter list without bodies (fast).
final chapterIndexProvider = FutureProvider.family<List<Chapter>, String>((ref, bookId) async {
  final rows = await sb.from('book_chapters').select('id, book_id, number, title').eq('book_id', bookId).order('number');
  return rows.map(Chapter.fromJson).toList();
});

final chapterProvider = FutureProvider.family<Chapter?, (String bookId, int number)>((ref, key) async {
  final row = await sb.from('book_chapters').select().eq('book_id', key.$1).eq('number', key.$2).maybeSingle();
  return row == null ? null : Chapter.fromJson(row);
});

final circleBookProvider = FutureProvider.family<CircleBook, String>((ref, id) async {
  final row = await sb.from('circle_books').select('*, books(*, book_chapters(count))').eq('id', id).single();
  return CircleBook.fromJson(row);
});

final highlightsProvider = StreamProvider.family<List<Highlight>, String>((ref, circleBookId) {
  return sb.from('highlights').stream(primaryKey: ['id']).eq('circle_book_id', circleBookId).asyncMap((_) async {
    final rows = await sb
        .from('highlights')
        .select('*, highlight_replies(*)')
        .eq('circle_book_id', circleBookId)
        .order('created_at', ascending: false);
    return rows.map(Highlight.fromJson).toList();
  });
});

class LibraryRepo {
  static Future<String> addToShelf(String circleId, String bookId) async {
    final existing = await sb.from('circle_books').select('id').eq('circle_id', circleId).eq('book_id', bookId).maybeSingle();
    if (existing != null) return existing['id'] as String;
    final row = await sb
        .from('circle_books')
        .insert({'circle_id': circleId, 'book_id': bookId, 'added_by': requireUserId()})
        .select('id')
        .single();
    return row['id'] as String;
  }

  static Future<void> startReading(String circleBookId) => sb
      .from('circle_books')
      .update({'status': 'reading', 'started_at': DateTime.now().toUtc().toIso8601String()})
      .eq('id', circleBookId);

  static Future<void> markFinished(String circleBookId) => sb
      .from('circle_books')
      .update({'status': 'finished', 'finished_at': DateTime.now().toUtc().toIso8601String()})
      .eq('id', circleBookId);

  static Future<void> setClub(String circleBookId, {required int weekday, required String time, required String tz, String? goal}) {
    final next = nextOccurrence(weekday, time);
    return sb.from('circle_books').update({
      'is_club': true,
      'goal': goal,
      'schedule': {'weekday': weekday, 'time': time, 'tz': tz},
      'next_session_at': next.toUtc().toIso8601String(),
    }).eq('id', circleBookId);
  }

  /// Next local date-time for a weekly slot (weekday: 1=Mon … 7=Sun, time "HH:mm").
  static DateTime nextOccurrence(int weekday, String time) {
    final parts = time.split(':');
    final now = DateTime.now();
    var d = DateTime(now.year, now.month, now.day, int.parse(parts[0]), int.parse(parts[1]));
    while (d.weekday != weekday || !d.isAfter(now)) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }

  static Future<void> saveProgress({
    required String circleBookId,
    required String circleId,
    required int chapter,
    required double scroll,
    required List<int> chaptersDone,
  }) =>
      sb.from('reading_progress').upsert({
        'circle_book_id': circleBookId,
        'circle_id': circleId,
        'user_id': requireUserId(),
        'chapter': chapter,
        'scroll': scroll.clamp(0.0, 1.0),
        'chapters_done': chaptersDone,
      }, onConflict: 'circle_book_id,user_id');

  static Future<void> highlight({required String circleBookId, required String circleId, required int chapter, required String quote, String? note}) =>
      sb.from('highlights').insert({
        'circle_book_id': circleBookId,
        'circle_id': circleId,
        'user_id': requireUserId(),
        'chapter': chapter,
        'quote': quote.length > 2000 ? quote.substring(0, 2000) : quote,
        'note': note,
      });

  static Future<void> reply(String highlightId, String circleId, String body) =>
      sb.from('highlight_replies').insert({'highlight_id': highlightId, 'circle_id': circleId, 'user_id': requireUserId(), 'body': body});

  static Future<void> reflect({required String circleBookId, required String circleId, required int chapter, required String body, int? rating}) =>
      sb.from('reading_reflections').insert({
        'circle_book_id': circleBookId,
        'circle_id': circleId,
        'chapter': chapter,
        'user_id': requireUserId(),
        'body': body,
        'rating': rating,
      });

  static Future<List<Reflection>> reflections(String circleBookId, int chapter) async {
    final rows = await sb.from('reading_reflections').select().eq('circle_book_id', circleBookId).eq('chapter', chapter);
    return rows.map(Reflection.fromJson).toList();
  }

  /// Private upload: love letters, your own writing (license = user_authorized).
  static Future<String> uploadPrivate({required String circleId, required String title, required String body, String category = 'love_letter'}) async {
    final row = await sb
        .from('books')
        .insert({
          'circle_id': circleId,
          'title': title,
          'author': 'Us',
          'category': category,
          'license': 'user_authorized',
          'published': false,
          'cover_color': '#AD1457',
          'created_by': requireUserId(),
        })
        .select('id')
        .single();
    final id = row['id'] as String;
    await sb.from('book_chapters').insert({'book_id': id, 'number': 1, 'title': title, 'body': body});
    return id;
  }
}
