import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../data/models.dart';
import '../../state/circle_channel.dart';
import '../../state/session.dart';
import 'arcade.dart';

/// Love Pong — real-time two-player pong over the private circle channel.
///
/// Netcode: the player who started the game is the HOST and runs the physics.
/// Host → guest: ball position/velocity, host paddle, scores (~20/s).
/// Guest → host: guest paddle (~20/s). The guest predicts the ball between
/// packets (dead reckoning) so motion stays smooth on mobile networks.
/// Each player sees their own paddle at the bottom (the guest's view is rotated 180°).
class LovePong extends ConsumerStatefulWidget {
  const LovePong({super.key, required this.session, required this.players});
  final GameSession session;
  final ArcadePlayers players;
  @override
  ConsumerState<LovePong> createState() => _LovePongState();
}

const double kW = 1.0, kH = 1.6;
const double kPaddleW = 0.26, kPaddleH = 0.028, kBall = 0.026;
const double kHostY = kH - 0.09, kGuestY = 0.09;
const int kWinScore = 7;

class _LovePongState extends ConsumerState<LovePong> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _frame = ValueNotifier<int>(0);
  CircleChannel? _ch;
  StreamSubscription<Map<String, dynamic>>? _sub;

  // World state (host coordinates)
  double bx = kW / 2, by = kH / 2, vx = 0, vy = 0;
  double hostX = kW / 2, guestX = kW / 2;
  int hostScore = 0, guestScore = 0;
  String phase = 'lobby'; // lobby | count | play | over | paused
  double countdown = 3;

  // Netcode
  Duration _last = Duration.zero;
  double _sendAcc = 0;
  DateTime _lastHeard = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastPacketAt = DateTime.now();
  bool _reported = false;

  // Input
  final _keys = <LogicalKeyboardKey>{};
  final _focus = FocusNode();

  bool get isHost => widget.players.iStarted;
  double get myX => isHost ? hostX : guestX;
  set myX(double v) {
    final x = v.clamp(kPaddleW / 2, kW - kPaddleW / 2);
    if (isHost) {
      hostX = x;
    } else {
      guestX = x;
    }
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ch = ref.read(circleChannelProvider);
      _ch?.setActivity('playing Love Pong');
      _sub = _ch?.on('arcade').listen(_onPacket);
      _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _sub?.cancel();
    _ch?.setActivity(null);
    _frame.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send(Map<String, dynamic> m) => _ch?.send('arcade', {...m, 'id': widget.session.id});

  void _onPacket(Map<String, dynamic> m) {
    if (m['id'] != widget.session.id) return;
    _lastHeard = DateTime.now();
    if (isHost) {
      if (m['k'] == 'p') guestX = (m['gx'] as num).toDouble();
      if (m['k'] == 'rematch' && phase == 'over') _restart();
      if (phase == 'lobby' || phase == 'paused') {
        phase = 'count';
        countdown = 3;
      }
    } else if (m['k'] == 's') {
      bx = (m['bx'] as num).toDouble();
      by = (m['by'] as num).toDouble();
      vx = (m['vx'] as num).toDouble();
      vy = (m['vy'] as num).toDouble();
      hostX = (m['hx'] as num).toDouble();
      hostScore = (m['sh'] as num).toInt();
      guestScore = (m['sg'] as num).toInt();
      phase = m['ph'] as String;
      countdown = (m['n'] as num?)?.toDouble() ?? 0;
      _lastPacketAt = DateTime.now();
    }
  }

  void _restart() {
    hostScore = 0;
    guestScore = 0;
    _reported = false;
    bx = kW / 2;
    by = kH / 2;
    vx = vy = 0;
    phase = 'count';
    countdown = 3;
  }

  void _serve({required bool towardHost}) {
    bx = kW / 2;
    by = kH / 2;
    final angle = (Random().nextDouble() - 0.5) * 0.9;
    const speed = 0.85;
    vx = sin(angle) * speed;
    vy = cos(angle) * speed * (towardHost ? 1 : -1);
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;

    // Keyboard control (desktop): arrows / A-D
    const speed = 1.6;
    final left = _keys.contains(LogicalKeyboardKey.arrowLeft) || _keys.contains(LogicalKeyboardKey.keyA);
    final right = _keys.contains(LogicalKeyboardKey.arrowRight) || _keys.contains(LogicalKeyboardKey.keyD);
    // Guest's screen is rotated, so their "left" is the host's right.
    final dir = (right ? 1 : 0) - (left ? 1 : 0);
    if (dir != 0) myX = myX + dir * speed * dt * (isHost ? 1 : -1);

    if (isHost) {
      _hostStep(dt);
    } else {
      _guestPredict(dt);
    }

    _sendAcc += dt;
    if (_sendAcc >= 0.05) {
      _sendAcc = 0;
      if (isHost) {
        _send({'k': 's', 'bx': bx, 'by': by, 'vx': vx, 'vy': vy, 'hx': hostX, 'sh': hostScore, 'sg': guestScore, 'ph': phase, 'n': countdown});
      } else {
        _send({'k': 'p', 'gx': guestX});
      }
    }
    _frame.value++;
  }

  void _hostStep(double dt) {
    final quiet = DateTime.now().difference(_lastHeard) > const Duration(seconds: 4);
    if (phase == 'play' && quiet) phase = 'paused';
    if (phase == 'lobby' || phase == 'paused' || phase == 'over') return;

    if (phase == 'count') {
      countdown -= dt;
      if (countdown <= 0) {
        phase = 'play';
        _serve(towardHost: _pendingTowardHost ?? Random().nextBool());
        _pendingTowardHost = null;
      }
      return;
    }

    bx += vx * dt;
    by += vy * dt;
    // Side walls
    if (bx < kBall) {
      bx = kBall;
      vx = vx.abs();
    } else if (bx > kW - kBall) {
      bx = kW - kBall;
      vx = -vx.abs();
    }
    // Paddles
    bool hits(double px, double py) => (bx - px).abs() <= kPaddleW / 2 + kBall && (by - py).abs() <= kPaddleH / 2 + kBall;
    if (vy > 0 && hits(hostX, kHostY)) {
      _bounce(hostX, up: true);
    } else if (vy < 0 && hits(guestX, kGuestY)) {
      _bounce(guestX, up: false);
    }
    // Scoring
    if (by > kH + 0.06) {
      guestScore++;
      _afterPoint(towardHost: true);
    } else if (by < -0.06) {
      hostScore++;
      _afterPoint(towardHost: false);
    }
  }

  void _bounce(double px, {required bool up}) {
    HapticFeedback.selectionClick();
    final offset = ((bx - px) / (kPaddleW / 2)).clamp(-1.0, 1.0); // -1..1 across the paddle
    final speed = min(sqrt(vx * vx + vy * vy) * 1.06, 2.2);
    final angle = offset * 1.0; // up to ~57° off vertical
    vx = sin(angle) * speed;
    vy = cos(angle) * speed * (up ? -1 : 1);
    by = up ? kHostY - kPaddleH / 2 - kBall : kGuestY + kPaddleH / 2 + kBall;
  }

  void _afterPoint({required bool towardHost}) {
    if (hostScore >= kWinScore || guestScore >= kWinScore) {
      phase = 'over';
      vx = vy = 0;
      _reportResult();
      return;
    }
    bx = kW / 2;
    by = kH / 2;
    vx = vy = 0;
    phase = 'count';
    countdown = 1.2;
    _pendingTowardHost = towardHost;
  }

  bool? _pendingTowardHost;

  void _guestPredict(double dt) {
    if (phase != 'play') return;
    final since = DateTime.now().difference(_lastPacketAt).inMilliseconds / 1000;
    if (since > 0.4) return; // stale: freeze rather than drift
    bx += vx * dt;
    by += vy * dt;
    if (bx < kBall || bx > kW - kBall) vx = -vx;
  }

  Future<void> _reportResult() async {
    if (_reported) return;
    _reported = true;
    final p = widget.players;
    final hostWon = hostScore > guestScore;
    final winner = hostWon ? p.starter : p.other(p.starter);
    final wins = Map<String, dynamic>.from((widget.session.state['wins'] as Map?) ?? const {});
    wins[winner] = ((wins[winner] as num?) ?? 0) + 1;
    try {
      await ArcadeRepo.setState(widget.session.id, {
        ...widget.session.state,
        'phase': 'over',
        'last': {'host': hostScore, 'guest': guestScore, 'winner': winner},
        'wins': wins,
      });
    } catch (_) {}
  }

  // Pointer → paddle (screen x in 0..1 of the court)
  void _pointer(Offset local, Size court) {
    final sx = (local.dx / court.width).clamp(0.0, 1.0);
    myX = isHost ? sx : 1 - sx;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.players;
    final myScore = isHost ? hostScore : guestScore;
    final theirScore = isHost ? guestScore : hostScore;
    final wins = Map<String, dynamic>.from((widget.session.state['wins'] as Map?) ?? const {});
    return KeyboardListener(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (e) {
        if (e is KeyDownEvent) _keys.add(e.logicalKey);
        if (e is KeyUpEvent) _keys.remove(e.logicalKey);
      },
      child: LayoutBuilder(builder: (context, c) {
        final maxH = c.maxHeight - 70;
        var cw = c.maxWidth - 24;
        var ch = cw * kH;
        if (ch > maxH) {
          ch = maxH;
          cw = ch / kH;
        }
        final court = Size(cw, ch);
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(children: [
              Text('${p.partnerName}  ', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
              Text('$theirScore', style: const TextStyle(color: Color(0xFFB39DDB), fontSize: 26, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text('Wins ${(wins[p.me] as num?) ?? 0}–${(wins[p.partner] as num?) ?? 0}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const Spacer(),
              Text('$myScore', style: const TextStyle(color: Color(0xFFF48FB1), fontSize: 26, fontWeight: FontWeight.w800)),
              const Text('  You', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
            ]),
          ),
          Expanded(
            child: Center(
              child: Semantics(
                label: 'Love Pong court. Drag left and right to move your paddle. Score: you $myScore, ${p.partnerName} $theirScore.',
                child: Listener(
                  onPointerDown: (e) => _pointer(e.localPosition, court),
                  onPointerMove: (e) => _pointer(e.localPosition, court),
                  child: SizedBox(
                    width: cw,
                    height: ch,
                    child: Stack(children: [
                      CustomPaint(size: court, painter: _CourtPainter(this, repaint: _frame)),
                      ValueListenableBuilder(
                        valueListenable: _frame,
                        builder: (context, _, __) => _Overlay(state: this, court: court),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ]);
      }),
    );
  }
}

class _Overlay extends StatelessWidget {
  const _Overlay({required this.state, required this.court});
  final _LovePongState state;
  final Size court;
  @override
  Widget build(BuildContext context) {
    final s = state;
    final p = s.widget.players;
    String? title;
    String? sub;
    Widget? action;
    switch (s.phase) {
      case 'lobby':
        title = s.isHost ? 'Waiting for ${p.partnerName}…' : 'Connecting…';
        sub = s.isHost ? 'The match starts as soon as they open the game.' : 'Joining ${p.partnerName}\'s court';
      case 'paused':
        title = '${p.partnerName}\'s connection dropped';
        sub = 'We\'ll pick up where you left off.';
      case 'count':
        title = s.countdown > 0 ? '${s.countdown.ceil()}' : 'Go!';
      case 'over':
        final myScore = s.isHost ? s.hostScore : s.guestScore;
        final their = s.isHost ? s.guestScore : s.hostScore;
        title = myScore > their ? 'You win! 🏆' : '${p.partnerName} wins! 💜';
        sub = '$myScore – $their';
        action = FilledButton.icon(
          onPressed: () {
            if (s.isHost) {
              s._restart();
            } else {
              s._send({'k': 'rematch'});
              showToast(context, 'Rematch requested ❤️');
            }
          },
          icon: const Icon(Icons.replay_rounded),
          label: const Text('Rematch'),
        );
    }
    if (title == null) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: action == null,
        child: Container(
          color: s.phase == 'count' ? Colors.transparent : const Color(0x99140810),
          alignment: Alignment.center,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: TextStyle(color: Colors.white, fontSize: s.phase == 'count' ? 72 : 28, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
            if (sub != null) ...[const SizedBox(height: 6), Text(sub, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center)],
            if (action != null) ...[const SizedBox(height: 16), action],
          ]),
        ),
      ),
    );
  }
}

class _CourtPainter extends CustomPainter {
  _CourtPainter(this.s, {required Listenable repaint}) : super(repaint: repaint);
  final _LovePongState s;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / kW;
    // Guest sees the court rotated 180° so their paddle is at the bottom.
    Offset pt(double x, double y) => s.isHost ? Offset(x * k, y * k) : Offset((kW - x) * k, (kH - y) * k);

    final rect = Offset.zero & size;
    final bg = Paint()
      ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2A0F22), Color(0xFF14070F)])
          .createShader(rect);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(20)), bg);
    final border = Paint()
      ..color = const Color(0x55F06292)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(RRect.fromRectAndRadius(rect.deflate(1), const Radius.circular(20)), border);

    // Centre line of little hearts
    final dash = Paint()..color = const Color(0x33F48FB1);
    for (var x = 0.05; x < kW; x += 0.08) {
      canvas.drawCircle(Offset(x * k, size.height / 2), 2.2, dash);
    }

    void paddle(double x, double y, Color c) {
      final center = pt(x, y);
      final r = RRect.fromRectAndRadius(Rect.fromCenter(center: center, width: kPaddleW * k, height: kPaddleH * k), Radius.circular(kPaddleH * k));
      canvas.drawRRect(r, Paint()
        ..color = c.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
      canvas.drawRRect(r, Paint()..color = c);
    }

    paddle(s.hostX, kHostY, s.isHost ? const Color(0xFFF48FB1) : const Color(0xFFB39DDB));
    paddle(s.guestX, kGuestY, s.isHost ? const Color(0xFFB39DDB) : const Color(0xFFF48FB1));

    // Ball: a glowing heart
    final c = pt(s.bx, s.by);
    final r = kBall * k * 1.3;
    canvas.drawCircle(c, r * 1.8, Paint()
      ..color = const Color(0x66FF4F8B)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));
    final heart = Path()
      ..moveTo(c.dx, c.dy + r * 0.9)
      ..cubicTo(c.dx - r * 1.6, c.dy - r * 0.2, c.dx - r * 0.7, c.dy - r * 1.4, c.dx, c.dy - r * 0.5)
      ..cubicTo(c.dx + r * 0.7, c.dy - r * 1.4, c.dx + r * 1.6, c.dy - r * 0.2, c.dx, c.dy + r * 0.9)
      ..close();
    canvas.drawPath(heart, Paint()..color = const Color(0xFFFF4F8B));
  }

  @override
  bool shouldRepaint(_CourtPainter old) => false;
}
