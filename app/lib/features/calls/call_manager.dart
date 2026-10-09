import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';

import '../../state/circle_channel.dart';
import '../../state/session.dart';

/// Voice & video calls between the two partners.
///
/// Media flows directly phone-to-phone (WebRTC, encrypted with DTLS-SRTP).
/// Signalling (ring / offer / answer / ICE) travels over the couple's private
/// realtime channel, which only the two members of the circle can join.
/// STUN finds a direct route; optional TURN (dart-define TURN_URL/USERNAME/CREDENTIAL)
/// relays media on strict networks.
enum CallPhase { idle, outgoing, incoming, connecting, connected }

class CallManager extends ChangeNotifier {
  CallManager(this._channel, this.myId) {
    // Signals are handled one at a time, in order (offer before its ICE, etc.).
    _sub = _channel.on('call').listen((m) {
      _queue = _queue.then((_) => _safeSignal(m));
    });
  }

  final CircleChannel _channel;
  final String myId;
  StreamSubscription<Map<String, dynamic>>? _sub;

  CallPhase phase = CallPhase.idle;
  bool video = false;
  bool micOn = true;
  bool camOn = true;
  bool speakerOn = true;
  bool minimized = false;
  String? notice; // "No answer", "Call declined", …
  DateTime? connectedAt;

  String? _callId;
  RTCPeerConnection? _pc;
  MediaStream? _local;
  MediaStream? _remote;
  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();
  bool _renderersReady = false;
  final _pendingIce = <RTCIceCandidate>[];
  bool _remoteSet = false;
  Timer? _ringTimer;
  Timer? _ringTimeout;
  Timer? _dropTimer;

  bool _disposed = false;
  Future<void> _queue = Future.value();

