import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/supabase.dart';
import '../../data/models.dart';
import '../../data/together_repo.dart';
import 'game_content.dart';

/// How a game round works.
enum GameMode {
  /// Both answer the same prompt privately, then reveal together (sealed in DB).
  reveal,

  /// One partner (the subject) answers about themselves; the other guesses. Then reveal.
  guess,

  /// Turn-based: whose-turn player gets a card (truth/dare/challenge); partner reacts.
  turn,
}

/// How answers are given.
enum AnswerKind { options, text, scale, none }

class GameDef {
  const GameDef({
    required this.key,
    required this.title,
    required this.emoji,
    required this.tagline,
    required this.color,
    required this.mode,
    required this.answer,
    this.rounds = 10,
    required this.buildDeck,
  });

  final String key;
  final String title;
  final String emoji;
  final String tagline;
  final Color color;
  final GameMode mode;
  final AnswerKind answer;
  final int rounds;

  /// Returns the shuffled deck: each card is {"t": text, "o": [options]?}.
  final List<Map<String, dynamic>> Function(Random rnd) buildDeck;
}

List<Map<String, dynamic>> _texts(List<String> src, Random r) => (List.of(src)..shuffle(r)).map((t) => {'t': t}).toList();
List<Map<String, dynamic>> _pairs(List<List<String>> src, Random r) =>
    (List.of(src)..shuffle(r)).map((p) => {'t': 'Would you rather…', 'o': p}).toList();

class GameCatalog {
  static final all = <GameDef>[
    GameDef(
      key: 'truth_or_dare',
      title: 'Truth or Dare',
      emoji: '🎯',
      tagline: 'Take turns. Choose wisely.',
      color: const Color(0xFFE0457B),
      mode: GameMode.turn,
      answer: AnswerKind.none,
      rounds: 12,
      buildDeck: (r) {
        final t = List.of(truths)..shuffle(r);
        final d = List.of(dares)..shuffle(r);
        return [for (var i = 0; i < 12; i++) {'truth': t[i % t.length], 'dare': d[i % d.length]}];
      },
    ),
    GameDef(
      key: 'would_you_rather',
      title: 'Would You Rather',
      emoji: '🤔',
      tagline: 'Pick secretly, reveal together.',
      color: const Color(0xFF9C4DCC),
      mode: GameMode.reveal,
      answer: AnswerKind.options,
      buildDeck: (r) => _pairs(wouldYouRather, r),
    ),
    GameDef(
      key: 'how_well_know_me',
      title: 'How Well Do You Know Me?',
      emoji: '🧠',
      tagline: 'One answers, one guesses.',
      color: const Color(0xFF2E8B9A),
      mode: GameMode.guess,
      answer: AnswerKind.text,
      buildDeck: (r) => _texts(knowMe, r),
    ),
    GameDef(
      key: 'couple_quiz',
      title: 'Couple Quiz',
      emoji: '💞',
      tagline: 'Do your stories match?',
      color: const Color(0xFFC2185B),
      mode: GameMode.reveal,
      answer: AnswerKind.text,
      buildDeck: (r) => _texts(coupleQuiz, r),
    ),
    GameDef(
      key: 'this_or_that',
      title: 'This or That',
      emoji: '⚡',
      tagline: 'Fast picks. How in sync are you?',
      color: const Color(0xFFD9822B),
      mode: GameMode.reveal,
      answer: AnswerKind.options,
      rounds: 15,
      buildDeck: (r) => (List.of(thisOrThat)..shuffle(r)).map((p) => {'t': 'This or that?', 'o': p}).toList(),
    ),
    GameDef(
      key: 'never_have_i_ever',
      title: 'Never Have I Ever',
      emoji: '🙊',
      tagline: 'Confess together.',
      color: const Color(0xFF5C6BC0),
      mode: GameMode.reveal,
      answer: AnswerKind.options,
      rounds: 12,
      buildDeck: (r) => (List.of(neverHaveIEver)..shuffle(r)).map((t) => {'t': t, 'o': ['I have 🙋', 'Never 🙅']}).toList(),
    ),
    GameDef(
      key: 'guess_my_answer',
      title: 'Guess My Answer',
      emoji: '🔮',
      tagline: 'Predict their pick.',
      color: const Color(0xFF7B5EA7),
      mode: GameMode.guess,
      answer: AnswerKind.options,
      buildDeck: (r) => (List.of(guessMyAnswer)..shuffle(r)).map((q) => {'t': q.first, 'o': q.sublist(1)}).toList(),
    ),
    GameDef(
      key: 'random_challenge',
      title: 'Random Challenge',
      emoji: '🎲',
      tagline: 'Lovebird dares you both.',
      color: const Color(0xFFE8B04B),
      mode: GameMode.turn,
      answer: AnswerKind.none,
      rounds: 6,
      buildDeck: (r) => _texts(challenges, r),
    ),
    GameDef(
      key: 'deep_questions',
      title: 'Deep Questions',
      emoji: '🌙',
      tagline: 'Slow down. Go deeper.',
      color: const Color(0xFF3F3D8F),
      mode: GameMode.reveal,
      answer: AnswerKind.text,
      rounds: 6,
      buildDeck: (r) => _texts(deepQuestions, r),
    ),
    GameDef(
      key: 'funny_questions',
      title: 'Funny Questions',
      emoji: '😂',
      tagline: 'Guaranteed giggles.',
      color: const Color(0xFFF06292),
      mode: GameMode.reveal,
      answer: AnswerKind.text,
      rounds: 8,
      buildDeck: (r) => _texts(funnyQuestions, r),
    ),
    GameDef(
      key: 'compatibility',
      title: 'Compatibility',
      emoji: '🧩',
      tagline: 'Rate 1–5, see where you meet.',
      color: const Color(0xFF7FCBA8),
      mode: GameMode.reveal,
      answer: AnswerKind.scale,
      buildDeck: (r) => _texts(compatibility, r),
    ),
  ];

