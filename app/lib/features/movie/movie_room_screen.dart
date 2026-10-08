import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../core/errors.dart';
import '../../core/supabase.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../../state/circle_channel.dart';
import '../../state/session.dart';
import '../calls/call_sheet.dart';
import '../chat/chat_screen.dart';
import '../diary/diary_repo.dart';
import '../diary/moment_suggester.dart';
import 'movie_catalog.dart';

/// Synced Movie Night.
///
/// Protocol (Broadcast on the private circle channel, event "movie"):
///   {type:"state", session, playing, pos}  — sent on every local play/pause/seek and as a 5s heartbeat
///   {type:"hello", session}                — "I just joined, tell me where you are"
///   {type:"wait",  session}                — "I'm buffering, hold on"
/// The receiver seeks only if drift > 1.5s. We deliberately ignore sender wall-clock time
/// (phones' clocks disagree) and add a small fixed latency allowance instead.
/// Durable state is also written to movie_sessions so either partner can resume later.
class MovieRoomScreen extends ConsumerStatefulWidget {
  const MovieRoomScreen({super.key, required this.sessionId});
  final String sessionId;
  @override
  ConsumerState<MovieRoomScreen> createState() => _MovieRoomScreenState();
}

class _MovieRoomScreenState extends ConsumerState<MovieRoomScreen> {
  static const _latency = Duration(milliseconds: 150);
  static const _driftTolerance = Duration(milliseconds: 1500);

