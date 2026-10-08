import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/widgets/widgets.dart';
import '../../data/ai_repo.dart';
import '../../state/session.dart';
import '../games/game_content.dart';

/// Conversation starters (Together → Talk). Both partners see the same card in real time.
class TalkScreen extends ConsumerStatefulWidget {
  const TalkScreen({super.key});
  @override
  ConsumerState<TalkScreen> createState() => _TalkScreenState();
}

class _TalkScreenState extends ConsumerState<TalkScreen> {
  static const moods = {
    'light': ('☀️', 'Light & easy'),
    'deep': ('🌙', 'Deep'),
    'funny': ('😂', 'Funny'),
    'romantic': ('❤️', 'Romantic'),
  };
  static const _romantic = [
    'What\'s your favourite photo of us, and why?',
    'When did you first think "this is my person"?',
    'What\'s the most romantic thing I\'ve done without realising?',
    'If you could relive one day with me, which one?',
    'What\'s something about me you\'d never want to change?',
    'Where would you take me on a perfect date, money no object?',
    'What song would you play at our anniversary dinner?',
    'What\'s a small way I could make you feel loved this week?',
  ];
  static const _light = [
    'What was the best part of your day?',
    'What\'s a tiny thing that made you smile recently?',
    'What are you looking forward to this month?',
    'What\'s something new you learned this week?',
    'If tomorrow was a free day, how would you spend it?',
    'What\'s a food you could eat every day?',
    'What show should we watch next?',
    'What\'s a place near you that you think I\'d love?',
  ];

  String _mood = 'light';
  List<String> _deck = [];
  int _i = 0;
  bool _loadingAi = false;
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _shuffle();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sub = ref.read(circleChannelProvider)?.on('together').listen((e) {
        if (e['type'] != 'talk' || !mounted) return;
        setState(() {
          _mood = e['mood'] as String? ?? _mood;
          _deck = List<String>.from(e['deck'] as List? ?? _deck);
          _i = (e['i'] as num?)?.toInt() ?? _i;
        });
      });
    });
  }

  void _shuffle() {
    final src = switch (_mood) {
      'deep' => deepQuestions,
      'funny' => funnyQuestions,
      'romantic' => _romantic,
      _ => _light,
    };
    _deck = List.of(src)..shuffle(Random());
    _i = 0;
  }

  void _sync() => ref.read(circleChannelProvider)?.send('together', {'type': 'talk', 'mood': _mood, 'deck': _deck, 'i': _i});

  Future<void> _ai() async {
    setState(() => _loadingAi = true);
    try {
      final r = await AiRepo.ask('conversation_starters', {'mood': moods[_mood]!.$2, 'depth': _mood == 'deep' ? 'deep' : 'mixed'});
      final qs = ((r['questions'] as List?) ?? const []).map((q) => (q as Map)['text'] as String).toList();
      if (qs.isNotEmpty) {
        setState(() {
          _deck = qs;
          _i = 0;
        });
        _sync();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loadingAi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final q = _deck.isEmpty ? '' : _deck[_i % _deck.length];
    return Scaffold(
      appBar: AppBar(title: const Text('Let\'s talk 💬')),
      body: Constrained(
        maxWidth: 640,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final m in moods.entries)
              ChoiceChip(
                label: Text('${m.value.$1} ${m.value.$2}'),
                selected: _mood == m.key,
                onSelected: (_) {
                  setState(() {
                    _mood = m.key;
                    _shuffle();
                  });
                  _sync();
                },
              ),
          ]),
          const SizedBox(height: 24),
          Semantics(
            liveRegion: true,
            child: LBCard(
              padding: const EdgeInsets.all(28),
              color: Theme.of(context).colorScheme.primaryContainer,
              child: SizedBox(
                height: 200,
                child: Center(child: Text(q, style: t.headlineSmall, textAlign: TextAlign.center)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('Card ${(_i % (_deck.isEmpty ? 1 : _deck.length)) + 1} of ${_deck.length} · your partner sees the same card', style: t.bodySmall, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _i == 0 ? null : () {
                  setState(() => _i--);
                  _sync();
                },
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () {
                  setState(() => _i++);
                  _sync();
                },
                child: const Text('Next question'),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: _loadingAi ? null : _ai,
            icon: _loadingAi ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome),
            label: const Text('Fresh questions from Lovebird AI'),
          ),
        ]),
      ),
    );
  }
}
