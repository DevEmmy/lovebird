import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/errors.dart';
import '../../data/models.dart';
import 'arcade.dart';

const _lines = [
  [0, 1, 2], [3, 4, 5], [6, 7, 8],
  [0, 3, 6], [1, 4, 7], [2, 5, 8],
  [0, 4, 8], [2, 4, 6],
];

/// Tic-Tac-Love: ❤️ vs 💜. Board lives in game_sessions.state (realtime).
class TicTacToe extends StatefulWidget {
  const TicTacToe({super.key, required this.session, required this.players});
  final GameSession session;
  final ArcadePlayers players;
  @override
  State<TicTacToe> createState() => _TicTacToeState();
}

class _TicTacToeState extends State<TicTacToe> {
  bool _busy = false;

  List<String> get _board => List<String>.from((widget.session.state['board'] as List?) ?? List.filled(9, ''));
  String? get _turn => widget.session.state['turn'] as String?;
  String? get _winner => widget.session.state['winner'] as String?;
  List<int> get _line => List<int>.from((widget.session.state['line'] as List?) ?? const []);
  Map<String, dynamic> get _wins => Map<String, dynamic>.from((widget.session.state['wins'] as Map?) ?? const {});

  Future<void> _play(int i) async {
    final p = widget.players;
    if (_busy || _winner != null || _turn != p.me || _board[i].isNotEmpty) return;
    HapticFeedback.lightImpact();
    final board = _board..[i] = p.me;
    String? winner;
    var line = <int>[];
    for (final l in _lines) {
      if (board[l[0]].isNotEmpty && board[l[0]] == board[l[1]] && board[l[1]] == board[l[2]]) {
        winner = board[l[0]];
        line = l;
      }
    }
    if (winner == null && board.every((c) => c.isNotEmpty)) winner = 'draw';
    final wins = _wins;
    if (winner != null && winner != 'draw') wins[winner] = ((wins[winner] as num?) ?? 0) + 1;
    setState(() => _busy = true);
    try {
      await ArcadeRepo.setState(widget.session.id, {
        ...widget.session.state,
        'board': board,
        'turn': p.partner,
        'winner': winner,
        'line': line,
        'wins': wins,
      }, turn: p.partner);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rematch() async {
    final p = widget.players;
    // Loser (or the other player after a draw) starts the next round.
    final next = _winner == p.me ? p.partner : p.me;
    await guard(context, () => ArcadeRepo.setState(widget.session.id, {
          ...widget.session.state,
          'board': List.filled(9, ''),
          'turn': next,
          'winner': null,
          'line': <int>[],
        }, turn: next));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.players;
    final board = _board;
    final line = _line;
    return LayoutBuilder(builder: (context, c) {
      final size = (c.maxWidth < c.maxHeight - 260 ? c.maxWidth : c.maxHeight - 260).clamp(240.0, 480.0) - 32;
      return SingleChildScrollView(
        child: Column(children: [
          TurnHeader(players: p, turn: _turn, winner: _winner, wins: _wins),
          SizedBox(
            width: size,
            height: size,
            child: GridView.count(
              crossAxisCount: 3,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              children: [
                for (var i = 0; i < 9; i++)
                  Semantics(
                    button: board[i].isEmpty,
                    label: board[i].isEmpty ? 'Empty square ${i + 1}' : '${p.nameOf(board[i])} square ${i + 1}',
                    child: Material(
                      color: line.contains(i)
                          ? p.colorOf(board[i]).withValues(alpha: 0.25)
                          : Theme.of(context).colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => _play(i),
                        child: Center(
                          child: AnimatedScale(
                            scale: board[i].isEmpty ? 0 : 1,
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutBack,
                            child: Text(board[i].isEmpty ? '' : p.tokenOf(board[i]), style: TextStyle(fontSize: size / 5.5)),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_winner != null) RematchBar(onRematch: _rematch),
        ]),
      );
    });
  }
}