  MovieSession? _session;
  VideoPlayerController? _player;
  Object? _error;
  CircleChannel? _channel;
  StreamSubscription<Map<String, dynamic>>? _sub;
  StreamSubscription<Map<String, dynamic>>? _reactSub;
  Timer? _heartbeat;
  Timer? _persistDebounce;
  DateTime _suppressUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool _iAmLeader = false;
  bool _partnerWaiting = false;
  DateTime? _bufferingSince;
  bool _sentWait = false;
  bool _showChat = true;
  bool _ended = false;
  double? _scrub;
  final _call = CallController();
  final _floating = <(int, String)>[];
  int _floatId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final row = await sb.from('movie_sessions').select().eq('id', widget.sessionId).single();
      final s = MovieSession.fromJson(row);
      final c = VideoPlayerController.networkUrl(Uri.parse(s.sourceUrl));
      await c.initialize();
      // Resume from durable state.
      var pos = Duration(milliseconds: s.positionMs);
      if (s.playbackState == 'playing') pos += DateTime.now().toUtc().difference(s.stateUpdatedAt.toUtc());
      if (pos < c.value.duration) await c.seekTo(pos);
      c.addListener(_onTick);
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _session = s;
        _player = c;
      });
      _channel = ref.read(circleChannelProvider);
      _channel?.setActivity('watching');
      _sub = _channel?.on('movie').listen(_onRemote);
      _reactSub = _channel?.on('reaction').listen((e) {
        if (e['session'] == widget.sessionId) _float(e['emoji'] as String? ?? '❤️');
      });
      _channel?.send('movie', {'type': 'hello', 'session': widget.sessionId});
      _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) {
        if (_iAmLeader && (_player?.value.isPlaying ?? false)) _broadcastState();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _reactSub?.cancel();
    _heartbeat?.cancel();
    _persistDebounce?.cancel();
    _player?.removeListener(_onTick);
    _player?.dispose();
    _call.dispose();
    _channel?.setActivity(null);
    super.dispose();
  }

  bool get _suppressed => DateTime.now().isBefore(_suppressUntil);

  void _onTick() {
    final c = _player;
    if (c == null || !mounted) return;
    final v = c.value;
    // Buffering → ask partner to wait (once), resume both when ready.
    if (v.isPlaying && v.isBuffering) {
      _bufferingSince ??= DateTime.now();
      if (!_sentWait && DateTime.now().difference(_bufferingSince!) > const Duration(milliseconds: 2500)) {
        _sentWait = true;
        _channel?.send('movie', {'type': 'wait', 'session': widget.sessionId});
      }
    } else {
      _bufferingSince = null;
      if (_sentWait && !v.isBuffering) {
        _sentWait = false;
        _broadcastState();
      }
    }
    if (!_ended && v.duration > Duration.zero && v.position >= v.duration - const Duration(milliseconds: 400)) {
      _ended = true;
      _onEnded();
    }
    setState(() {});
  }

  void _onRemote(Map<String, dynamic> e) async {
    if (e['session'] != widget.sessionId) return;
    final c = _player;
    if (c == null) return;
    switch (e['type']) {
      case 'hello':
        _broadcastState();
      case 'wait':
        _suppressUntil = DateTime.now().add(const Duration(milliseconds: 600));
        await c.pause();
        setState(() => _partnerWaiting = true);
      case 'state':
        _iAmLeader = false;
        final playing = e['playing'] == true;
        var target = Duration(milliseconds: (e['pos'] as num).toInt());
        if (playing) target += _latency;
        _suppressUntil = DateTime.now().add(const Duration(milliseconds: 600));
        if ((c.value.position - target).abs() > _driftTolerance) await c.seekTo(target);
        if (playing && !c.value.isPlaying) await c.play();
        if (!playing && c.value.isPlaying) await c.pause();
        if (mounted) setState(() => _partnerWaiting = false);
    }
  }

  void _broadcastState() {
    final c = _player;
    if (c == null) return;
    _channel?.send('movie', {
      'type': 'state',
      'session': widget.sessionId,
      'playing': c.value.isPlaying,
      'pos': c.value.position.inMilliseconds,
    });
  }

  void _persist() {
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 400), () async {
      final c = _player;
      if (c == null) return;
      try {
        await sb.from('movie_sessions').update({
          'playback_state': c.value.isPlaying ? 'playing' : 'paused',
          'position_ms': c.value.position.inMilliseconds,
          'state_updated_at': DateTime.now().toUtc().toIso8601String(),
          'updated_by': requireUserId(),
        }).eq('id', widget.sessionId);
      } catch (_) {}
    });
  }

  /// Every local control goes through here: apply, broadcast, persist.
  Future<void> _control(Future<void> Function(VideoPlayerController c) action) async {
    final c = _player;
    if (c == null || _suppressed) return;
    await action(c);
    _iAmLeader = true;
    setState(() => _partnerWaiting = false);
    _broadcastState();
    _persist();
  }

  void _float(String emoji) {
    final id = _floatId++;
    setState(() => _floating.add((id, emoji)));
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _floating.removeWhere((f) => f.$1 == id));
    });
  }

  Future<void> _onEnded() async {
    final s = _session;
    if (s == null) return;
    try {
      await sb.from('movie_sessions').update({'playback_state': 'ended', 'ended_at': DateTime.now().toUtc().toIso8601String()}).eq('id', s.id);
      await sb.from('together_sessions').update({'status': 'ended', 'ended_at': DateTime.now().toUtc().toIso8601String()}).eq('ref_id', s.id);
    } catch (_) {}
    if (!mounted) return;
    MomentSuggester.maybeSuggest(
      context,
      s.circleId,
      MomentSuggestion(
        kind: 'movie_night',
        headline: '🎬 Movie night with you is the best.',
        prompt: 'Save "${s.title}" to Our Diary?',
        entryType: 'movie',
        title: 'We watched ${s.title}',
        payload: {'movie_session_id': s.id, 'title': s.title},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final partner = ref.watch(partnerProvider).valueOrNull;
    final partnerName = partner?.displayName ?? 'your partner';
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final s = _session;
    final c = _player;

    if (_error != null) {
      return Scaffold(appBar: AppBar(), body: ErrorView(error: _error!, onRetry: () {
        setState(() => _error = null);
        _load();
      }));
    }
    if (s == null || c == null) return const Scaffold(body: LoadingView(label: 'Setting up the screen…'));

    final film = movieCatalog.where((f) => f.id == s.catalogId).firstOrNull;
    final v = c.value;
    final position = _scrub != null ? Duration(milliseconds: _scrub!.round()) : v.position;

    final player = Column(mainAxisSize: MainAxisSize.min, children: [
      Stack(alignment: Alignment.center, children: [
        AspectRatio(aspectRatio: v.aspectRatio == 0 ? 16 / 9 : v.aspectRatio, child: ColoredBox(color: Colors.black, child: VideoPlayer(c))),
        if (v.isBuffering) const CircularProgressIndicator(color: Colors.white),
        if (_partnerWaiting)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(99)),
            child: Text('Waiting for $partnerName\'s connection…', style: const TextStyle(color: Colors.white)),
          ),
        for (final f in _floating)
          Positioned(
            key: ValueKey(f.$1),
            bottom: 12,
            right: 24.0 + (f.$1 % 5) * 18,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 1700),
              builder: (_, t, child) => Transform.translate(offset: Offset(0, -140 * t), child: Opacity(opacity: 1 - t, child: child)),
              child: Text(f.$2, style: const TextStyle(fontSize: 34)),
            ),
          ),
        Positioned(top: 8, right: 8, child: CallVideoTiles(controller: _call)),
      ]),
      Material(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Column(children: [
            Slider(
              value: position.inMilliseconds.clamp(0, v.duration.inMilliseconds).toDouble(),
              max: v.duration.inMilliseconds < 1 ? 1.0 : v.duration.inMilliseconds.toDouble(),
              semanticFormatterCallback: (x) => Fmt.duration(Duration(milliseconds: x.round())),
              onChanged: (x) => setState(() => _scrub = x),
              onChangeEnd: (x) async {
                setState(() => _scrub = null);
                await _control((c) => c.seekTo(Duration(milliseconds: x.round())));
              },
            ),
            Row(children: [
              Text('${Fmt.duration(position)} / ${Fmt.duration(v.duration)}', style: Theme.of(context).textTheme.labelMedium),
              const Spacer(),
              IconButton(tooltip: 'Back 10 seconds', onPressed: () => _control((c) => c.seekTo(c.value.position - const Duration(seconds: 10))), icon: const Icon(Icons.replay_10_rounded)),
              IconButton.filled(
                tooltip: v.isPlaying ? 'Pause for both' : 'Play for both',
                iconSize: 32,
                onPressed: () => _control((c) => v.isPlaying ? c.pause() : c.play()),
                icon: Icon(v.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
              ),
              IconButton(tooltip: 'Forward 10 seconds', onPressed: () => _control((c) => c.seekTo(c.value.position + const Duration(seconds: 10))), icon: const Icon(Icons.forward_10_rounded)),
              const Spacer(),
              if (!wide)
                IconButton(
                  tooltip: _showChat ? 'Hide chat' : 'Show chat',
                  onPressed: () => setState(() => _showChat = !_showChat),
                  icon: Icon(_showChat ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline_rounded),
                ),
            ]),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (final e in const ['😂', '😍', '😱', '😭', '🔥', '❤️'])
                IconButton(
                  tooltip: 'React $e',
                  onPressed: () {
                    _float(e);
                    _channel?.send('reaction', {'session': widget.sessionId, 'emoji': e});
                  },
                  icon: Text(e, style: const TextStyle(fontSize: 22)),
                ),
            ]),
            if (film != null) Text(film.attribution, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ),
    ]);

    final chat = const ChatScreen(embedded: true);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.title, overflow: TextOverflow.ellipsis),
        actions: [
          CallBar(controller: _call, partnerName: partnerName, compact: !wide),
          IconButton(
            tooltip: 'Save to Our Diary',
            icon: const Icon(Icons.auto_stories_outlined),
            onPressed: () => guard(context, () async {
              await DiaryRepo.create(circleId: s.circleId, entryType: 'movie', origin: 'together', title: 'We watched ${s.title}', payload: {'movie_session_id': s.id});
              if (mounted) showToast(context, 'Saved to Our Diary ❤️');
            }),
          ),
        ],
      ),
      body: SafeArea(
        child: wide
            ? Row(children: [
                Expanded(child: SingleChildScrollView(child: player)),
                const VerticalDivider(width: 1),
                SizedBox(width: 380, child: chat),
              ])
            : Column(children: [
                player,
                if (_showChat) const Divider(height: 1),
                if (_showChat) Expanded(child: chat) else const Spacer(),
              ]),
      ),
    );
  }
}
