import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../../core/utils/format.dart';
import '../../data/media_repo.dart';

class RecordedVoice {
  RecordedVoice(this.bytes, this.duration, this.mime, this.filename);
  final Uint8List bytes;
  final Duration duration;
  final String mime;
  final String filename;
}

/// Tap-to-record voice notes (works on mobile and web).
class VoiceRecorderController {
  final _rec = AudioRecorder();
  DateTime? _startedAt;
  bool get isRecording => _startedAt != null;
  Duration get elapsed => _startedAt == null ? Duration.zero : DateTime.now().difference(_startedAt!);

  Future<bool> start() async {
    if (!await _rec.hasPermission()) return false;
    final encoder = kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc;
    var path = '';
    if (!kIsWeb) {
      final dir = await getTemporaryDirectory();
      path = '${dir.path}/vn_${const Uuid().v4()}.m4a';
    }
    await _rec.start(RecordConfig(encoder: encoder, bitRate: 64000, sampleRate: 44100, numChannels: 1), path: path);
    _startedAt = DateTime.now();
    return true;
  }

  Future<RecordedVoice?> stop() async {
    final duration = elapsed;
    _startedAt = null;
    final out = await _rec.stop();
    if (out == null || duration.inMilliseconds < 700) return null; // accidental taps
    final bytes = await XFile(out).readAsBytes();
    return kIsWeb
        ? RecordedVoice(bytes, duration, 'audio/webm', 'voice.webm')
        : RecordedVoice(bytes, duration, 'audio/m4a', 'voice.m4a');
  }

  Future<void> cancel() async {
    _startedAt = null;
    await _rec.cancel();
  }

  Future<void> dispose() => _rec.dispose();
}

/// Playback bubble content for a voice note in private storage.
class VoiceNotePlayer extends StatefulWidget {
  const VoiceNotePlayer({super.key, required this.path, required this.durationMs, required this.color});
  final String path;
  final int durationMs;
  final Color color;
  @override
  State<VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<VoiceNotePlayer> {
  AudioPlayer? _player;
  bool _loading = false;
  Duration _pos = Duration.zero;
  bool _playing = false;
  final _subs = <StreamSubscription<dynamic>>[];

  Future<void> _toggle() async {
    if (_player == null) {
      setState(() => _loading = true);
      try {
        final url = await MediaRepo.instance.signedUrl(widget.path);
        final p = AudioPlayer();
        await p.setUrl(url);
        _subs
          ..add(p.positionStream.listen((d) => mounted ? setState(() => _pos = d) : null))
          ..add(p.playerStateStream.listen((s) {
            if (!mounted) return;
            if (s.processingState == ProcessingState.completed) {
              p.pause();
              p.seek(Duration.zero);
            }
            setState(() => _playing = s.playing && s.processingState != ProcessingState.completed);
          }));
        _player = p;
      } catch (_) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      if (mounted) setState(() => _loading = false);
    }
    _player!.playing ? await _player!.pause() : await _player!.play();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = Duration(milliseconds: widget.durationMs);
    final progress = total.inMilliseconds == 0 ? 0.0 : (_pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
        tooltip: _playing ? 'Pause voice note' : 'Play voice note',
        onPressed: _loading ? null : _toggle,
        icon: _loading
            ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: widget.color))
            : Icon(_playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: widget.color, size: 34),
      ),
      SizedBox(
        width: 120,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: progress, minHeight: 4, color: widget.color, backgroundColor: widget.color.withValues(alpha: 0.25)),
        ),
      ),
      const SizedBox(width: 8),
      Text(Fmt.duration(_playing || _pos > Duration.zero ? _pos : total), style: TextStyle(color: widget.color, fontSize: 12)),
      const SizedBox(width: 6),
    ]);
  }
}
