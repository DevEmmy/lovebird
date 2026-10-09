import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../data/models.dart';
import 'arcade.dart';

const _faces = ['🌹', '💌', '🍫', '🧸', '💍', '🍓', '🎶', '🌙', '🦢', '🍷', '🌻', '🎈'];

/// Memory Match: take turns flipping two cards. A pair scores and you go again.
class MemoryMatch extends StatefulWidget {
  const MemoryMatch({super.key, required this.session, required this.players});
  final GameSession session;
  final ArcadePlayers players;

  static Map<String, dynamic> newDeck(String turn, {Map<String, dynamic>? wins}) {
    final faces = (List.of(_faces)..shuffle(Random())).take(8).toList();
    final deck = [...faces, ...faces]..shuffle(Random());
    return {'deck': deck, 'matched': <int>[], 'open': <int>[], 'turn': turn, 'scores': <String, int>{}, 'winner': null, 'wins': wins ?? <String, int>{}};
  }

  @override
  State<MemoryMatch> createState() => _MemoryMatchState();
}

class _MemoryMatchState extends State<MemoryMatch> {
  bool _busy = false;
  Timer? _flipBack;

  Map<String, dynamic> get _s => widget.session.state;
  List<String> get _deck => List<String>.from((_s['deck'] as List?) ?? const []);
  List<int> get _matched => List<int>.from((_s['matched'] as List?) ?? const []);
  List<int> get _open => List<int>.from((_s['open'] as List?) ?? const []);
  String? get _turn => _s['turn'] as String?;
  Map<String, dynamic> get _scores => Map<String, dynamic>.from((_s['scores'] as Map?) ?? const {});

  @override
  void didUpdateWidget(MemoryMatch old) {
    super.didUpdateWidget(old);
    _scheduleFlipBack();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleFlipBack());
  }

  @override
  void dispose() {
    _flipBack?.cancel();
    super.dispose();
  }

  /// Two non-matching cards are open: show them briefly, then flip back and pass the turn.
  /// The player whose turn it was does this; the partner steps in if they've gone quiet.
  void _scheduleFlipBack() {
    _flipBack?.cancel();
    final open = _open;
    if (open.length != 2) return;
    final mine = _turn == widget.players.me;
    _flipBack = Timer(Duration(milliseconds: mine ? 1100 : 4000), () async {
      if (!mounted || _open.length != 2) return;
      try {
        await ArcadeRepo.setState(widget.session.id, {..._s, 'open': <int>[], 'turn': widget.players.other(_turn ?? widget.players.me)});
      } catch (_) {}
    });
  }

  Future<void> _flip(int i) async {
    final p = widget.players;
    final open = _open;
    final matched = _matched;
    if (_busy || _s['winner'] != null || _turn != p.me || open.length >= 2 || open.contains(i) || matched.contains(i)) return;
    final deck = _deck;
    open.add(i);
    final next = Map<String, dynamic>.from(_s);
    if (open.length == 2 && deck[open[0]] == deck[open[1]]) {
      matched.addAll(open);
      final scores = _scores;
      scores[p.me] = ((scores[p.me] as num?) ?? 0) + 1;
      next['scores'] = scores;
      next['matched'] = matched;
      next['open'] = <int>[];
      if (matched.length == deck.length) {
        final mine = (scores[p.me] as num?) ?? 0;
        final theirs = (scores[p.partner] as num?) ?? 0;
        final winner = mine == theirs ? 'draw' : (mine > theirs ? p.me : p.partner);
        next['winner'] = winner;
        final wins = Map<String, dynamic>.from((_s['wins'] as Map?) ?? const {});
        if (winner != 'draw') wins[winner] = ((wins[winner] as num?) ?? 0) + 1;
        next['wins'] = wins;
      }
    } else {
      next['open'] = open;
    }
    setState(() => _busy = true);
    try {
      await ArcadeRepo.setState(widget.session.id, next);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.players;
    final deck = _deck;
    final open = _open;
    final matched = _matched;
    final scores = _scores;
    final t = Theme.of(context).textTheme;
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - 24).clamp(260.0, 520.0);
      return SingleChildScrollView(
        child: Column(children: [
          TurnHeader(players: p, turn: _turn, winner: _s['winner'] as String?, wins: Map<String, dynamic>.from((_s['wins'] as Map?) ?? const {})),
          Text('Pairs — You ${(scores[p.me] as num?) ?? 0} · ${p.partnerName} ${(scores[p.partner] as num?) ?? 0}', style: t.titleSmall),
          const SizedBox(height: 12),
          SizedBox(
            width: w,
            child: GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                for (var i = 0; i < deck.length; i++)
                  _Card(
                    face: deck[i],
                    up: open.contains(i) || matched.contains(i),
                    matched: matched.contains(i),
                    onTap: () => _flip(i),
                    label: open.contains(i) || matched.contains(i) ? 'Card ${i + 1}: ${deck[i]}' : 'Hidden card ${i + 1}',
                  ),
              ],
            ),
          ),
          if (_s['winner'] != null)
            RematchBar(
              onRematch: () => guard(
                context,
                () => ArcadeRepo.setState(
                  widget.session.id,
                  MemoryMatch.newDeck(_s['winner'] == p.me ? p.partner : p.me, wins: Map<String, dynamic>.from((_s['wins'] as Map?) ?? const {})),
                ),
              ),
            ),
        ]),
      );
    });
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.face, required this.up, required this.matched, required this.onTap, required this.label});
  final String face;
  final bool up;
  final bool matched;
  final VoidCallback onTap;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: !up,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: up ? 1 : 0),
          duration: const Duration(milliseconds: 280),
          builder: (context, v, _) {
            final showFace = v > 0.5;
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateY(pi * v),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: showFace
                      ? null
                      : const LinearGradient(colors: [Color(0xFFC2185B), Color(0xFFF06292)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  color: showFace ? (matched ? const Color(0xFFFDE7EF) : Colors.white) : null,
                  border: Border.all(color: matched ? const Color(0xFFE8B04B) : const Color(0x22000000), width: matched ? 2 : 1),
                ),
                alignment: Alignment.center,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(showFace ? pi : 0),
                  child: Text(showFace ? face : '❤', style: TextStyle(fontSize: 30, color: showFace ? null : Colors.white)),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
