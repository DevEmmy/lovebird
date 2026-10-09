import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/supabase.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../state/circle_channel.dart';
import '../../state/session.dart';
import '../arcade/arcade.dart';
import '../diary/diary_repo.dart';
import '../diary/moment_suggester.dart';
import 'game_engine.dart';

final _sessionStream = StreamProvider.autoDispose.family<GameSession?, String>((ref, id) => sb
    .from('game_sessions')
    .stream(primaryKey: ['id'])
    .eq('id', id)
    .map((rows) => rows.isEmpty ? null : GameSession.fromJson(rows.first)));

class GameSessionScreen extends ConsumerStatefulWidget {
  const GameSessionScreen({super.key, required this.sessionId});
  final String sessionId;
  @override
  ConsumerState<GameSessionScreen> createState() => _GameSessionScreenState();
}

class _GameSessionScreenState extends ConsumerState<GameSessionScreen> {
  List<GameResponse> _responses = const [];
  StreamSubscription<dynamic>? _respSub;
  StreamSubscription<Map<String, dynamic>>? _gameSub;
  StreamSubscription<Map<String, dynamic>>? _reactSub;
  final _floating = <(int, String)>[];
  int _floatId = 0;
  final _text = TextEditingController();
  int _scale = 3;
  bool _busy = false;
  bool _suggested = false;
  final _scoredRounds = <int>{};
  CircleChannel? _channel;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Partner's rows arrive here only once RLS lets us see them (sealed answers).
    _respSub = sb.from('game_responses').stream(primaryKey: ['id']).eq('session_id', widget.sessionId).listen((_) => _refresh());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ch = ref.read(circleChannelProvider);
      _channel = ch;
      ch?.setActivity('playing');
      _gameSub = ch?.on('game').listen((e) {
        if (e['session'] == widget.sessionId) _refresh();
      });
      _reactSub = ch?.on('reaction').listen((e) {
        if (e['session'] == widget.sessionId) _float(e['emoji'] as String? ?? '❤️');
      });
    });
  }

  @override
  void dispose() {
    _respSub?.cancel();
    _gameSub?.cancel();
    _reactSub?.cancel();
    _text.dispose();
    _channel?.setActivity(null);
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final r = await GameEngine.responses(widget.sessionId);
      if (mounted) setState(() => _responses = r);
    } catch (_) {}
  }

  void _ping() => ref.read(circleChannelProvider)?.send('game', {'session': widget.sessionId});

  void _float(String emoji) {
    final id = _floatId++;
    setState(() => _floating.add((id, emoji)));
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _floating.removeWhere((f) => f.$1 == id));
    });
  }

  void _react(String emoji) {
    _float(emoji);
    ref.read(circleChannelProvider)?.send('reaction', {'session': widget.sessionId, 'emoji': emoji});
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      _ping();
      await _refresh();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit(GameSession s, dynamic answer) => _run(() async {
        await GameEngine.answer(s, answer);
        _text.clear();
        _scale = 3;
      });

  String _fill(String text, {required bool aboutMe, required String partnerName}) {
    if (aboutMe) {
      return text.replaceAll("{p}'s", 'your').replaceAll('{p}’s', 'your').replaceAll('{p}', 'you');
    }
    return text.replaceAll('{p}', partnerName);
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(_sessionStream(widget.sessionId));
    final uid = ref.watch(userIdProvider)!;
    final partner = ref.watch(partnerProvider).valueOrNull;
    final channel = ref.watch(circleChannelProvider);

    ref.listen(_sessionStream(widget.sessionId), (prev, next) {
      if (prev?.valueOrNull?.round != next.valueOrNull?.round) _refresh();
    });

    return sessionAsync.when(
      loading: () => const Scaffold(body: LoadingView()),
      error: (e, _) => Scaffold(appBar: AppBar(), body: ErrorView(error: e, onRetry: () => ref.invalidate(_sessionStream(widget.sessionId)))),
      data: (s) {
        if (s == null) return Scaffold(appBar: AppBar(), body: const ErrorView(error: 'not found'));
        if (ArcadeCatalog.byKey(s.gameKey) != null) return ArcadeView(session: s);
        final game = GameCatalog.byKey(s.gameKey);
        if (game == null) return Scaffold(appBar: AppBar(), body: const ErrorView(error: 'unknown game'));
        return Scaffold(
          appBar: AppBar(
            title: Text('${game.emoji} ${game.title}'),
            actions: [
              if (channel != null)
                ValueListenableBuilder(
                  valueListenable: channel.online,
                  builder: (context, _, __) {
                    final here = channel.isOnline(partner?.id);
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: PillTag(
                        here ? '${partner?.displayName ?? 'Partner'} is here' : '${partner?.displayName ?? 'Partner'} is away',
                        color: here ? LBColors.mint.withValues(alpha: 0.25) : null,
                        icon: here ? Icons.circle : Icons.circle_outlined,
                      ),
                    );
                  },
                ),
              if (s.active)
                IconButton(
                  tooltip: 'End game',
                  icon: const Icon(Icons.flag_outlined),
                  onPressed: () async {
                    final ok = await confirmDialog(context, title: 'End this game?', message: 'You can always start a new one.', confirm: 'End game');
                    if (ok) await _run(() => GameEngine.finish(s));
                  },
                ),
            ],
          ),
          body: Stack(children: [
            Constrained(
              maxWidth: 640,
              child: s.active ? _roundView(s, game, uid, partner) : _summary(s, game, uid, partner),
            ),
            // Floating reactions
            for (final f in _floating)
              _FloatingEmoji(key: ValueKey(f.$1), emoji: f.$2),
          ]),
        );
      },
    );
  }

  Widget _roundView(GameSession s, GameDef game, String uid, Profile? partner) {
    final t = Theme.of(context).textTheme;
    final partnerName = partner?.displayName ?? 'your partner';
    final card = Map<String, dynamic>.from(s.deck[(s.round - 1).clamp(0, s.deck.length - 1)] as Map);
    final roundResponses = _responses.where((r) => r.round == s.round).toList();
    final mine = roundResponses.where((r) => r.userId == uid).firstOrNull;
    final theirs = roundResponses.where((r) => r.userId != uid).firstOrNull;
    final myTurn = s.turnUserId == uid;

    Widget progress = Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(children: [
        Row(children: [
          Text('Round ${s.round} of ${s.totalRounds}', style: t.labelMedium),
          const Spacer(),
          if (game.mode == GameMode.guess || game.key == 'random_challenge') Text(_scoreLine(s, uid, partner), style: t.labelMedium),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: s.round / s.totalRounds, minHeight: 6, color: game.color),
        ),
      ]),
    );

    Widget body;
    switch (game.mode) {
      case GameMode.turn:
        body = _turnRound(s, game, card, myTurn, partnerName, uid, partner);
      case GameMode.reveal:
      case GameMode.guess:
        final subjectIsMe = s.turnUserId == uid;
        String prompt = card['t'] as String;
        if (game.mode == GameMode.guess) {
          prompt = _fill(prompt, aboutMe: subjectIsMe, partnerName: partnerName);
        }
        final options = (card['o'] as List?)?.cast<String>();
        body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _PromptCard(
            color: game.color,
            label: game.mode == GameMode.guess
                ? (subjectIsMe ? 'Answer honestly — $partnerName is guessing' : 'Guess what $partnerName will say')
                : null,
            text: prompt,
          ),
          const SizedBox(height: 20),
          if (mine == null)
            _answerInput(s, game, options)
          else if (theirs == null)
            _Waiting(partnerName: partnerName, myAnswer: _fmtAnswer(mine.answer), onNudge: () {
              ref.read(circleChannelProvider)?.send('nudge', {'session': s.id});
              showToast(context, 'Nudged $partnerName 💌');
            })
          else
            _reveal(s, game, mine, theirs, uid, partnerName, subjectIsMe),
        ]);
    }

    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      progress,
      Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 0), child: body),
    ]);
  }

  String _scoreLine(GameSession s, String uid, Profile? partner) {
    final me = (s.scores[uid] as num?)?.toInt() ?? 0;
    final them = partner == null ? 0 : (s.scores[partner.id] as num?)?.toInt() ?? 0;
    return 'You $me · ${partner?.displayName ?? 'Partner'} $them';
  }

  String _fmtAnswer(dynamic a) {
    if (a is num) return '$a / 5';
    if (a is String) return a;
    return '$a';
  }

  Widget _answerInput(GameSession s, GameDef game, List<String>? options) {
    switch (game.answer) {
      case AnswerKind.options:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final o in options ?? const <String>[])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(60), side: BorderSide(color: game.color, width: 1.5)),
                onPressed: _busy ? null : () => _submit(s, o),
                child: Text(o, textAlign: TextAlign.center),
              ),
            ),
        ]);
      case AnswerKind.scale:
        return StatefulBuilder(builder: (context, setLocal) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [Text('Not at all'), Text('Totally')]),
            Slider(
              value: _scale.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              label: '$_scale',
              semanticFormatterCallback: (v) => '${v.round()} out of 5',
              onChanged: (v) => setLocal(() => _scale = v.round()),
            ),
            FilledButton(onPressed: _busy ? null : () => _submit(s, _scale), child: Text('Lock in $_scale')),
          ]);
        });
      case AnswerKind.text:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _text,
            maxLines: 4,
            minLines: 2,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Your answer (hidden until you both answer)'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy
                ? null
                : () {
                    final v = _text.text.trim();
                    if (v.isEmpty) return;
                    _submit(s, v);
                  },
            child: const Text('Lock in answer 🔒'),
          ),
        ]);
      case AnswerKind.none:
        return const SizedBox.shrink();
    }
  }

  Widget _reveal(GameSession s, GameDef game, GameResponse mine, GameResponse theirs, String uid, String partnerName, bool subjectIsMe) {
    final t = Theme.of(context).textTheme;
    final a = mine.answer, b = theirs.answer;
    String? verdict;
    bool? matched;
    if (game.answer == AnswerKind.options) {
      matched = a == b;
    } else if (game.answer == AnswerKind.scale && a is num && b is num) {
      final d = (a - b).abs();
      matched = d <= 1;
      verdict = d == 0 ? 'Perfectly in sync 💞' : (d == 1 ? 'Close enough 😊' : 'Opposites attract? 😅');
    }
    if (game.mode == GameMode.guess && game.answer == AnswerKind.options) {
      verdict = matched! ? (subjectIsMe ? '$partnerName knows you! 🔮' : 'You nailed it! 🔮') : (subjectIsMe ? '$partnerName missed this one 😄' : 'Not quite 😄');
      // The guesser scores; dedupe so both devices don't double-count.
      // Only the guesser's device records the point, once per round.
      if (matched && !subjectIsMe && _scoredRounds.add(s.round)) {
        GameEngine.addScore(s, uid, roundKey: 'r${s.round}').catchError((_) {});
      }
    } else if (matched != null && verdict == null) {
      verdict = matched ? 'Same answer! 💞' : 'Different picks — talk about it! 💬';
    }

    final textJudge = game.answer == AnswerKind.text && game.mode == GameMode.guess && subjectIsMe;
    final quizJudge = game.key == 'couple_quiz' && s.turnUserId == uid;
    final judged = s.state['judged'] == true;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _AnswerCard(label: 'You', answer: _fmtAnswer(a), color: game.color)),
        const SizedBox(width: 10),
        Expanded(child: _AnswerCard(label: partnerName, answer: _fmtAnswer(b), color: game.color)),
      ]),
      if (verdict != null) ...[
        const SizedBox(height: 16),
        Text(verdict, style: t.titleLarge, textAlign: TextAlign.center),
      ],
      if ((textJudge || quizJudge) && !judged) ...[
        const SizedBox(height: 16),
        Text(textJudge ? 'Did $partnerName get it right?' : 'Did your answers match?', style: t.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => _run(() => GameEngine.setState(s, {'judged': true, 'match': false})),
              child: const Text('Not quite'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: () => _run(() async {
                await GameEngine.setState(s, {'judged': true, 'match': true});
                await GameEngine.addScore(s, textJudge ? theirs.userId : '_matches', roundKey: 'r${s.round}');
              }),
              child: Text(textJudge ? 'Got it! ✅' : 'Match! 💞'),
            ),
          ),
        ]),
      ],
      if (judged) ...[
        const SizedBox(height: 12),
        Text(s.state['match'] == true ? 'Match! 💞' : 'Not this time 😄', style: t.titleLarge, textAlign: TextAlign.center),
      ],
      const SizedBox(height: 16),
      _ReactionBar(onReact: _react),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _busy || ((textJudge || quizJudge) && !judged) ? null : () => _run(() => GameEngine.next(s, ref.read(partnerProvider).valueOrNull?.id)),
        child: Text(s.round >= s.totalRounds ? 'See results' : 'Next round'),
      ),
    ]);
  }

  Widget _turnRound(GameSession s, GameDef game, Map<String, dynamic> card, bool myTurn, String partnerName, String uid, Profile? partner) {
    final t = Theme.of(context).textTheme;
    if (game.key == 'truth_or_dare') {
      final choice = s.state['choice'] as String?;
      if (choice == null) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _PromptCard(color: game.color, text: myTurn ? 'Your turn! Truth or dare?' : '$partnerName is choosing…'),
          const SizedBox(height: 20),
          if (myTurn)
            Row(children: [
              Expanded(child: FilledButton(onPressed: _busy ? null : () => _run(() => GameEngine.setState(s, {'choice': 'truth'})), child: const Text('Truth 🫣'))),
              const SizedBox(width: 12),
              Expanded(child: FilledButton(onPressed: _busy ? null : () => _run(() => GameEngine.setState(s, {'choice': 'dare'})), child: const Text('Dare 🔥'))),
            ])
          else
            const Center(child: Text('⏳', style: TextStyle(fontSize: 40))),
        ]);
      }
      final text = card[choice] as String? ?? '';
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _PromptCard(
          color: game.color,
          label: myTurn ? 'You chose ${choice == 'truth' ? 'Truth' : 'Dare'}' : '$partnerName chose ${choice == 'truth' ? 'Truth' : 'Dare'}',
          text: text,
        ),
        const SizedBox(height: 12),
        Text(myTurn ? 'Answer out loud or in chat — then tap done.' : 'Cheer them on 👇', style: t.bodyMedium, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        _ReactionBar(onReact: _react),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : () => _run(() => GameEngine.next(s, partner?.id)),
          child: Text(s.round >= s.totalRounds ? 'Finish' : (myTurn ? 'Done — $partnerName\'s turn' : 'Next')),
        ),
      ]);
    }

    // Random Challenge: both see the same challenge; pick the winner.
    final judged = s.state['winner'] as String?;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _PromptCard(color: game.color, label: 'Challenge ${s.round}', text: card['t'] as String),
      const SizedBox(height: 20),
      if (judged == null) ...[
        Text('Who won this one?', style: t.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          OutlinedButton(onPressed: () => _run(() async {
                await GameEngine.setState(s, {'winner': uid});
                await GameEngine.addScore(s, uid, roundKey: 'r${s.round}');
              }), child: const Text('Me 🙋')),
          OutlinedButton(onPressed: partner == null ? null : () => _run(() async {
                await GameEngine.setState(s, {'winner': partner.id});
                await GameEngine.addScore(s, partner.id, roundKey: 'r${s.round}');
              }), child: Text(partnerName)),
          OutlinedButton(onPressed: () => _run(() => GameEngine.setState(s, {'winner': 'tie'})), child: const Text('Both of us 💞')),
        ]),
      ] else
        Text(judged == 'tie' ? 'You both won 💞' : (judged == uid ? 'You won this one! 🏆' : '$partnerName won this one! 🏆'),
            style: t.titleLarge, textAlign: TextAlign.center),
      const SizedBox(height: 16),
      _ReactionBar(onReact: _react),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _busy ? null : () => _run(() => GameEngine.next(s, partner?.id)),
        child: Text(s.round >= s.totalRounds ? 'See results' : 'Next challenge'),
      ),
    ]);
  }

  Widget _summary(GameSession s, GameDef game, String uid, Profile? partner) {
    final t = Theme.of(context).textTheme;
    final partnerName = partner?.displayName ?? 'Partner';
    String headline;
    String sub;
    int? matchPct;
    if (game.mode == GameMode.reveal && (game.answer == AnswerKind.options || game.answer == AnswerKind.scale)) {
      var both = 0, same = 0;
      for (var r = 1; r <= s.totalRounds; r++) {
        final rr = _responses.where((x) => x.round == r).toList();
        if (rr.length == 2) {
          both++;
          final a = rr[0].answer, b = rr[1].answer;
          if (game.answer == AnswerKind.scale && a is num && b is num ? (a - b).abs() <= 1 : a == b) same++;
        }
      }
      matchPct = both == 0 ? 0 : (same * 100 / both).round();
      headline = '$matchPct% in sync 💞';
      sub = 'You matched on $same of $both rounds.';
    } else if (game.mode == GameMode.guess || game.key == 'random_challenge') {
      final me = (s.scores[uid] as num?)?.toInt() ?? 0;
      final them = partner == null ? 0 : (s.scores[partner.id] as num?)?.toInt() ?? 0;
      headline = me == them ? 'It\'s a tie! 💞' : (me > them ? 'You win! 🏆' : '$partnerName wins! 🏆');
      sub = 'You $me · $partnerName $them';
    } else if (game.key == 'couple_quiz') {
      final m = (s.scores['_matches'] as num?)?.toInt() ?? 0;
      matchPct = (m * 100 / s.totalRounds).round();
      headline = '$m of ${s.totalRounds} stories matched';
      sub = 'Your shared history, in numbers 💞';
    } else {
      headline = 'Game complete 🎉';
      sub = '${s.totalRounds} rounds together.';
    }

    if (!_suggested && (matchPct ?? 0) >= 70) {
      _suggested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        MomentSuggester.maybeSuggest(
          context,
          s.circleId,
          MomentSuggestion(
            kind: 'game_result',
            headline: 'You two really need to remember this one 😂',
            prompt: 'Add it to Our Diary?',
            entryType: 'game',
            title: '${game.emoji} ${game.title}: $headline',
            payload: {'game_key': game.key, 'session_id': s.id, 'result': headline},
          ),
        );
      });
    }

    return ListView(padding: const EdgeInsets.all(24), children: [
      const SizedBox(height: 24),
      Center(child: Text(game.emoji, style: const TextStyle(fontSize: 64))),
      const SizedBox(height: 12),
      Text(headline, style: t.headlineMedium, textAlign: TextAlign.center),
      const SizedBox(height: 6),
      Text(sub, style: t.bodyLarge, textAlign: TextAlign.center),
      const SizedBox(height: 28),
      AsyncButton(
        icon: Icons.auto_stories_outlined,
        onPressed: () async {
          await DiaryRepo.create(
            circleId: s.circleId,
            entryType: 'game',
            origin: 'together',
            title: '${game.emoji} ${game.title}',
            body: '$headline\n$sub',
            payload: {'game_key': game.key, 'session_id': s.id},
          );
          if (mounted) showToast(context, 'Saved to Our Diary ❤️');
        },
        child: const Text('Save to Our Diary'),
      ),
      const SizedBox(height: 10),
      OutlinedButton(
        onPressed: () async {
          final id = await guard(context, () => GameEngine.start(circleId: s.circleId, game: game, partnerId: partner?.id));
          ref.invalidate(gameHistoryProvider);
          if (id != null && mounted) context.pushReplacement('/game/$id');
        },
        child: const Text('Play again'),
      ),
      const SizedBox(height: 10),
      TextButton(onPressed: () => context.pop(), child: const Text('Back to games')),
      if (game.mode == GameMode.reveal && game.answer == AnswerKind.text) ...[
        const SectionHeader('Your answers'),
        for (var r = 1; r <= s.totalRounds; r++) _AnswersRecap(s: s, round: r, responses: _responses, uid: uid, partnerName: partnerName),
      ],
    ]);
  }
}

