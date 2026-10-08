/// Legally watchable films for Movie Night (brief §13).
/// Blender Foundation open movies are Creative Commons Attribution licensed;
/// attribution is shown in the player. Admins can extend this list; licensed
/// integrations plug in behind [ContentProvider] later.
class CatalogFilm {
  const CatalogFilm({
    required this.id,
    required this.title,
    required this.year,
    required this.minutes,
    required this.description,
    required this.url,
    required this.attribution,
    required this.emoji,
  });
  final String id;
  final String title;
  final int year;
  final int minutes;
  final String description;
  final String url;
  final String attribution;
  final String emoji;
}

const movieCatalog = <CatalogFilm>[
  CatalogFilm(
    id: 'sintel',
    title: 'Sintel',
    year: 2010,
    minutes: 15,
    emoji: '🐉',
    description: 'A lonely girl and the baby dragon she rescues. Bring tissues.',
    url: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4',
    attribution: '© Blender Foundation · sintel.org · CC BY 3.0',
  ),
  CatalogFilm(
    id: 'big_buck_bunny',
    title: 'Big Buck Bunny',
    year: 2008,
    minutes: 10,
    emoji: '🐰',
    description: 'A gentle giant rabbit gets his revenge on three bullies. Pure silliness.',
    url: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
    attribution: '© Blender Foundation · peach.blender.org · CC BY 3.0',
  ),
  CatalogFilm(
    id: 'tears_of_steel',
    title: 'Tears of Steel',
    year: 2012,
    minutes: 12,
    emoji: '🤖',
    description: 'Sci-fi in Amsterdam: a breakup, robots, and a second chance.',
    url: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4',
    attribution: '© Blender Foundation · mango.blender.org · CC BY 3.0',
  ),
  CatalogFilm(
    id: 'elephants_dream',
    title: 'Elephants Dream',
    year: 2006,
    minutes: 11,
    emoji: '🐘',
    description: 'Two strange travellers in an endless machine. Weird and wonderful.',
    url: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
    attribution: '© Blender Foundation · orange.blender.org · CC BY 2.5',
  ),
];

/// Future boundary for licensed streaming partners that permit synced playback.
abstract class ContentProvider {
  String get id;
  Future<List<CatalogFilm>> search(String query);
  Future<Uri> playbackUri(String filmId);
}
