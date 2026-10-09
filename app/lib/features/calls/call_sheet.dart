import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/widgets.dart';
import '../../state/session.dart';
import 'call_manager.dart';

/// Voice / video call buttons for app bars (Chat, Movie Night, games).
class CallBar extends ConsumerWidget {
  const CallBar({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(callManagerProvider);
    final partner = ref.watch(partnerProvider).valueOrNull;
    if (m == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: m,
      builder: (context, _) {
        if (m.inCall) {
          return IconButton(
            tooltip: 'Show call',
            onPressed: () => m.setMinimized(false),
            icon: const Icon(Icons.phone_in_talk_rounded, color: LBColors.mint),
          );
        }
        return Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            tooltip: 'Voice call ${partner?.displayName ?? ''}',
            onPressed: () => m.start(video: false),
            icon: const Icon(Icons.call_outlined),
          ),
          if (!compact)
            IconButton(
              tooltip: 'Video call ${partner?.displayName ?? ''}',
              onPressed: () => m.start(video: true),
              icon: const Icon(Icons.videocam_outlined),
            ),
        ]);
      },
    );
  }
}

/// Global call UI, layered above every screen (ringing, in-call, minimized pill).
/// Lives in MaterialApp.builder, so it avoids widgets that need a Navigator/Overlay (e.g. tooltips).
class CallOverlay extends ConsumerStatefulWidget {
  const CallOverlay({super.key});
  @override
  ConsumerState<CallOverlay> createState() => _CallOverlayState();
}

class _CallOverlayState extends ConsumerState<CallOverlay> {
  Timer? _clock;
  Timer? _noticeTimer;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      final m = ref.read(callManagerProvider);
      if (mounted && m?.phase == CallPhase.connected) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _noticeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = ref.watch(callManagerProvider);
    if (m == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: m,
      builder: (context, _) {
        if (!m.inCall) {
          if (m.notice == null) return const SizedBox.shrink();
          _noticeTimer?.cancel();
          _noticeTimer = Timer(const Duration(seconds: 3), m.clearNotice);
          return _NoticeToast(text: m.notice!);
        }
        if (m.minimized) return _MiniPill(m: m);
        return _FullCall(m: m);
      },
    );
  }
}

class _FullCall extends ConsumerWidget {
  const _FullCall({required this.m});
  final CallManager m;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partner = ref.watch(partnerProvider).valueOrNull;
    final name = partner?.displayName ?? 'Your partner';
    final t = Theme.of(context).textTheme;
    final status = switch (m.phase) {
      CallPhase.outgoing => 'Calling…',
      CallPhase.incoming => m.video ? 'Incoming video call' : 'Incoming voice call',
      CallPhase.connecting => 'Connecting…',
      CallPhase.connected => m.connectedAt == null ? '' : Fmt.duration(DateTime.now().difference(m.connectedAt!)),
      _ => '',
    };
    final showRemoteVideo = m.video && m.phase == CallPhase.connected;