class _AnswersRecap extends StatelessWidget {
  const _AnswersRecap({required this.s, required this.round, required this.responses, required this.uid, required this.partnerName});
  final GameSession s;
  final int round;
  final List<GameResponse> responses;
  final String uid;
  final String partnerName;
  @override
  Widget build(BuildContext context) {
    final rr = responses.where((x) => x.round == round).toList();
    if (rr.isEmpty) return const SizedBox.shrink();
    final card = Map<String, dynamic>.from(s.deck[round - 1] as Map);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LBCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(card['t'] as String, style: t.titleSmall),
          const SizedBox(height: 6),
          for (final r in rr) Text('${r.userId == uid ? 'You' : partnerName}: ${r.answer}', style: t.bodyMedium),
        ]),
      ),
    );
  }
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({required this.color, required this.text, this.label});
  final Color color;
  final String text;
  final String? label;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(minHeight: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color, Color.lerp(color, Colors.black, 0.25)!]),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 10))],
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (label != null) ...[
            Text(label!, style: t.labelLarge?.copyWith(color: Colors.white), textAlign: TextAlign.center),
            const SizedBox(height: 10),
          ],
          Text(text, style: t.headlineSmall?.copyWith(color: Colors.white), textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.label, required this.answer, required this.color});
  final String label;
  final String answer;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduce ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutBack,
      builder: (context, v, child) => Transform.scale(scale: 0.85 + 0.15 * v, child: Opacity(opacity: v.clamp(0.0, 1.0), child: child)),
      child: LBCard(
        color: color.withValues(alpha: 0.1),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          Text(answer, style: Theme.of(context).textTheme.titleMedium),
        ]),
      ),
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.partnerName, required this.myAnswer, required this.onNudge});
  final String partnerName;
  final String myAnswer;
  final VoidCallback onNudge;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LBCard(child: Text('🔒 Your answer: $myAnswer', style: t.bodyLarge)),
      const SizedBox(height: 20),
      Semantics(liveRegion: true, child: Text('Waiting for $partnerName…', style: t.titleMedium, textAlign: TextAlign.center)),
      const SizedBox(height: 6),
      Text('Answers reveal the moment you\'ve both locked in.', style: t.bodySmall, textAlign: TextAlign.center),
      const SizedBox(height: 12),
      TextButton.icon(onPressed: onNudge, icon: const Icon(Icons.notifications_active_outlined), label: Text('Nudge $partnerName')),
    ]);
  }
}

class _ReactionBar extends StatelessWidget {
  const _ReactionBar({required this.onReact});
  final ValueChanged<String> onReact;
  @override
  Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (final e in const ['😂', '😍', '😮', '🥺', '🔥', '👏'])
          IconButton(tooltip: 'React $e', onPressed: () => onReact(e), icon: Text(e, style: const TextStyle(fontSize: 26))),
      ]);
}

class _FloatingEmoji extends StatefulWidget {
  const _FloatingEmoji({super.key, required this.emoji});
  final String emoji;
  @override
  State<_FloatingEmoji> createState() => _FloatingEmojiState();
}

class _FloatingEmojiState extends State<_FloatingEmoji> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700))..forward();
  late final double _x = 0.2 + (widget.emoji.hashCode % 60) / 100;
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Positioned(
        left: MediaQuery.sizeOf(context).width * _x,
        bottom: 80 + 260 * _c.value,
        child: IgnorePointer(child: Opacity(opacity: 1 - _c.value, child: Text(widget.emoji, style: const TextStyle(fontSize: 40)))),
      ),
    );
  }
}