  Future<void> _safeSignal(Map<String, dynamic> m) async {
    try {
      await _onSignal(m);
    } catch (e, st) {
      // ignore: avoid_print
      print('[call] ${m['t']} failed: $e\n$st');
    }
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  bool get inCall => phase != CallPhase.idle;
  bool get remoteHasVideo => (_remote?.getVideoTracks().isNotEmpty ?? false) && video;

  static Map<String, dynamic> get _rtcConfig {
    const turnUrl = String.fromEnvironment('TURN_URL');
    return {
      'iceServers': [
        {'urls': ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302']},
        if (turnUrl.isNotEmpty)
          {
            'urls': turnUrl.split(','),
            'username': const String.fromEnvironment('TURN_USERNAME'),
            'credential': const String.fromEnvironment('TURN_CREDENTIAL'),
          },
      ],
      'sdpSemantics': 'unified-plan',
    };
  }

  Future<void> _ensureRenderers() async {
    if (_renderersReady) return;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _renderersReady = true;
  }

  void _send(String t, [Map<String, dynamic> extra = const {}]) =>
      _channel.send('call', {'t': t, 'cid': _callId, 'video': video, ...extra});

  // ------------------------------------------------------------------ actions

  Future<void> start({required bool video}) async {
    if (inCall) return;
    this.video = video;
    _callId = const Uuid().v4();
    notice = null;
    phase = CallPhase.outgoing;
    minimized = false;
    notifyListeners();
    try {
      await _openMedia();
    } catch (e) {
      _finish(notice: 'Allow microphone${video ? ' and camera' : ''} access to call.');
      return;
    }
    _send('ring');
    _ringTimer = Timer.periodic(const Duration(seconds: 3), (_) => _send('ring'));
    _ringTimeout = Timer(const Duration(seconds: 45), () {
      if (phase == CallPhase.outgoing) {
        _send('end');
        _finish(notice: 'No answer');
      }
    });
  }

  Future<void> accept() async {
    if (phase != CallPhase.incoming) return;
    phase = CallPhase.connecting;
    notifyListeners();
    try {
      await _openMedia();
    } catch (e) {
      _send('decline');
      _finish(notice: 'Allow microphone${video ? ' and camera' : ''} access to answer.');
      return;
    }
    try {
      await _createPeer();
    } catch (e, st) {
      // ignore: avoid_print
      print('[call] accept/createPeer failed: $e\n$st');
      rethrow;
    }
    _send('accept');
  }

  void decline() {
    if (phase != CallPhase.incoming) return;
    _send('decline');
    _finish();
  }

  void hangUp() {
    if (!inCall) return;
    _send('end');
    _finish();
  }

  void toggleMic() {
    micOn = !micOn;
    for (final t in _local?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = micOn;
    }
    notifyListeners();
  }

  void toggleCam() {
    camOn = !camOn;
    for (final t in _local?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = camOn;
    }
    notifyListeners();
  }

  Future<void> switchCamera() async {
    final tracks = _local?.getVideoTracks() ?? const <MediaStreamTrack>[];
    if (tracks.isNotEmpty) await Helper.switchCamera(tracks.first);
  }

  Future<void> toggleSpeaker() async {
    speakerOn = !speakerOn;
    if (!kIsWeb) await Helper.setSpeakerphoneOn(speakerOn);
    notifyListeners();
  }

  void setMinimized(bool v) {
    minimized = v;
    notifyListeners();
  }

  void clearNotice() {
    notice = null;
    notifyListeners();
  }

  // ------------------------------------------------------------------ signalling

  Future<void> _onSignal(Map<String, dynamic> m) async {
    final t = m['t'] as String?;
    final cid = m['cid'] as String?;
    switch (t) {
      case 'ring':
        if (phase == CallPhase.idle) {
          _callId = cid;
          video = m['video'] == true;
          notice = null;
          minimized = false;
          phase = CallPhase.incoming;
          HapticFeedback.heavyImpact();
          notifyListeners();
          // Stop ringing if the caller gives up and we never hear again.
          _ringTimeout?.cancel();
          _ringTimeout = Timer(const Duration(seconds: 10), () {
            if (phase == CallPhase.incoming) _finish(notice: 'Missed call');
          });
        } else if (phase == CallPhase.incoming && cid == _callId) {
          _ringTimeout?.cancel();
          _ringTimeout = Timer(const Duration(seconds: 10), () {
            if (phase == CallPhase.incoming) _finish(notice: 'Missed call');
          });
        } else if (cid != _callId) {
          _channel.send('call', {'t': 'busy', 'cid': cid});
        }
      case 'accept':
        if (cid != _callId || phase != CallPhase.outgoing) return;
        _ringTimer?.cancel();
        _ringTimeout?.cancel();
        phase = CallPhase.connecting;
        notifyListeners();
        await _createPeer();
        final offer = await _pc!.createOffer({'offerToReceiveAudio': 1, 'offerToReceiveVideo': video ? 1 : 0});
        await _pc!.setLocalDescription(offer);
        _send('offer', {'sdp': offer.sdp, 'sdpType': offer.type});
      case 'offer':
        if (cid != _callId || _pc == null) return;
        await _pc!.setRemoteDescription(RTCSessionDescription(m['sdp'] as String?, m['sdpType'] as String?));
        await _flushIce();
        final answer = await _pc!.createAnswer({'offerToReceiveAudio': 1, 'offerToReceiveVideo': video ? 1 : 0});
        await _pc!.setLocalDescription(answer);
        _send('answer', {'sdp': answer.sdp, 'sdpType': answer.type});
      case 'answer':
        if (cid != _callId || _pc == null) return;
        await _pc!.setRemoteDescription(RTCSessionDescription(m['sdp'] as String?, m['sdpType'] as String?));
        await _flushIce();
      case 'ice':
        if (cid != _callId) return;
        final c = RTCIceCandidate(m['c'] as String?, m['mid'] as String?, (m['idx'] as num?)?.toInt());
        if (_pc != null && _remoteSet) {
          await _pc!.addCandidate(c);
        } else {
          _pendingIce.add(c);
        }
      case 'decline':
        if (cid == _callId) _finish(notice: 'Call declined');
      case 'busy':
        if (cid == _callId && phase == CallPhase.outgoing) _finish(notice: 'They\'re on another call');
      case 'end':
        if (cid == _callId) _finish(notice: phase == CallPhase.incoming ? 'Missed call' : 'Call ended');
    }
  }

  Future<void> _flushIce() async {
    _remoteSet = true;
    for (final c in _pendingIce) {
      await _pc?.addCandidate(c);
    }
    _pendingIce.clear();
  }

  Future<void> _openMedia() async {
    await _ensureRenderers();
    _local = await navigator.mediaDevices.getUserMedia({
      'audio': {'echoCancellation': true, 'noiseSuppression': true},
      'video': video ? {'facingMode': 'user', 'width': {'ideal': 1280}, 'height': {'ideal': 720}} : false,
    });
    localRenderer.srcObject = _local;
    micOn = true;
    camOn = video;
    notifyListeners();
  }

  Future<void> _createPeer() async {
    final pc = await createPeerConnection(_rtcConfig);
    _pc = pc;
    for (final track in _local?.getTracks() ?? const <MediaStreamTrack>[]) {
      await pc.addTrack(track, _local!);
    }
    pc.onIceCandidate = (c) {
      if (c.candidate != null) _send('ice', {'c': c.candidate, 'mid': c.sdpMid, 'idx': c.sdpMLineIndex});
    };
    pc.onTrack = (e) {
      if (e.streams.isNotEmpty) {
        _remote = e.streams.first;
        remoteRenderer.srcObject = _remote;
        notifyListeners();
      }
    };
    pc.onConnectionState = (s) {
      switch (s) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _dropTimer?.cancel();
          phase = CallPhase.connected;
          connectedAt ??= DateTime.now();
          if (!kIsWeb) Helper.setSpeakerphoneOn(video || speakerOn);
          notifyListeners();
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          // Brief network blips recover on their own; give it a moment.
          _dropTimer?.cancel();
          _dropTimer = Timer(const Duration(seconds: 12), () => _finish(notice: 'Connection lost'));
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          _send('end');
          _finish(notice: 'Couldn\'t connect the call. Try again on Wi-Fi.');
        default:
          break;
      }
    };
  }

  Future<void> _finish({String? notice}) async {
    _ringTimer?.cancel();
    _ringTimeout?.cancel();
    _dropTimer?.cancel();
    final pc = _pc;
    final local = _local;
    _pc = null;
    _local = null;
    _remote = null;
    _remoteSet = false;
    _pendingIce.clear();
    _callId = null;
    connectedAt = null;
    phase = CallPhase.idle;
    minimized = false;
    this.notice = notice;
    if (_renderersReady) {
      localRenderer.srcObject = null;
      remoteRenderer.srcObject = null;
    }
    notifyListeners();
    try {
      for (final t in local?.getTracks() ?? const <MediaStreamTrack>[]) {
        await t.stop();
      }
      await local?.dispose();
      await pc?.close();
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (inCall) _send('end');
    _disposed = true;
    _finish();
    if (_renderersReady) {
      localRenderer.dispose();
      remoteRenderer.dispose();
    }
    super.dispose();
  }
}

/// One call manager per active circle (lives as long as the realtime channel).
final callManagerProvider = Provider<CallManager?>((ref) {
  final ch = ref.watch(circleChannelProvider);
  final uid = ref.watch(userIdProvider);
  if (ch == null || uid == null) return null;
  final m = CallManager(ch, uid);
  ref.onDispose(m.dispose);
  return m;
});
