import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/errors.dart';
import '../../data/models.dart';
import 'arcade.dart';

const _cols = 7;
const _rows = 6;

/// Connect Hearts (Connect Four). 7×6 board, drop hearts, four in a row wins.
class ConnectFour extends StatefulWidget {
  const ConnectFour({super.key, required this.session, required this.players});
  final GameSession session;
  final ArcadePlayers players;
  @override
  State<ConnectFour> createState() => _ConnectFourState();
}

class _ConnectFourState extends State<ConnectFour> {
  bool _busy = false;
  int? _hover;

  List<String> get _board => List<String>.from((widget.session.state['board'] as List?) ?? List.filled(42, ''));
  String? get _turn => widget.session.state['turn'] as String?;
  String? get _winner => widget.session.state['winner'] as String?;
  List<int> get _line => List<int>.from((widget.session.state['line'] as List?) ?? const []);
  Map<String, dynamic> get _wins => Map<String, dynamic>.from((widget.session.state['wins'] as Map?) ?? const {});

  static List<int>? _findLine(List<String> b, int idx) {
    final who = b[idx];
    final r0 = idx ~/ _cols, c0 = idx % _cols;
    for (final d in const [(0, 1), (1, 0), (1, 1), (1, -1)]) {
      final cells = <int>[idx];
      for (final sign in const [1, -1]) {
        var r = r0 + d.$1 * sign, c = c0 + d.$2 * sign;
        while (r >= 0 && r < _rows && c >= 0 && c < _cols && b[r * _cols + c] == who) {
          cells.add(r * _cols + c);
          r += d.$1 * sign;
          c += d.$2 * sign;
        }
      }
      if (cells.length >= 4) return cells;
    }
    return null;
  }

  Future<void> _drop(int col) async {
    final p = widget.players;
    if (_busy || _winner != null || _turn != p.me) return;
    final board = _board;
    int? idx;
    for (var r = _rows - 1; r >= 0; r--) {
      if (board[r * _cols + col].isEmpty) {
        idx = r * _cols + col;
        break;
      }
    }
    if (idx == null) return; // column full
    HapticFeedback.mediumImpact();
    board[idx] = p.me;
    final line = _findLine(board, idx);
    String? winner = line != null ? p.me : null;
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
        'line': line ?? <int>[],
        'last': idx,
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
    final next = _winner == p.me ? p.partner : p.me;
    await guard(context, () => ArcadeRepo.setState(widget.session.id, {
          ...widget.session.state,
          'board': List.filled(42, ''),
          'turn': next,
          'winner': null,
          'line': <int>[],
          'last': null,
        }, turn: next));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.players;
    final board = _board;
    final line = _line;
    final last = widget.session.state['last'] as int?;
    final myTurn = _turn == p.me && _winner == null;
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - 24).clamp(260.0, 560.0);
      final cell = w / _cols;
      return SingleChildScrollView(
        child: Column(children: [
          TurnHeader(players: p, turn: _turn, winner: _winner, wins: _wins),
          // Column pickers (also the tap targets)
          SizedBox(
            width: w,
            height: cell * (_rows + 0.8),
            child: Stack(children: [
              Positioned(
                top: cell * 0.8,
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF8E0E43), Color(0xFFC2185B)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
              for (var col = 0; col < _cols; col++)
                Positioned(
                  left: col * cell,
                  top: 0,
                  width: cell,
                  bottom: 0,
                  child: Semantics(
                    button: true,
                    label: 'Drop in column ${col + 1}',
                    child: MouseRegion(
                      onEnter: (_) => setState(() => _hover = col),
                      onExit: (_) => setState(() => _hover = null),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _drop(col),
                        child: Column(children: [
                          SizedBox(
                            height: cell * 0.8,
                            child: Center(
                              child: AnimatedOpacity(
                                opacity: myTurn && _hover == col ? 1 : 0,
                                duration: const Duration(milliseconds: 120),
                                child: Text(p.tokenOf(p.me), style: TextStyle(fontSize: cell * 0.5)),
                              ),
                            ),
                          ),
                          for (var r = 0; r < _rows; r++)
                            SizedBox(
                              width: cell,
                              height: cell,
                              child: Padding(
                                padding: EdgeInsets.all(cell * 0.08),
                                child: _Slot(
                                  owner: board[r * _cols + col],
                                  players: p,
                                  highlight: line.contains(r * _cols + col),
                                  justDropped: last == r * _cols + col,
                                  rowFromTop: r,
                                  cell: cell,
                                ),
                              ),
                            ),
                        ]),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
          if (_winner != null) RematchBar(onRematch: _rematch),
          if (_winner == null && !myTurn)
            Padding(padding: const EdgeInsets.all(16), child: Text('Waiting for ${p.partnerName}…', style: Theme.of(context).textTheme.bodyMedium)),
        ]),
      );
    });
  }
}

class _Slot extends StatelessWidget {
  const _Slot({required this.owner, required this.players, required this.highlight, required this.justDropped, required this.rowFromTop, required this.cell});
  final String owner;
  final ArcadePlayers players;
  final bool highlight;
  final bool justDropped;
  final int rowFromTop;
  final double cell;
  @override
  Widget build(BuildContext context) {
    final empty = owner.isEmpty;
    final disc = Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: empty ? const Color(0xFF2A0F1E) : Colors.white,
        border: highlight ? Border.all(color: const Color(0xFFFFD54F), width: 3) : null,
        boxShadow: empty ? null : [BoxShadow(color: players.colorOf(owner).withValues(alpha: 0.6), blurRadius: 10)],
      ),
      alignment: Alignment.center,
      child: empty ? null : Text(players.tokenOf(owner), style: TextStyle(fontSize: cell * 0.48)),
    );
    if (!justDropped || MediaQuery.of(context).disableAnimations) return disc;
    // Drop animation from the top of the board
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: -(rowFromTop + 1) * cell, end: 0),
      duration: Duration(milliseconds: 220 + rowFromTop * 60),
      curve: Curves.bounceOut,
      builder: (_, dy, child) => Transform.translate(offset: Offset(0, dy), child: child),
      child: disc,
    );
  }
}