  static GameDef? byKey(String key) {
    for (final g in all) {
      if (g.key == key) return g;
    }
    return null;
  }
}

/// All game writes. Concurrency: round advances use a compare-and-set on `round`
/// so two partners tapping "Next" at once can't skip a card.
class GameEngine {
  static Future<String> start({required String circleId, required GameDef game, required String? partnerId}) async {
    final uid = requireUserId();
    final rnd = Random();
    final deck = game.buildDeck(rnd).take(game.rounds).toList();
    final row = await sb
        .from('game_sessions')
        .insert({
          'circle_id': circleId,
          'game_key': game.key,
          'total_rounds': deck.length,
          'deck': deck,
          // turn games: starter goes first. guess games: starter is the first subject.
          'turn_user_id': uid,
          'state': <String, dynamic>{},
          'scores': <String, dynamic>{},
          'started_by': uid,
        })
        .select('id')
        .single();
    final id = row['id'] as String;
    await TogetherRepo.start(circleId: circleId, activity: 'play', refType: 'game', refId: id, title: '${game.emoji} ${game.title}');
    return id;
  }

  static Future<void> answer(GameSession s, dynamic answer) => sb.from('game_responses').insert({
        'session_id': s.id,
        'circle_id': s.circleId,
        'round': s.round,
        'user_id': requireUserId(),
        'answer': answer,
      });

  static Future<List<GameResponse>> responses(String sessionId) async {
    final rows = await sb.from('game_responses').select().eq('session_id', sessionId).order('round');
    return rows.map(GameResponse.fromJson).toList();
  }

  static Future<void> setState(GameSession s, Map<String, dynamic> patch) =>
      sb.from('game_sessions').update({'state': {...s.state, ...patch}}).eq('id', s.id).eq('round', s.round);

  static Future<void> addScore(GameSession s, String userId, {int points = 1, String? roundKey}) {
    final scores = Map<String, dynamic>.from(s.scores);
    if (roundKey != null) {
      final scored = List<String>.from((scores['_scored'] as List?) ?? const []);
      if (scored.contains(roundKey)) return Future.value();
      scored.add(roundKey);
      scores['_scored'] = scored;
    }
    scores[userId] = ((scores[userId] as num?) ?? 0) + points;
    return sb.from('game_sessions').update({'scores': scores}).eq('id', s.id);
  }

  /// Advance to the next card, or finish. `partnerId` toggles the turn/subject.
  static Future<void> next(GameSession s, String? partnerId) async {
    if (s.round >= s.totalRounds) {
      await finish(s);
      return;
    }
    final nextTurn = s.turnUserId == s.startedBy ? (partnerId ?? s.startedBy) : s.startedBy;
    await sb
        .from('game_sessions')
        .update({'round': s.round + 1, 'turn_user_id': nextTurn, 'state': <String, dynamic>{}})
        .eq('id', s.id)
        .eq('round', s.round);
  }

  static Future<void> finish(GameSession s) async {
    await sb.from('game_sessions').update({'status': 'finished', 'finished_at': DateTime.now().toUtc().toIso8601String()}).eq('id', s.id);
    await sb.from('together_sessions').update({'status': 'ended', 'ended_at': DateTime.now().toUtc().toIso8601String()})
        .eq('ref_id', s.id);
  }
}
