/// Guided Date Night experiences (brief §15). Each step can link into a Lovebird
/// activity so the couple never has to leave the app.
class DateStep {
  const DateStep(this.title, this.body, {this.minutes, this.action, this.actionLabel});
  final String title;
  final String body;
  final int? minutes;

  /// In-app route to open for this step, e.g. "/games?key=deep_questions".
  final String? action;
  final String? actionLabel;
}

class DateGuide {
  const DateGuide({required this.key, required this.title, required this.emoji, required this.blurb, required this.steps});
  final String key;
  final String title;
  final String emoji;
  final String blurb;
  final List<DateStep> steps;
}

class DateNightGuides {
  static const all = <DateGuide>[
    DateGuide(key: 'movie', title: 'Movie Night', emoji: '🎬', blurb: 'Snacks, a film, and commentary only you two get.', steps: [
      DateStep('Set the scene', 'Dim the lights, grab a blanket and your favourite snack. Same snack on both ends = bonus points.', minutes: 5),
      DateStep('Pick the film', 'Choose together from Movie Night — no scrolling for an hour, deal?', action: '/movie', actionLabel: 'Open Movie Night'),
      DateStep('Watch together', 'Play, pause and react in sync. Use the reactions — they float on your partner\'s screen too.'),
      DateStep('Post-credits chat', 'Who was your favourite character? Which scene would you rewrite? Rate it out of 10.', minutes: 10),
    ]),
    DateGuide(key: 'games', title: 'Game Night', emoji: '🎮', blurb: 'Friendly competition. Loser plans the next date.', steps: [
      DateStep('Set the stakes', 'Agree on a fun prize: loser writes a love note, plans the next date, or sings a song.'),
      DateStep('Warm-up round', 'Start light with This or That.', action: '/games?key=this_or_that', actionLabel: 'Play This or That'),
      DateStep('Main event', 'Test how well you really know each other.', action: '/games?key=guess_my_answer', actionLabel: 'Play Guess My Answer'),
      DateStep('Final boss', 'Truth or Dare to finish. Choose wisely.', action: '/games?key=truth_or_dare', actionLabel: 'Play Truth or Dare'),
      DateStep('Crown the winner', 'Announce the champion dramatically. Save the best moment to Our Diary.'),
    ]),
    DateGuide(key: 'deep_talk', title: 'Deep Talk', emoji: '🌙', blurb: 'Phones down (except this one). Go deeper.', steps: [
      DateStep('Get comfortable', 'Somewhere quiet. A warm drink. No other tabs.', minutes: 3),
      DateStep('Check in', 'Each share one high and one low from this week. Just listen — no fixing.', minutes: 10),
      DateStep('Deep Questions', 'Take turns answering. Answers stay hidden until you both lock in.', action: '/games?key=deep_questions', actionLabel: 'Start Deep Questions'),
      DateStep('Say thank you', 'Tell each other one specific thing you appreciated tonight.'),
    ]),
    DateGuide(key: 'laugh', title: 'Laugh Together', emoji: '😂', blurb: 'Silly prompts, guaranteed giggles.', steps: [
      DateStep('Funny Questions', 'The more ridiculous the answer, the better.', action: '/games?key=funny_questions', actionLabel: 'Play Funny Questions'),
      DateStep('Impression battle', 'Do your best impression of each other. 30 seconds each. Judge fairly (you won\'t).', minutes: 3),
      DateStep('Random Challenge', 'Let Lovebird throw challenges at you.', action: '/games?key=random_challenge', actionLabel: 'Get a challenge'),
      DateStep('Save the funniest bit', 'Something too good to forget? Put it in Our Diary.', action: '/diary/new?prompt=funny', actionLabel: 'Write it down'),
    ]),
    DateGuide(key: 'cooking', title: 'Cooking Date', emoji: '🍳', blurb: 'Same recipe, two kitchens (or one).', steps: [
      DateStep('Choose a recipe', 'Pick something you can both make with what you have: pasta, stir-fry, jollof, pancakes…', minutes: 5),
      DateStep('Shopping list', 'Add the ingredients to a shared plan so nobody forgets the onions.', action: '/plans', actionLabel: 'Open Our Plans'),
      DateStep('Prep together', 'Video on, aprons on. Chop, stir, narrate like a cooking show.', minutes: 20),
      DateStep('Cook', 'Keep each other company while it simmers. Rate each other\'s technique.', minutes: 25),
      DateStep('Eat together', 'Plate it nicely, sit down, and eat "together". Cheers!', minutes: 30),
      DateStep('Judge & remember', 'Whose looked better? Snap photos and save the memory.', action: '/memory/new', actionLabel: 'Save a memory'),
    ]),
    DateGuide(key: 'creative', title: 'Creative Date', emoji: '🎨', blurb: 'Make something together.', steps: [
      DateStep('Pick a medium', 'Drawing, a poem, a playlist, a short story — or one of each.'),
      DateStep('Create', 'Use a Create Together prompt.', action: '/create', actionLabel: 'Open Create Together', minutes: 20),
      DateStep('Show and tell', 'Reveal at the same time. Compliments only.'),
      DateStep('Keep it', 'Save your creation to Our Diary or Memories.'),
    ]),
    DateGuide(key: 'study', title: 'Study Date', emoji: '📚', blurb: 'Focus together, celebrate together.', steps: [
      DateStep('Set goals', 'Tell each other what you\'ll get done in the next session.', minutes: 3),
      DateStep('Focus block', 'Cameras optional, mics muted. Just knowing they\'re there helps.', minutes: 25),
      DateStep('Break', 'Stretch, snack, and a quick chat.', minutes: 5),
      DateStep('Focus block', 'One more round.', minutes: 25),
      DateStep('Celebrate', 'Share what you finished. Reward: one round of any game.', action: '/games', actionLabel: 'Pick a game'),
    ]),
    DateGuide(key: 'relax', title: 'Relax Together', emoji: '🕯️', blurb: 'Slow evening. No agenda.', steps: [
      DateStep('Wind down', 'Comfy clothes, low lights, maybe a candle.', minutes: 5),
      DateStep('Read a poem aloud', 'Take turns reading to each other.', action: '/library', actionLabel: 'Open Our Library'),
      DateStep('Gentle talk', 'Light questions only tonight.', action: '/talk', actionLabel: 'Conversation starters'),
      DateStep('Fall asleep on call', 'If you\'re apart: leave the call on. It counts.'),
    ]),
    DateGuide(key: 'relationship', title: 'Relationship Night', emoji: '💞', blurb: 'Check in on "us".', steps: [
      DateStep('Appreciations', 'Three things you appreciate about each other lately.', minutes: 5),
      DateStep('Couple Quiz', 'How well do your stories match?', action: '/games?key=couple_quiz', actionLabel: 'Play Couple Quiz'),
      DateStep('Compatibility', 'Where do you meet, where do you differ?', action: '/games?key=compatibility', actionLabel: 'Play Compatibility'),
      DateStep('Plan ahead', 'Pick one goal and one date to look forward to. Add them to Our Plans.', action: '/plans', actionLabel: 'Open Our Plans'),
    ]),
  ];

  static DateGuide? byKey(String key) {
    for (final g in all) {
      if (g.key == key) return g;
    }
    return null;
  }
}
