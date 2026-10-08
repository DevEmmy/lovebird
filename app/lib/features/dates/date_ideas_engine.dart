import 'dart:math';

/// Offline Date Idea engine (always available, no AI needed).
/// The AI generator in the edge function personalises further when enabled.

enum Distance { longDistance, nearby }

class DateQuery {
  const DateQuery({
    this.budget,
    this.currency = 'USD',
    this.location = '',
    this.minutes = 60,
    this.distance = Distance.longDistance,
    this.setting = 'any',
    this.mood = 'romantic',
    this.food = '',
    this.energy = 'medium',
    this.spendMoney = true,
  });
  final double? budget;
  final String currency;
  final String location;
  final int minutes;
  final Distance distance;
  final String setting; // indoor | outdoor | any
  final String mood; // romantic | funny | adventurous | chill
  final String food;
  final String energy; // low | medium | high
  final bool spendMoney;
}

class DateIdea {
  const DateIdea(this.title, this.summary, this.steps,
      {required this.tier, required this.ld, required this.near, required this.minutes, this.setting = 'indoor', required this.moods, this.energy = 'medium', this.route});
  final String title;
  final String summary;
  final List<String> steps;

  /// 0 free · 1 low · 2 medium · 3 high
  final int tier;
  final bool ld;
  final bool near;
  final int minutes;
  final String setting;
  final Set<String> moods;
  final String energy;
  final String? route;

  String costLabel(String currency) => switch (tier) {
        0 => 'Free',
        1 => 'Low cost (${_tierRange(currency, 1)})',
        2 => 'Mid budget (${_tierRange(currency, 2)})',
        _ => 'Splurge',
      };
}

/// Approximate local thresholds for "low" and "medium" spend. Tuned per currency
/// so "under ₦5,000" and "under $20" both land in the low tier.
const _thresholds = <String, (double low, double mid)>{
  'USD': (25, 100), 'CAD': (30, 130), 'AUD': (35, 150), 'NZD': (40, 160),
  'GBP': (20, 80), 'EUR': (25, 90), 'SEK': (250, 1000), 'NOK': (250, 1000), 'PLN': (100, 400),
  'NGN': (10000, 50000), 'GHS': (200, 800), 'KES': (2000, 8000), 'ZAR': (300, 1200), 'EGP': (800, 3000),
  'AED': (80, 350), 'SAR': (80, 350), 'INR': (1500, 6000), 'PKR': (4000, 15000), 'PHP': (1000, 4000),
  'SGD': (30, 130), 'JPY': (3000, 12000), 'KRW': (30000, 120000), 'BRL': (100, 400), 'MXN': (400, 1600),
};

