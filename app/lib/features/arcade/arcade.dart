import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../../data/together_repo.dart';
import '../../state/session.dart';
import 'connect_four.dart';
import 'love_pong.dart';
import 'memory_match.dart';
import 'tic_tac_toe.dart';

/// Real two-player arcade games. Turn-based games keep their board in
/// `game_sessions.state` (durable + realtime); Love Pong streams over the
/// private circle channel at ~20 updates/second.
class ArcadeGame {
  const ArcadeGame(this.key, this.title, this.emoji, this.tagline, this.color, this.initialState);
  final String key;
  final String title;
  final String emoji;
  final String tagline;
  final Color color;
  final Map<String, dynamic> Function(String starter, String? partner) initialState;
}

class ArcadeCatalog {
  static final all = <ArcadeGame>[
    ArcadeGame('love_pong', 'Love Pong', '🏓', 'Real-time. First to 7 wins.', const Color(0xFFE0457B),
        (s, p) => {'phase': 'lobby', 'scores': {s: 0, if (p != null) p: 0}}),
    ArcadeGame('connect_four', 'Connect Hearts', '❤️', 'Four in a row before they do.', const Color(0xFFC2185B),
        (s, p) => {'board': List.filled(42, ''), 'turn': s, 'winner': null, 'wins': <String, int>{}, 'line': <int>[]}),
    ArcadeGame('tic_tac_toe', 'Tic-Tac-Love', '💘', 'Classic X & O — hearts & kisses.', const Color(0xFF9C4DCC),
        (s, p) => {'board': List.filled(9, ''), 'turn': s, 'winner': null, 'wins': <String, int>{}, 'line': <int>[]}),
    ArcadeGame('memory_match', 'Memory Match', '🃏', 'Find the pairs. Take turns.', const Color(0xFFD9822B),
        (s, p) => MemoryMatch.newDeck(s)),
  ];

  static ArcadeGame? byKey(String key) {
    for (final g in all) {
      if (g.key == key) return g;
    }
    return null;
  }
}

class ArcadeRepo {
  static Future<String> start({required String circleId, required ArcadeGame game, required String? partnerId}) async {
    final uid = requireUserId();
    final row = await sb
        .from('game_sessions')
        .insert({
          'circle_id': circleId,
          'game_key': game.key,
          'total_rounds': 1,
          'deck': <dynamic>[],
          'turn_user_id': uid,
          'state': game.initialState(uid, partnerId),
          'scores': <String, dynamic>{},
          'started_by': uid,
        })
        .select('id')
        .single();
    final id = row['id'] as String;
    await TogetherRepo.start(circleId: circleId, activity: 'play', refType: 'game', refId: id, title: '${game.emoji} ${game.title}');
    return id;
  }

  static Future<void> setState(String sessionId, Map<String, dynamic> state, {String? turn}) =>
      sb.from('game_sessions').update({'state': state, if (turn != null) 'turn_user_id': turn}).eq('id', sessionId);

  static Future<void> finish(String sessionId) => sb
      .from('game_sessions')
      .update({'status': 'finished', 'finished_at': DateTime.now().toUtc().toIso8601String()}).eq('id', sessionId);
}

/// Routes a session to the right arcade game widget.
class ArcadeView extends ConsumerWidget {
  const ArcadeView({super.key, required this.session});
  final GameSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ArcadeCatalog.byKey(session.gameKey)!;
    final uid = ref.watch(userIdProvider)!;
    final partner = ref.watch(partnerProvider).valueOrNull;
    final me = ref.watch(myProfileProvider).valueOrNull;
    final players = ArcadePlayers(
      me: uid,
      partner: partner?.id ?? '',
      starter: session.startedBy ?? uid,
      myName: me?.displayName ?? 'You',
      partnerName: partner?.displayName ?? 'Partner',
    );
    final body = switch (game.key) {
      'love_pong' => LovePong(session: session, players: players),
      'connect_four' => ConnectFour(session: session, players: players),
      'tic_tac_toe' => TicTacToe(session: session, players: players),
      _ => MemoryMatch(session: session, players: players),
    };
    return Scaffold(
      backgroundColor: game.key == 'love_pong' ? const Color(0xFF1A0B14) : null,
      appBar: AppBar(
        backgroundColor: game.key == 'love_pong' ? const Color(0xFF1A0B14) : null,
        foregroundColor: game.key == 'love_pong' ? Colors.white : null,
        title: Text('${game.emoji} ${game.title}'),
        actions: [_PresenceChip(partnerId: partner?.id, name: players.partnerName, dark: game.key == 'love_pong')],
      ),
      body: SafeArea(child: body),
    );
  }
}

