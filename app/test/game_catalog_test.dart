import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lovebird/features/games/game_engine.dart';

void main() {
  test('catalog contains every game from the brief', () {
    const required = [
      'truth_or_dare', 'would_you_rather', 'how_well_know_me', 'couple_quiz', 'this_or_that', 'never_have_i_ever',
      'guess_my_answer', 'random_challenge', 'deep_questions', 'funny_questions', 'compatibility',
    ];
    for (final k in required) {
      expect(GameCatalog.byKey(k), isNotNull, reason: k);
    }
  });

  for (final g in GameCatalog.all) {
    test('${g.key}: deck has enough cards and correct shape', () {
      final deck = g.buildDeck(Random(42)).take(g.rounds).toList();
      expect(deck.length, g.rounds, reason: 'not enough content for ${g.rounds} rounds');
      for (final card in deck) {
        if (g.key == 'truth_or_dare') {
          expect(card['truth'], isA<String>());
          expect(card['dare'], isA<String>());
        } else {
          expect(card['t'], isA<String>());
        }
        if (g.answer == AnswerKind.options) {
          expect((card['o'] as List).length, greaterThanOrEqualTo(2));
        }
      }
    });
  }

  test('decks are shuffled per session', () {
    final g = GameCatalog.byKey('deep_questions')!;
    final a = g.buildDeck(Random(1)).map((c) => c['t']).toList();
    final b = g.buildDeck(Random(2)).map((c) => c['t']).toList();
    expect(a, isNot(equals(b)));
  });
}
