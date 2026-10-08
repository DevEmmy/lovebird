import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../../core/errors.dart';
import '../../core/supabase.dart';
import '../../core/theme/colors.dart';

/// Voice (and optional video) for the couple, via LiveKit.
/// The `call-token` edge function only issues tokens to live members of the circle,
/// for the room "circle-{id}" — nobody else can join.
class CallController extends ChangeNotifier {
  lk.Room? _room;
  bool connecting = false;
  bool micOn = true;
  bool camOn = false;
  String? error;

  bool get connected => _room?.connectionState == lk.ConnectionState.connected;
  lk.Room? get room => _room;

  lk.RemoteParticipant? get partner {
    final r = _room;
    if (r == null || r.remoteParticipants.isEmpty) return null;
    return r.remoteParticipants.values.first;
  }

  lk.VideoTrack? get partnerVideo {
    final p = partner;
    if (p == null) return null;
    for (final pub in p.videoTrackPublications) {
      final t = pub.track;
      if (t != null && !pub.muted) return t;
    }
    return null;
  }

  lk.VideoTrack? get myVideo {
    final lp = _room?.localParticipant;
    if (lp == null) return null;
    for (final pub in lp.videoTrackPublications) {
      final t = pub.track;
      if (t != null) return t;
    }
    return null;
  }

  Future<void> join({bool video = false}) async {
    if (connecting || connected) return;
    connecting = true;
    error = null;
    notifyListeners();
    try {
      final res = await sb.functions.invoke('call-token', body: {'video': video});
      final data = Map<String, dynamic>.from(res.data as Map);
      final room = lk.Room(roomOptions: const lk.RoomOptions(adaptiveStream: true, dynacast: true));
      room.addListener(notifyListeners);
      await room.connect(data['url'] as String, data['token'] as String);
      await room.localParticipant?.setMicrophoneEnabled(true);
      if (video) await room.localParticipant?.setCameraEnabled(true);
      _room = room;
      micOn = true;
      camOn = video;
    } catch (e) {
      error = friendlyError(e);
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  Future<void> toggleMic() async {
    micOn = !micOn;
    await _room?.localParticipant?.setMicrophoneEnabled(micOn);
    notifyListeners();
  }

  Future<void> toggleCam() async {
    camOn = !camOn;
    await _room?.localParticipant?.setCameraEnabled(camOn);
    notifyListeners();
  }

  Future<void> leave() async {
    final r = _room;
    _room = null;
    if (r != null) {
      r.removeListener(notifyListeners);
      await r.disconnect();
      await r.dispose();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    leave();
    super.dispose();
  }
}

/// Compact call bar used in Chat, Movie Night and games.
class CallBar extends StatelessWidget {
  const CallBar({super.key, required this.controller, required this.partnerName, this.compact = false});
  final CallController controller;
  final String partnerName;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        if (!c.connected) {
          return Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              tooltip: 'Voice call $partnerName',
              onPressed: c.connecting ? null : () => c.join(),
              icon: c.connecting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.call_outlined),
            ),
            if (!compact)
              IconButton(tooltip: 'Video call $partnerName', onPressed: c.connecting ? null : () => c.join(video: true), icon: const Icon(Icons.videocam_outlined)),
            if (c.error != null)
              Tooltip(message: c.error!, child: const Icon(Icons.info_outline, size: 18)),
          ]);
        }
        final here = c.partner != null;
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: LBColors.mint.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(99)),
            child: Text(here ? 'On call' : 'Calling…', style: Theme.of(context).textTheme.labelMedium),
          ),
          IconButton(tooltip: c.micOn ? 'Mute' : 'Unmute', onPressed: c.toggleMic, icon: Icon(c.micOn ? Icons.mic : Icons.mic_off)),
          if (!compact)
            IconButton(tooltip: c.camOn ? 'Camera off' : 'Camera on', onPressed: c.toggleCam, icon: Icon(c.camOn ? Icons.videocam : Icons.videocam_off)),
          IconButton(
            tooltip: 'Hang up',
            onPressed: c.leave,
            icon: const Icon(Icons.call_end_rounded, color: LBColors.danger),
          ),
        ]);
      },
    );
  }
}

/// Floating video tiles when someone has a camera on.
class CallVideoTiles extends StatelessWidget {
  const CallVideoTiles({super.key, required this.controller});
  final CallController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final remote = controller.partnerVideo;
          final local = controller.camOn ? controller.myVideo : null;
          if (remote == null && local == null) return const SizedBox.shrink();
          Widget tile(lk.VideoTrack t, {bool mirror = false}) => ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(width: 110, height: 150, child: lk.VideoTrackRenderer(t, mirrorMode: mirror ? lk.VideoViewMirrorMode.mirror : lk.VideoViewMirrorMode.off)),
              );
          return Row(mainAxisSize: MainAxisSize.min, children: [
            if (remote != null) tile(remote),
            if (remote != null && local != null) const SizedBox(width: 8),
            if (local != null) tile(local, mirror: true),
          ]);
        },
      );
}
