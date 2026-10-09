import 'dart:convert';

import 'package:http/http.dart' as http;

/// Legal full-length films from the Internet Archive's public-domain
/// "Feature Films" collection (archive.org/details/feature_films).
/// Search + metadata are public APIs that allow browser (CORS) access.
class ArchiveFilm {
  ArchiveFilm({required this.id, required this.title, this.year, this.description, this.downloads});
  final String id;
  final String title;
  final String? year;
  final String? description;
  final int? downloads;

  String get posterUrl => 'https://archive.org/services/img/$id';
  String get pageUrl => 'https://archive.org/details/$id';
}

class InternetArchive {
  static const _base = 'https://archive.org';

  static const genres = <String, String>{
    'Most watched': '',
    'Romance': 'romance',
    'Comedy': 'comedy',
    'Drama': 'drama',
    'Mystery & Noir': 'film noir OR mystery',
    'Horror': 'horror',
    'Sci-Fi': 'science fiction',
    'Westerns': 'western',
    'Silent classics': 'silent',
    'Animation': 'animation OR cartoon',
  };

  /// Search the public-domain feature film collection.
  static Future<List<ArchiveFilm>> search({String query = '', String genre = '', int page = 1, int rows = 30}) async {
    final terms = <String>['collection:(feature_films)', 'mediatype:(movies)'];
    if (genre.isNotEmpty) terms.add('subject:($genre)');
    if (query.trim().isNotEmpty) {
      final q = query.trim().replaceAll(RegExp(r'[()":]'), ' ');
      terms.add('(title:($q) OR description:($q) OR subject:($q))');
    }
    final uri = Uri.parse('$_base/advancedsearch.php').replace(queryParameters: {
      'q': terms.join(' AND '),
      'fl[]': ['identifier', 'title', 'year', 'description', 'downloads'],
      'sort[]': 'downloads desc',
      'rows': '$rows',
      'page': '$page',
      'output': 'json',
    });
    final res = await http.get(uri).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw Exception('Archive search failed (${res.statusCode})');
    final docs = (jsonDecode(res.body)['response']?['docs'] as List?) ?? const [];
    return docs.map((d) {
      final m = Map<String, dynamic>.from(d as Map);
      String? str(dynamic v) => v == null ? null : (v is List ? (v.isEmpty ? null : '${v.first}') : '$v');
      return ArchiveFilm(
        id: m['identifier'] as String,
        title: str(m['title']) ?? m['identifier'] as String,
        year: str(m['year']),
        description: str(m['description'])?.replaceAll(RegExp(r'<[^>]*>'), '').trim(),
        downloads: (m['downloads'] as num?)?.toInt(),
      );
    }).toList();
  }

  /// Finds the best browser-playable MP4 for a film. Returns null if none.
  static Future<String?> playableUrl(String id) async {
    final res = await http.get(Uri.parse('$_base/metadata/$id')).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return null;
    final files = ((jsonDecode(res.body)['files'] as List?) ?? const []).map((f) => Map<String, dynamic>.from(f as Map)).toList();
    int rank(Map<String, dynamic> f) {
      final name = (f['name'] as String? ?? '').toLowerCase();
      final format = (f['format'] as String? ?? '').toLowerCase();
      if (!name.endsWith('.mp4')) return -1;
      if (format.contains('h.264') && !format.contains('hd')) return 4;
      if (format.contains('512kb')) return 3;
      if (format.contains('h.264')) return 2;
      return 1;
    }

    files.sort((a, b) => rank(b).compareTo(rank(a)));
    if (files.isEmpty || rank(files.first) < 0) return null;
    final name = files.first['name'] as String;
    return '$_base/download/$id/${Uri.encodeComponent(name).replaceAll('%2F', '/')}';
  }
}