String _tierRange(String currency, int tier) {
  final t = _thresholds[currency] ?? _thresholds['USD']!;
  String n(double v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k' : v.toStringAsFixed(0);
  return tier == 1 ? 'under ${n(t.$1)} $currency' : 'under ${n(t.$2)} $currency';
}

int budgetTier(double? budget, String currency) {
  if (budget == null) return 3;
  if (budget <= 0) return 0;
  final t = _thresholds[currency] ?? _thresholds['USD']!;
  if (budget <= t.$1) return 1;
  if (budget <= t.$2) return 2;
  return 3;
}

const dateIdeas = <DateIdea>[
  // ---------- Long-distance friendly ----------
  DateIdea('Synced Movie Night', 'Pick a film in Lovebird and watch in perfect sync.', ['Choose a free film in Movie Night', 'Make the same snack', 'React live and rate it after'],
      tier: 0, ld: true, near: true, minutes: 120, moods: {'romantic', 'chill', 'funny'}, energy: 'low', route: '/movie'),
  DateIdea('Cook the Same Recipe', 'Same dish, two kitchens, one video call.', ['Pick a recipe you both have ingredients for', 'Cook together on call', 'Eat "together" and judge plating'],
      tier: 1, ld: true, near: true, minutes: 90, moods: {'romantic', 'funny', 'adventurous'}, route: '/date-night/cooking'),
  DateIdea('Deep Questions by Candlelight', 'Light a candle on both ends and go deep.', ['Light a candle', 'Play Deep Questions', 'End with three appreciations each'],
      tier: 0, ld: true, near: true, minutes: 45, moods: {'romantic', 'chill'}, energy: 'low', route: '/games?key=deep_questions'),
  DateIdea('Virtual Museum Tour', 'Explore a world-famous museum online together.', ['Pick a museum with a free virtual tour', 'Share screens or browse side by side', 'Each choose a favourite piece and explain why'],
      tier: 0, ld: true, near: true, minutes: 60, moods: {'adventurous', 'chill'}, energy: 'low'),
  DateIdea('Read Together Night', 'Pick a story from Our Library and read a chapter each.', ['Open Our Library', 'Read aloud, taking turns', 'Reveal your chapter thoughts'],
      tier: 0, ld: true, near: true, minutes: 45, moods: {'romantic', 'chill'}, energy: 'low', route: '/library'),
  DateIdea('Send Each Other Dinner', 'Order a surprise meal to each other\'s door.', ['Agree a budget', 'Secretly order your partner\'s favourite', 'Unbox and eat on video'],
      tier: 2, ld: true, near: true, minutes: 75, moods: {'romantic', 'funny'}),
  DateIdea('Game Tournament', 'Three games, one champion, one silly prize.', ['Set a prize', 'Play This or That, Guess My Answer, Truth or Dare', 'Crown the winner'],
      tier: 0, ld: true, near: true, minutes: 60, moods: {'funny', 'adventurous'}, energy: 'high', route: '/date-night/games'),
  DateIdea('Stargazing Call', 'Look at the same moon from different places.', ['Go outside (or to a window)', 'Use a free star map app', 'Find the same constellation and make a wish'],
      tier: 0, ld: true, near: true, minutes: 30, setting: 'outdoor', moods: {'romantic', 'chill'}, energy: 'low'),
  DateIdea('Playlist Swap', 'Build playlists for each other and listen together.', ['Each pick 8 songs that remind you of the other', 'Listen together on call', 'Explain one song each'],
      tier: 0, ld: true, near: true, minutes: 45, moods: {'romantic', 'chill'}, energy: 'low'),
  DateIdea('Draw Each Other', 'Two minutes, no looking at the paper. Big laughs guaranteed.', ['Grab paper and pen', 'Draw each other blind', 'Reveal and save to Memories'],
      tier: 0, ld: true, near: true, minutes: 20, moods: {'funny'}, route: '/create'),
  DateIdea('Online Class Together', 'Learn something new: dance, language, cooking.', ['Find a free class online', 'Join at the same time', 'Practise on each other'],
      tier: 1, ld: true, near: true, minutes: 60, moods: {'adventurous', 'funny'}, energy: 'high'),
  DateIdea('Future Letter', 'Write letters to your future selves, one year from now.', ['Write separately for 15 minutes', 'Save to Our Diary', 'Set a reminder for next year'],
      tier: 0, ld: true, near: true, minutes: 30, moods: {'romantic'}, energy: 'low', route: '/diary/new?together=1&prompt=future'),
  DateIdea('Dress-Up Dinner Date', 'Fancy outfits, simple food, candlelight — on video.', ['Dress up like it\'s a fancy restaurant', 'Make or order something simple', 'Toast to something you\'re proud of'],
      tier: 1, ld: true, near: true, minutes: 75, moods: {'romantic', 'funny'}),
  DateIdea('Plan Our Dream Trip', 'Plan the trip you\'ll take together one day.', ['Pick a destination', 'Plan day by day', 'Add it to Our Plans'],
      tier: 0, ld: true, near: true, minutes: 45, moods: {'adventurous', 'romantic'}, energy: 'low', route: '/plans'),
  DateIdea('Sunrise or Sunset Call', 'Watch it together, even if it\'s at different times.', ['Find your sunset times', 'Call when one of you sees it', 'Describe it to each other'],
      tier: 0, ld: true, near: true, minutes: 20, setting: 'outdoor', moods: {'romantic', 'chill'}, energy: 'low'),
  DateIdea('Workout Together', 'A free online workout on video. Sweaty, silly, wholesome.', ['Pick a 20-minute workout video', 'Do it together on call', 'Cool down with a chat'],
      tier: 0, ld: true, near: true, minutes: 30, moods: {'adventurous', 'funny'}, energy: 'high'),
  DateIdea('Gift Box Swap', 'Mail each other small boxes and open them on call.', ['Set a small budget', 'Fill a box with little things', 'Open together on video'],
      tier: 2, ld: true, near: false, minutes: 45, moods: {'romantic'}, energy: 'low'),
  DateIdea('Mini Book Club', 'Pick a short story, read, then discuss over tea.', ['Choose a short story', 'Read separately', 'Meet to discuss with tea or coffee'],
      tier: 0, ld: true, near: true, minutes: 60, moods: {'chill', 'romantic'}, energy: 'low', route: '/library'),
  DateIdea('Couples Quiz Night', 'Find out how well your stories match.', ['Play Couple Quiz', 'Then Compatibility', 'Celebrate your matches'],
      tier: 0, ld: true, near: true, minutes: 30, moods: {'funny', 'romantic'}, route: '/games?key=couple_quiz'),
  DateIdea('Karaoke Night', 'Sing duets badly and proudly.', ['Find karaoke versions online', 'Take turns choosing songs', 'Finish with a duet'],
      tier: 0, ld: true, near: true, minutes: 45, moods: {'funny'}, energy: 'high'),
  // ---------- Nearby ----------
  DateIdea('Picnic in the Park', 'Blanket, snacks, and no plans.', ['Pack simple snacks', 'Find a shady spot', 'Bring a game or a book'],
      tier: 1, ld: false, near: true, minutes: 120, setting: 'outdoor', moods: {'romantic', 'chill'}, energy: 'low'),
  DateIdea('Street Food Crawl', 'Try three things you\'ve never eaten before.', ['Pick a busy food street or market', 'Share every dish', 'Rate each out of 10'],
      tier: 1, ld: false, near: true, minutes: 120, setting: 'outdoor', moods: {'adventurous', 'funny'}, energy: 'high'),
  DateIdea('Sunrise Walk', 'Wake up early and watch the city wake up.', ['Set an alarm', 'Walk somewhere with a view', 'Breakfast after'],
      tier: 0, ld: false, near: true, minutes: 90, setting: 'outdoor', moods: {'romantic', 'adventurous'}),
  DateIdea('Home Spa Night', 'Face masks, soft music, foot rubs.', ['Get simple face masks', 'Play calm music', 'Take turns pampering'],
      tier: 1, ld: false, near: true, minutes: 90, moods: {'romantic', 'chill'}, energy: 'low'),
  DateIdea('Thrift Shop Challenge', 'Pick an outfit for each other on a tiny budget.', ['Set a tiny budget each', 'Shop separately for 30 minutes', 'Reveal the outfits'],
      tier: 1, ld: false, near: true, minutes: 120, setting: 'indoor', moods: {'funny', 'adventurous'}, energy: 'high'),
  DateIdea('Cook a New Cuisine', 'Pick a country, cook its national dish together.', ['Choose a cuisine', 'Shop together', 'Cook and eat with music from that country'],
      tier: 2, ld: false, near: true, minutes: 150, moods: {'adventurous', 'romantic'}),
  DateIdea('Live Music Night', 'Find a local gig, open mic or free concert.', ['Check local listings', 'Grab a cheap bite before', 'Dance at least once'],
      tier: 2, ld: false, near: true, minutes: 180, setting: 'indoor', moods: {'adventurous', 'romantic'}, energy: 'high'),
  DateIdea('Board Game Café', 'Learn a new board game together.', ['Find a board game café', 'Ask staff for a 2-player recommendation', 'Loser buys dessert'],
      tier: 1, ld: false, near: true, minutes: 120, moods: {'funny', 'chill'}),
  DateIdea('Fancy Dinner Out', 'Dress up and try somewhere special.', ['Book a table', 'Dress up', 'Toast to your favourite memory'],
      tier: 3, ld: false, near: true, minutes: 150, moods: {'romantic'}, energy: 'low'),
  DateIdea('Day Trip', 'Pick a nearby town you\'ve never visited.', ['Choose a destination within 2 hours', 'Explore with no itinerary', 'Collect one souvenir each'],
      tier: 2, ld: false, near: true, minutes: 480, setting: 'outdoor', moods: {'adventurous'}, energy: 'high'),
  DateIdea('Photo Walk', 'Take photos of things that remind you of each other.', ['Walk a new neighbourhood', 'Snap 10 photos each', 'Make a Memory from the best ones'],
      tier: 0, ld: false, near: true, minutes: 90, setting: 'outdoor', moods: {'romantic', 'adventurous'}, route: '/memory/new'),
  DateIdea('Blanket Fort Movie', 'Build a fort, watch a film inside it.', ['Build the fort', 'Pick a film in Movie Night', 'Popcorn mandatory'],
      tier: 0, ld: false, near: true, minutes: 150, moods: {'funny', 'romantic', 'chill'}, energy: 'low', route: '/movie'),
  DateIdea('Volunteer Together', 'Give a few hours to a cause you both care about.', ['Find a local volunteering slot', 'Go together', 'Talk about it over a drink after'],
      tier: 0, ld: false, near: true, minutes: 180, setting: 'any', moods: {'adventurous', 'chill'}),
  DateIdea('Sunset Rooftop Drinks', 'Golden hour, your favourite drinks, a view.', ['Find a rooftop or hill', 'Bring drinks and snacks', 'Watch the sunset together'],
      tier: 2, ld: false, near: true, minutes: 120, setting: 'outdoor', moods: {'romantic', 'chill'}, energy: 'low'),
];

class DateIdeaEngine {
  static List<DateIdea> suggest(DateQuery q, {int count = 6, int seed = 0}) {
    final maxTier = q.spendMoney ? budgetTier(q.budget, q.currency) : 0;
    final pool = dateIdeas.where((i) {
      if (q.distance == Distance.longDistance && !i.ld) return false;
      if (q.distance == Distance.nearby && !i.near) return false;
      if (i.tier > maxTier) return false;
      if (i.minutes > q.minutes * 1.5 + 15) return false;
      if (q.setting != 'any' && i.setting != 'any' && i.setting != q.setting) return false;
      return true;
    }).toList();

    double score(DateIdea i) {
      var s = 0.0;
      if (i.moods.contains(q.mood)) s += 3;
      if (i.energy == q.energy) s += 1.5;
      if (q.energy == 'low' && i.energy == 'high') s -= 2;
      s -= (i.minutes - q.minutes).abs() / 120;
      if (q.food.isNotEmpty && i.title.toLowerCase().contains(RegExp('cook|food|dinner|picnic'))) s += 1;
      return s;
    }

    // Small random jitter (stable per seed) so "Shuffle" surfaces different good fits.
    final rnd = Random(seed);
    final keyed = {for (final i in pool) i: score(i) + rnd.nextDouble() * 1.5};
    pool.sort((a, b) => keyed[b]!.compareTo(keyed[a]!));
    return pool.take(count).toList();
  }
}
