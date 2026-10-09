import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase.dart';

/// The couple's private realtime channel "circle:{id}".
/// Authorization is enforced server-side by RLS on realtime.messages
/// (only live members of an active circle can join or send).
///
/// Used for ephemeral, low-latency things that shouldn't hit the database:
/// typing, presence/online, movie playback ticks, game nudges, reactions.
class CircleChannel {
  CircleChannel({required this.circleId, required this.userId, required this.trackPresence}) {
    _channel = sb.channel(
      'circle:$circleId',
      opts: RealtimeChannelConfig(private: true, key: userId),
    );
    for (final event in events) {
      _controllers[event] = StreamController<Map<String, dynamic>>.broadcast();
      _channel.onBroadcast(
        event: event,
        callback: (raw) {
          // Payload shape differs slightly across client versions; normalise.
          // App data travels under its own key ("d") so fields like `type`
          // can never collide with the realtime envelope.
          final inner = raw['payload'];
          final body = (inner is Map && inner['d'] is Map) ? inner['d'] : raw['d'];
          if (body is! Map) return;
          final data = Map<String, dynamic>.from(body);
          if (data['from'] == userId) return; // ignore our own echoes
          _controllers[event]?.add(data);
        },
      );
    }
    _channel.onPresenceSync((_) => _syncPresence());
    _channel.onPresenceJoin((_) => _syncPresence());
    _channel.onPresenceLeave((_) => _syncPresence());
    _channel.subscribe((status, error) async {
      connected.value = status == RealtimeSubscribeStatus.subscribed;
      if (status == RealtimeSubscribeStatus.subscribed && trackPresence) {
        await _track();
      }
    });
  }

  static const events = ['typing', 'together', 'movie', 'game', 'reaction', 'date_step', 'reading', 'nudge', 'arcade', 'call'];

  final String circleId;
  final String userId;
  final bool trackPresence;
  late final RealtimeChannel _channel;
  final _controllers = <String, StreamController<Map<String, dynamic>>>{};
  String? _activity;

  /// user_id -> presence payload (online_at, activity)
  final online = ValueNotifier<Map<String, Map<String, dynamic>>>({});
  final connected = ValueNotifier<bool>(false);

  Stream<Map<String, dynamic>> on(String event) {
    assert(events.contains(event), 'Unknown event $event');
    return _controllers[event]!.stream;
  }

  Future<void> send(String event, Map<String, dynamic> payload) async {
    try {
      await _channel.sendBroadcastMessage(event: event, payload: {'d': {...payload, 'from': userId}});
    } catch (e) {
      debugPrint('broadcast failed: $e');
    }
  }

  bool isOnline(String? uid) => uid != null && online.value.containsKey(uid);
  String? activityOf(String? uid) => uid == null ? null : online.value[uid]?['activity'] as String?;

  /// Shown to the partner, e.g. "watching", "reading ch. 3".
  Future<void> setActivity(String? activity) async {
    _activity = activity;
    if (trackPresence && connected.value) await _track();
  }

  Future<void> _track() async {
    try {
      await _channel.track({
        'user_id': userId,
        'online_at': DateTime.now().toUtc().toIso8601String(),
        'activity': _activity,
      });
    } catch (e) {
      debugPrint('presence track failed: $e');
    }
  }

  void _syncPresence() {
    final next = <String, Map<String, dynamic>>{};
    for (final state in _channel.presenceState()) {
      for (final p in state.presences) {
        final payload = Map<String, dynamic>.from(p.payload);
        final uid = payload['user_id'] as String?;
        if (uid != null) next[uid] = payload;
      }
    }
    online.value = next;
  }

  Future<void> dispose() async {
    for (final c in _controllers.values) {
      await c.close();
    }
    online.dispose();
    connected.dispose();
    await sb.removeChannel(_channel);
  }
}
