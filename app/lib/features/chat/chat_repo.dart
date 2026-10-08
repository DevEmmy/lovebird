import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/supabase.dart';
import '../../data/media_repo.dart';
import '../../data/models.dart';
import '../../state/session.dart';

const _uuid = Uuid();

/// Latest messages (realtime). Older history loads on demand.
final messagesProvider = StreamProvider<List<Message>>((ref) {
  final circle = ref.watch(circleProvider).valueOrNull;
  if (circle == null) return Stream.value(const []);
  return sb
      .from('messages')
      .stream(primaryKey: ['id'])
      .eq('circle_id', circle.id)
      .order('created_at', ascending: false)
      .limit(300)
      .map((rows) => rows.map(Message.fromJson).toList());
});

final reactionsProvider = StreamProvider<Map<String, List<Reaction>>>((ref) {
  final circle = ref.watch(circleProvider).valueOrNull;
  if (circle == null) return Stream.value(const {});
  return sb.from('message_reactions').stream(primaryKey: ['message_id', 'user_id', 'emoji']).eq('circle_id', circle.id).map((rows) {
    final map = <String, List<Reaction>>{};
    for (final r in rows.map(Reaction.fromJson)) {
      (map[r.messageId] ??= []).add(r);
    }
    return map;
  });
});

/// My private last-read marker (never visible to my partner), as stored on the server…
final _serverLastReadProvider = FutureProvider<DateTime>((ref) async {
  final circle = ref.watch(circleProvider).valueOrNull;
  final uid = ref.watch(userIdProvider);
  if (circle == null || uid == null) return DateTime.fromMillisecondsSinceEpoch(0);
  final row = await sb.from('chat_reads').select('last_read_at').eq('circle_id', circle.id).eq('user_id', uid).maybeSingle();
  return row == null ? DateTime.fromMillisecondsSinceEpoch(0) : DateTime.parse(row['last_read_at'] as String);
});

/// …and updated locally the moment we mark messages read.
final lastReadProvider = StateProvider<DateTime?>((ref) => null);

final unreadCountProvider = Provider<AsyncValue<int>>((ref) {
  final uid = ref.watch(userIdProvider);
  final last = ref.watch(lastReadProvider) ?? ref.watch(_serverLastReadProvider).valueOrNull;
  return ref.watch(messagesProvider).whenData((msgs) {
    if (last == null) return 0;
    return msgs.where((m) => m.senderId != uid && !m.isDeleted && m.createdAt.isAfter(last)).length;
  });
});

/// Optimistic outbox: messages shown instantly, reconciled by client_id when the server echoes them.
class Outbox extends StateNotifier<List<Message>> {
  Outbox(this.ref) : super(const []);
  final Ref ref;

  Future<void> sendText(String circleId, String text, {String? replyTo}) =>
      _send(circleId: circleId, kind: 'text', body: text.trim(), replyTo: replyTo);

  Future<void> sendImage(String circleId, Uint8List bytes, String filename, {String? replyTo}) async {
    final path = await MediaRepo.instance.uploadToCircle(circleId: circleId, folder: 'chat', bytes: bytes, filename: filename);
    await _send(circleId: circleId, kind: 'image', mediaPath: path, replyTo: replyTo);
  }

  Future<void> sendVoice(String circleId, Uint8List bytes, Duration duration, String mime, String filename) async {
    final path = await MediaRepo.instance.uploadToCircle(
      circleId: circleId,
      folder: 'voice',
      bytes: bytes,
      filename: filename,
      mime: mime,
      durationMs: duration.inMilliseconds,
    );
    await _send(circleId: circleId, kind: 'voice', mediaPath: path, meta: {'duration_ms': duration.inMilliseconds});
  }

  Future<void> sendGif(String circleId, String url) => _send(circleId: circleId, kind: 'gif', meta: {'url': url});

  Future<void> _send({
    required String circleId,
    required String kind,
    String? body,
    String? mediaPath,
    String? replyTo,
    Map<String, dynamic> meta = const {},
    String? clientId,
  }) async {
    final cid = clientId ?? _uuid.v4();
    final local = Message(
      id: cid,
      circleId: circleId,
      senderId: requireUserId(),
      clientId: cid,
      kind: kind,
      body: body,
      mediaPath: mediaPath,
      meta: meta,
      replyTo: replyTo,
      createdAt: DateTime.now().toUtc(),
      pending: true,
    );
    state = [...state.where((m) => m.clientId != cid), local];
    try {
      await sb.from('messages').upsert(
        {
          'circle_id': circleId,
          'sender_id': local.senderId,
          'client_id': cid,
          'kind': kind,
          'body': body,
          'media_path': mediaPath,
          'meta': meta,
          'reply_to': replyTo,
        },
        onConflict: 'sender_id,client_id',
        ignoreDuplicates: true, // safe retries on flaky networks
      );
      state = state.where((m) => m.clientId != cid).toList();
    } catch (_) {
      state = [for (final m in state) m.clientId == cid ? m.copyWith(pending: false, failed: true) : m];
      rethrow;
    }
  }

  Future<void> retry(Message m) => _send(
        circleId: m.circleId,
        kind: m.kind,
        body: m.body,
        mediaPath: m.mediaPath,
        replyTo: m.replyTo,
        meta: m.meta,
        clientId: m.clientId,
      );

  void discard(Message m) => state = state.where((x) => x.clientId != m.clientId).toList();
}

final outboxProvider = StateNotifierProvider<Outbox, List<Message>>((ref) => Outbox(ref));

class ChatRepo {
  static Future<void> markRead(String circleId) => sb.rpc('mark_messages_read', params: {'p_circle': circleId, 'p_read': true});

  static Future<void> react(String circleId, String messageId, String emoji, {required bool remove}) async {
    final uid = requireUserId();
    if (remove) {
      await sb.from('message_reactions').delete().eq('message_id', messageId).eq('user_id', uid).eq('emoji', emoji);
    } else {
      await sb.from('message_reactions').insert({'message_id': messageId, 'circle_id': circleId, 'user_id': uid, 'emoji': emoji});
    }
  }

  static Future<void> delete(String messageId) => sb.rpc('delete_message', params: {'p_message': messageId});

  static Future<List<Message>> olderThan(String circleId, DateTime before, {int limit = 100}) async {
    final rows = await sb
        .from('messages')
        .select()
        .eq('circle_id', circleId)
        .lt('created_at', before.toUtc().toIso8601String())
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(Message.fromJson).toList();
  }
}
