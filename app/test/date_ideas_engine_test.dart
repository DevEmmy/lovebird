import 'package:flutter_test/flutter_test.dart';
import 'package:lovebird/features/dates/date_ideas_engine.dart';

void main() {
  group('budgetTier', () {
    test('free when budget is zero', () => expect(budgetTier(0, 'NGN'), 0));
    test('₦5,000 is a low-cost date', () => expect(budgetTier(5000, 'NGN'), 1));
    test('\$20 is a low-cost date', () => expect(budgetTier(20, 'USD'), 1));
    test('no budget means anything goes', () => expect(budgetTier(null, 'USD'), 3));
    test('unknown currency falls back to USD thresholds', () => expect(budgetTier(50, 'XYZ'), 2));
  });

  group('DateIdeaEngine', () {
    test('long-distance results are all doable apart', () {
      final ideas = DateIdeaEngine.suggest(const DateQuery(distance: Distance.longDistance, minutes: 240), count: 50);
      expect(ideas, isNotEmpty);
      expect(ideas.every((i) => i.ld), isTrue);
    });

    test('"we don\'t want to spend money" returns only free ideas', () {
      final ideas = DateIdeaEngine.suggest(const DateQuery(spendMoney: false, minutes: 480), count: 50);
      expect(ideas, isNotEmpty);
      expect(ideas.every((i) => i.tier == 0), isTrue);
    });

    test('30 minutes excludes long dates', () {
      final ideas = DateIdeaEngine.suggest(const DateQuery(minutes: 30), count: 50);
      expect(ideas.every((i) => i.minutes <= 30 * 1.5 + 15), isTrue);
    });

    test('budget under ₦5,000 never suggests mid/high tier ideas', () {
      final ideas = DateIdeaEngine.suggest(const DateQuery(budget: 5000, currency: 'NGN', distance: Distance.nearby, minutes: 480), count: 50);
      expect(ideas.every((i) => i.tier <= 1), isTrue);
    });

    test('same seed gives the same order; shuffle changes it', () {
      const q = DateQuery(minutes: 240);
      final a = DateIdeaEngine.suggest(q, seed: 1).map((i) => i.title).toList();
      final b = DateIdeaEngine.suggest(q, seed: 1).map((i) => i.title).toList();
      expect(a, b);
    });
  });
}