class ArcadePlayers {
  const ArcadePlayers({required this.me, required this.partner, required this.starter, required this.myName, required this.partnerName});
  final String me;
  final String partner;
  final String starter;
  final String myName;
  final String partnerName;
  bool get iStarted => me == starter;
  String other(String uid) => uid == me ? partner : me;
  String nameOf(String? uid) => uid == me ? 'You' : partnerName;
  Color colorOf(String? uid) => uid == starter ? LBColors.rose : const Color(0xFF7E57C2);
  String tokenOf(String? uid) => uid == starter ? '❤️' : '💜';
}

class _PresenceChip extends ConsumerWidget {
  const _PresenceChip({required this.partnerId, required this.name, required this.dark});
  final String? partnerId;
  final String name;
  final bool dark;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ch = ref.watch(circleChannelProvider);
    if (ch == null) return const SizedBox.shrink();
    return ValueListenableBuilder(
      valueListenable: ch.online,
      builder: (context, _, __) {
        final here = ch.isOnline(partnerId);
        return Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle, size: 10, color: here ? LBColors.mint : Colors.grey),
            const SizedBox(width: 6),
            Text(here ? '$name is here' : '$name is away',
                style: TextStyle(color: dark ? Colors.white : null, fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        );
      },
    );
  }
}

/// Shared header for turn-based games: whose turn, tally, result.
class TurnHeader extends StatelessWidget {
  const TurnHeader({super.key, required this.players, required this.turn, required this.winner, required this.wins});
  final ArcadePlayers players;
  final String? turn;
  final String? winner;
  final Map<String, dynamic> wins;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final myWins = (wins[players.me] as num?)?.toInt() ?? 0;
    final theirWins = (wins[players.partner] as num?)?.toInt() ?? 0;
    String msg;
    if (winner == 'draw') {
      msg = 'It\'s a draw 🤝';
    } else if (winner != null) {
      msg = winner == players.me ? 'You win! 🏆' : '${players.partnerName} wins! 🏆';
    } else {
      msg = turn == players.me ? 'Your turn ${players.tokenOf(players.me)}' : '${players.partnerName}\'s turn ${players.tokenOf(players.partner)}';
    }
    return Column(children: [
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _Score(name: 'You', token: players.tokenOf(players.me), score: myWins, color: players.colorOf(players.me)),
        const SizedBox(width: 24),
        Text('vs', style: t.titleMedium),
        const SizedBox(width: 24),
        _Score(name: players.partnerName, token: players.tokenOf(players.partner), score: theirWins, color: players.colorOf(players.partner)),
      ]),
      const SizedBox(height: 12),
      Semantics(liveRegion: true, child: Text(msg, style: t.headlineSmall)),
      const SizedBox(height: 12),
    ]);
  }
}

class _Score extends StatelessWidget {
  const _Score({required this.name, required this.token, required this.score, required this.color});
  final String name;
  final String token;
  final int score;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(children: [
        Text(token, style: const TextStyle(fontSize: 28)),
        Text(name, style: Theme.of(context).textTheme.labelMedium),
        Text('$score', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: color)),
      ]);
}

/// Arcade section shown at the top of the Games screen.
class ArcadeGrid extends StatelessWidget {
  const ArcadeGrid({super.key, required this.onStart, required this.busy});
  final void Function(ArcadeGame) onStart;
  final bool busy;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 700 ? 4 : 2;
      return GridView.count(
        crossAxisCount: cols,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.9,
        children: [
          for (final g in ArcadeCatalog.all)
            Semantics(
              button: true,
              label: '${g.title}. ${g.tagline}',
              child: Material(
                borderRadius: BorderRadius.circular(22),
                clipBehavior: Clip.antiAlias,
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [g.color, Color.lerp(g.color, const Color(0xFF1A0B14), 0.55)!],
                    ),
                  ),
                  child: InkWell(
                    onTap: busy ? null : () => onStart(g),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(g.emoji, style: const TextStyle(fontSize: 34)),
                        const Spacer(),
                        Text(g.title, style: t.titleMedium?.copyWith(color: Colors.white)),
                        const SizedBox(height: 2),
                        Text(g.tagline, style: t.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.9)), maxLines: 2),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(99)),
                          child: const Text('PLAY', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1.2, fontSize: 12)),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}

/// Win/draw banner with rematch for turn games.
class RematchBar extends StatelessWidget {
  const RematchBar({super.key, required this.onRematch});
  final VoidCallback onRematch;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton.icon(onPressed: onRematch, icon: const Icon(Icons.replay_rounded), label: const Text('Rematch')),
      );
}

int randomSeed() => Random().nextInt(1 << 30);

/// Small empty-state while the partner hasn't joined (shared).
class WaitingForPartner extends StatelessWidget {
  const WaitingForPartner({super.key, required this.name, this.dark = false});
  final String name;
  final bool dark;
  @override
  Widget build(BuildContext context) => EmptyState(
        emoji: '⏳',
        title: 'Waiting for $name to join…',
        message: 'They\'ve been invited. The game starts the moment they open it.',
      );
}