    return Positioned.fill(
      child: Material(
        color: const Color(0xFF14070F),
        child: Stack(children: [
          // Remote media is ALWAYS mounted: on the web it is also what plays the partner's audio.
          Positioned.fill(
            child: Opacity(
              opacity: showRemoteVideo ? 1 : 0,
              child: RTCVideoView(m.remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
            ),
          ),
          if (!showRemoteVideo)
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF8E0E43), Color(0xFF14070F)]),
                ),
              ),
            ),
          SafeArea(
            child: Column(children: [
              Align(
                alignment: Alignment.topLeft,
                child: m.phase == CallPhase.incoming
                    ? const SizedBox(height: 48)
                    : _RoundButton(icon: Icons.close_fullscreen_rounded, label: 'Minimise', onTap: () => m.setMinimized(true), small: true),
              ),
              const SizedBox(height: 12),
              if (!showRemoteVideo) ...[
                const SizedBox(height: 32),
                _Pulse(active: m.phase != CallPhase.connected, child: LBAvatar(profile: partner, size: 120, ring: true)),
                const SizedBox(height: 20),
              ],
              Text(name, style: t.headlineMedium?.copyWith(color: Colors.white, shadows: const [Shadow(blurRadius: 8)])),
              const SizedBox(height: 6),
              Semantics(liveRegion: true, child: Text(status, style: t.bodyLarge?.copyWith(color: Colors.white70, shadows: const [Shadow(blurRadius: 8)]))),
              const Spacer(),
              if (m.phase == CallPhase.incoming)
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  _RoundButton(icon: Icons.call_end_rounded, label: 'Decline', color: LBColors.danger, onTap: m.decline),
                  _RoundButton(icon: m.video ? Icons.videocam_rounded : Icons.call_rounded, label: 'Accept', color: LBColors.success, onTap: m.accept),
                ])
              else
                Wrap(alignment: WrapAlignment.center, spacing: 18, runSpacing: 18, children: [
                  _RoundButton(icon: m.micOn ? Icons.mic_rounded : Icons.mic_off_rounded, label: m.micOn ? 'Mute' : 'Unmute', onTap: m.toggleMic, active: !m.micOn),
                  if (m.video) _RoundButton(icon: m.camOn ? Icons.videocam_rounded : Icons.videocam_off_rounded, label: m.camOn ? 'Camera off' : 'Camera on', onTap: m.toggleCam, active: !m.camOn),
                  if (m.video) _RoundButton(icon: Icons.cameraswitch_rounded, label: 'Flip', onTap: m.switchCamera),
                  if (!m.video) _RoundButton(icon: m.speakerOn ? Icons.volume_up_rounded : Icons.hearing_rounded, label: 'Speaker', onTap: m.toggleSpeaker, active: m.speakerOn),
                  _RoundButton(icon: Icons.call_end_rounded, label: 'End', color: LBColors.danger, onTap: m.hangUp),
                ]),
              const SizedBox(height: 36),
            ]),
          ),
          // Your own camera, picture-in-picture
          if (m.video && m.phase != CallPhase.incoming)
            Positioned(
              right: 16,
              top: MediaQuery.paddingOf(context).top + 60,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 110,
                  height: 160,
                  color: Colors.black,
                  child: m.camOn ? RTCVideoView(m.localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover) : const Center(child: Icon(Icons.videocam_off, color: Colors.white54)),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _MiniPill extends ConsumerWidget {
  const _MiniPill({required this.m});
  final CallManager m;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partner = ref.watch(partnerProvider).valueOrNull;
    final time = m.connectedAt == null ? 'Connecting…' : Fmt.duration(DateTime.now().difference(m.connectedAt!));
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 8,
      right: 12,
      child: Material(
        color: const Color(0xFF14070F),
        elevation: 8,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            // Keep remote media mounted (plays audio on the web) as a tiny live thumbnail.
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: m.video ? 56 : 1,
                height: m.video ? 72 : 1,
                child: RTCVideoView(m.remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
              ),
            ),
            if (!m.video) LBAvatar(profile: partner, size: 34),
            const SizedBox(width: 8),
            Text(time, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            const SizedBox(width: 4),
            _RoundButton(icon: Icons.open_in_full_rounded, label: 'Expand', onTap: () => m.setMinimized(false), small: true),
            _RoundButton(icon: Icons.call_end_rounded, label: 'End', color: LBColors.danger, onTap: m.hangUp, small: true),
          ]),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.label, required this.onTap, this.color, this.active = false, this.small = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool active;
  final bool small;
  @override
  Widget build(BuildContext context) {
    final size = small ? 40.0 : 64.0;
    final bg = color ?? (active ? Colors.white : Colors.white.withValues(alpha: 0.16));
    final fg = color != null ? Colors.white : (active ? const Color(0xFF14070F) : Colors.white);
    final button = Semantics(
      button: true,
      label: label,
      child: Material(
        color: bg,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: size, height: size, child: Icon(icon, color: fg, size: small ? 20 : 28)),
        ),
      ),
    );
    if (small) return Padding(padding: const EdgeInsets.all(4), child: button);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      button,
      const SizedBox(height: 6),
      ExcludeSemantics(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12))),
    ]);
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse({required this.child, required this.active});
  final Widget child;
  final bool active;
  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active || MediaQuery.of(context).disableAnimations) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Stack(alignment: Alignment.center, children: [
        Container(
          width: 120 + 60 * _c.value,
          height: 120 + 60 * _c.value,
          decoration: BoxDecoration(shape: BoxShape.circle, color: LBColors.blossom.withValues(alpha: 0.35 * (1 - _c.value))),
        ),
        child!,
      ]),
      child: widget.child,
    );
  }
}

class _NoticeToast extends StatelessWidget {
  const _NoticeToast({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Positioned(
        left: 0,
        right: 0,
        top: MediaQuery.paddingOf(context).top + 12,
        child: Center(
          child: Material(
            color: const Color(0xFF14070F),
            borderRadius: BorderRadius.circular(99),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Semantics(liveRegion: true, child: Text('📞 $text', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
            ),
          ),
        ),
      );
}
