import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/errors.dart';
import '../../core/theme/colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/widgets.dart';
import '../../data/media_repo.dart';
import '../../data/models.dart';
import '../../state/session.dart';
import '../calls/call_sheet.dart';
import '../diary/diary_repo.dart';
import '../diary/moment_suggester.dart';
import 'chat_repo.dart';
import 'voice_note.dart';

const quickReactions = ['❤️', '😂', '😮', '🥺', '🔥', '👍'];

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, this.embedded = false});

  /// Embedded = compact chat used inside Movie Night / games.
  final bool embedded;
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> with WidgetsBindingObserver {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _voice = VoiceRecorderController();
  Message? _replyTo;
  bool _partnerTyping = false;
  Timer? _typingTimer;
  DateTime _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);
  StreamSubscription<Map<String, dynamic>>? _typingSub;
  Timer? _recordTicker;
  Timer? _readDebounce;
  final _older = <Message>[];
  bool _loadingOlder = false;
  bool _noMoreOlder = false;
  String? _lastSeenNewestId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _typingSub?.cancel();
    _typingTimer?.cancel();
    _recordTicker?.cancel();
    _readDebounce?.cancel();
    _voice.dispose();
    _text.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _markRead();
  }

  String get _circleId => ref.read(circleIdProvider);

  void _markRead() {
    _readDebounce?.cancel();
    _readDebounce = Timer(const Duration(milliseconds: 600), () async {
      try {
        await ChatRepo.markRead(_circleId);
        ref.read(lastReadProvider.notifier).state = DateTime.now();
      } catch (_) {}
    });
  }

  void _onScroll() {
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _loadOlder();
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || _noMoreOlder) return;
    final current = ref.read(messagesProvider).valueOrNull ?? const [];
    if (current.length < 300) return; // stream already holds everything
    final oldest = _older.isNotEmpty ? _older.last : current.last;
    setState(() => _loadingOlder = true);
    try {
      final more = await ChatRepo.olderThan(_circleId, oldest.createdAt);
      setState(() {
        _older.addAll(more);
        _noMoreOlder = more.isEmpty;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  void _listenTyping() {
    final ch = ref.read(circleChannelProvider);
    if (ch == null || _typingSub != null) return;
    _typingSub = ch.on('typing').listen((_) {
      setState(() => _partnerTyping = true);
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 4), () => mounted ? setState(() => _partnerTyping = false) : null);
    });
  }

  void _onTyping() {
    final now = DateTime.now();
    if (now.difference(_lastTypingSent).inMilliseconds < 2500) return;
    _lastTypingSent = now;
    ref.read(circleChannelProvider)?.send('typing', {});
  }

  Future<void> _sendText() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    final reply = _replyTo;
    _text.clear();
    setState(() => _replyTo = null);
    try {
      await ref.read(outboxProvider.notifier).sendText(_circleId, text, replyTo: reply?.id);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final files = await MediaRepo.instance.pickPhotos(multiple: false, source: source);
    if (files.isEmpty) return;
    final reply = _replyTo;
    setState(() => _replyTo = null);
    if (!mounted) return;
    await guard(context, () async {
      final f = files.first;
      await ref.read(outboxProvider.notifier).sendImage(_circleId, await f.readAsBytes(), f.name, replyTo: reply?.id);
    });
  }

  Future<void> _toggleRecording() async {
    if (_voice.isRecording) {
      _recordTicker?.cancel();
      final rec = await _voice.stop();
      setState(() {});
      if (rec == null || !mounted) return;
      await guard(context, () => ref.read(outboxProvider.notifier).sendVoice(_circleId, rec.bytes, rec.duration, rec.mime, rec.filename));
    } else {
      final ok = await _voice.start();
      if (!ok) {
        if (mounted) showToast(context, 'Allow microphone access to send voice notes.');
        return;
      }
      HapticFeedback.mediumImpact();
      _recordTicker = Timer.periodic(const Duration(milliseconds: 250), (_) => setState(() {}));
      setState(() {});
    }
  }

  Future<void> _cancelRecording() async {
    _recordTicker?.cancel();
    await _voice.cancel();
    setState(() {});
  }

  void _maybeSuggestMoment(List<Message> msgs) {
    if (msgs.isEmpty || msgs.first.id == _lastSeenNewestId) return;
    final isFirstLoad = _lastSeenNewestId == null;
    _lastSeenNewestId = msgs.first.id;
    if (isFirstLoad) return;
    final s = MomentSuggester.fromChat(msgs, ref.read(userIdProvider)!);
    if (s != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) MomentSuggester.maybeSuggest(context, _circleId, s);
      });
    }
  }

  Future<void> _showActions(Message m) async {
    final uid = ref.read(userIdProvider);
    final mine = m.senderId == uid;
    final myReactions = (ref.read(reactionsProvider).valueOrNull?[m.id] ?? const []).where((r) => r.userId == uid).map((r) => r.emoji).toSet();
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              for (final e in quickReactions)
                Semantics(
                  button: true,
                  label: 'React $e',
                  child: InkResponse(
                    onTap: () => Navigator.pop(ctx, 'react:$e'),
                    radius: 28,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: myReactions.contains(e) ? Theme.of(ctx).colorScheme.primaryContainer : null,
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 28)),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          if (!m.isDeleted) ListTile(leading: const Icon(Icons.reply_rounded), title: const Text('Reply'), onTap: () => Navigator.pop(ctx, 'reply')),
          if (m.kind == 'text' && !m.isDeleted)
            ListTile(leading: const Icon(Icons.copy_rounded), title: const Text('Copy'), onTap: () => Navigator.pop(ctx, 'copy')),
          if (!m.isDeleted)
            ListTile(leading: const Icon(Icons.auto_stories_outlined), title: const Text('Save to Our Diary'), onTap: () => Navigator.pop(ctx, 'diary')),
          if (mine && !m.isDeleted)
            ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Delete for both of us'), onTap: () => Navigator.pop(ctx, 'delete')),
          if (!mine)
            ListTile(leading: const Icon(Icons.flag_outlined), title: const Text('Report'), onTap: () => Navigator.pop(ctx, 'report')),
        ]),
      ),
    );
    if (action == null || !mounted) return;
    if (action.startsWith('react:')) {
      final e = action.substring(6);
      await guard(context, () => ChatRepo.react(_circleId, m.id, e, remove: myReactions.contains(e)));
      ref.invalidate(reactionsProvider);
    } else if (action == 'reply') {
      setState(() => _replyTo = m);
      _focus.requestFocus();
    } else if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: m.body ?? ''));
      if (mounted) showToast(context, 'Copied');
    } else if (action == 'diary') {
      await guard(context, () async {
        await DiaryRepo.create(
          circleId: _circleId,
          entryType: 'chat',
          title: 'A message worth keeping',
          body: m.kind == 'text' ? m.body : null,
          photoPaths: m.kind == 'image' && m.mediaPath != null ? [m.mediaPath!] : const [],
          payload: {
            'messages': [
              {'sender_id': m.senderId, 'body': m.body, 'at': m.createdAt.toIso8601String()}
            ]
          },
        );
        if (mounted) showToast(context, 'Saved to Our Diary ❤️');
      });
    } else if (action == 'delete') {
      final ok = await confirmDialog(context, title: 'Delete message?', message: 'It will be removed for both of you.', confirm: 'Delete', destructive: true);
      if (ok && mounted) await guard(context, () => ChatRepo.delete(m.id));
    } else if (action == 'report') {
      context.push('/report', extra: {
        'type': 'message',
        'message_id': m.id,
        'body': m.body,
        'kind': m.kind,
        'at': m.createdAt.toIso8601String(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    _listenTyping();
    final uid = ref.watch(userIdProvider);
    final partner = ref.watch(partnerProvider).valueOrNull;
    final channel = ref.watch(circleChannelProvider);
    final messagesAsync = ref.watch(messagesProvider);
    final outbox = ref.watch(outboxProvider);
    final reactions = ref.watch(reactionsProvider).valueOrNull ?? const {};

    ref.listen(messagesProvider, (prev, next) {
      final list = next.valueOrNull;
      if (list == null) return;
      if (list.isNotEmpty && list.first.senderId != uid) _markRead();
      _maybeSuggestMoment(list);
    });

    final body = messagesAsync.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(messagesProvider)),
      data: (serverMsgs) {
        if (_lastSeenNewestId == null && serverMsgs.isNotEmpty) {
          _lastSeenNewestId = serverMsgs.first.id;
          _markRead();
        }
        final serverClientIds = serverMsgs.map((m) => m.clientId).toSet();
        final pending = outbox.where((m) => !serverClientIds.contains(m.clientId)).toList().reversed;
        final all = [...pending, ...serverMsgs, ..._older];
        final byId = {for (final m in all) m.id: m};
        if (all.isEmpty) {
          return EmptyState(
            emoji: '💌',
            title: 'Say hello ❤️',
            message: 'This chat is just for you two. Nobody else can ever read it.',
          );
        }
        return ListView.builder(
          controller: _scroll,
          reverse: true,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          itemCount: all.length + (_loadingOlder ? 1 : 0),
          itemBuilder: (context, i) {
            if (i == all.length) return const Padding(padding: EdgeInsets.all(12), child: LoadingView());
            final m = all[i];
            final older = i + 1 < all.length ? all[i + 1] : null;
            final newer = i > 0 ? all[i - 1] : null;
            final showDay = older == null || Fmt.chatDayLabel(older.createdAt) != Fmt.chatDayLabel(m.createdAt);
            final groupedWithNewer = newer != null &&
                newer.senderId == m.senderId &&
                newer.createdAt.difference(m.createdAt).inMinutes < 3 &&
                Fmt.chatDayLabel(newer.createdAt) == Fmt.chatDayLabel(m.createdAt);
            return Column(children: [
              if (showDay) _DayDivider(label: Fmt.chatDayLabel(m.createdAt)),
              MessageBubble(
                message: m,
                mine: m.senderId == uid,
                replyTo: m.replyTo == null ? null : byId[m.replyTo],
                reactions: reactions[m.id] ?? const [],
                showTail: !groupedWithNewer,
                partnerReceipts: partner?.readReceipts ?? true,
                onLongPress: () => _showActions(m),
                onRetry: () => guard(context, () => ref.read(outboxProvider.notifier).retry(m)),
                onDiscard: () => ref.read(outboxProvider.notifier).discard(m),
                onReactionTap: (e, mineReacted) async {
                  await guard(context, () => ChatRepo.react(_circleId, m.id, e, remove: mineReacted));
                  ref.invalidate(reactionsProvider);
                },
              ),
            ]);
          },
        );
      },
    );

    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              titleSpacing: 8,
              title: channel == null
                  ? Text(partner?.displayName ?? 'Chat')
                  : ValueListenableBuilder<Map<String, Map<String, dynamic>>>(
                      valueListenable: channel.online,
                      builder: (context, _, __) {
                        final isOnline = channel.isOnline(partner?.id);
                        return Row(children: [
                          LBAvatar(profile: partner, size: 38, online: isOnline),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(partner?.displayName ?? 'Your partner', overflow: TextOverflow.ellipsis),
                              Text(
                                _partnerTyping ? 'typing…' : (isOnline ? 'online' : 'offline'),
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: _partnerTyping ? Theme.of(context).colorScheme.primary : null,
                                    ),
                              ),
                            ]),
                          ),
                        ]);
                      },
                    ),
              actions: const [CallBar(), SizedBox(width: 4)],
            ),
      body: Stack(children: [
        Column(children: [
          Expanded(child: body),
          if (widget.embedded && _partnerTyping)
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 4),
              child: Align(alignment: Alignment.centerLeft, child: Text('${partner?.displayName ?? 'Partner'} is typing…', style: Theme.of(context).textTheme.bodySmall)),
            ),
          _Composer(
            controller: _text,
            focus: _focus,
            replyTo: _replyTo,
            replyName: _replyTo == null ? null : (_replyTo!.senderId == uid ? 'yourself' : partner?.displayName ?? 'partner'),
            recording: _voice.isRecording,
            recordElapsed: _voice.elapsed,
            compact: widget.embedded,
            onCancelReply: () => setState(() => _replyTo = null),
            onChanged: (_) => _onTyping(),
            onSend: _sendText,
            onPhoto: () => _pickPhoto(ImageSource.gallery),
            onCamera: () => _pickPhoto(ImageSource.camera),
            onMic: _toggleRecording,
            onCancelRecording: _cancelRecording,
          ),
        ]),
      ]),
    );
  }
}

class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(99)),
            child: Text(label, style: Theme.of(context).textTheme.labelMedium),
          ),
        ),
      );
}

class MessageBubble extends ConsumerWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.mine,
    required this.reactions,
    required this.showTail,
    required this.partnerReceipts,
    required this.onLongPress,
    required this.onRetry,
    required this.onDiscard,
    required this.onReactionTap,
    this.replyTo,
  });

  final Message message;
  final bool mine;
  final Message? replyTo;
  final List<Reaction> reactions;
  final bool showTail;
  final bool partnerReceipts;
  final VoidCallback onLongPress;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;
  final void Function(String emoji, bool mineReacted) onReactionTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final uid = ref.watch(userIdProvider);
    final nameOf = ref.watch(nameOfProvider);
    final bg = mine ? (dark ? const Color(0xFF8E2450) : LBColors.rose) : scheme.surfaceContainerLowest;
    final fg = mine ? Colors.white : scheme.onSurface;
    final m = message;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(20),
      topRight: const Radius.circular(20),
      bottomLeft: Radius.circular(mine || !showTail ? 20 : 6),
      bottomRight: Radius.circular(!mine || !showTail ? 20 : 6),
    );

    Widget content;
    if (m.isDeleted) {
      content = Text('This message was deleted', style: TextStyle(color: fg.withValues(alpha: 0.75), fontStyle: FontStyle.italic));
    } else {
      switch (m.kind) {
        case 'image':
          content = GestureDetector(
            onTap: () => _openImage(context, m.mediaPath!),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280, maxWidth: 240),
                child: StorageImage(m.mediaPath!, width: 240, height: 240),
              ),
            ),
          );
        case 'voice':
          content = VoiceNotePlayer(path: m.mediaPath!, durationMs: (m.meta['duration_ms'] as num?)?.toInt() ?? 0, color: fg);
        case 'gif':
          content = ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(m.meta['url'] as String? ?? '', width: 220, fit: BoxFit.cover, semanticLabel: 'GIF'),
          );
        default:
          content = SelectableText(m.body ?? '', style: TextStyle(color: fg, fontSize: 15.5, height: 1.35));
      }
    }

    final grouped = <String, List<Reaction>>{};
    for (final r in reactions) {
      (grouped[r.emoji] ??= []).add(r);
    }

    Widget? status;
    if (mine) {
      IconData icon;
      Color color = fg.withValues(alpha: 0.8);
      String label;
      if (m.failed) {
        icon = Icons.error_outline;
        color = Colors.white;
        label = 'Failed';
      } else if (m.pending) {
        icon = Icons.schedule;
        label = 'Sending';
      } else if (m.readAt != null && partnerReceipts) {
        icon = Icons.done_all;
        color = dark ? LBColors.petal : const Color(0xFFFFD6E4);
        label = 'Read';
      } else if (m.deliveredAt != null) {
        icon = Icons.done_all;
        label = 'Delivered';
      } else {
        icon = Icons.done;
        label = 'Sent';
      }
      status = Icon(icon, size: 14, color: color, semanticLabel: label);
    }

    return Padding(
      padding: EdgeInsets.only(top: 2, bottom: showTail ? 8 : 2),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78 > 520 ? 520 : MediaQuery.sizeOf(context).width * 0.78),
              child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
                GestureDetector(
                  onLongPress: m.pending ? null : onLongPress,
                  onSecondaryTap: m.pending ? null : onLongPress,
                  child: Container(
                    padding: m.kind == 'image' || m.kind == 'gif' ? const EdgeInsets.all(4) : const EdgeInsets.fromLTRB(14, 10, 14, 8),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: radius,
                      border: mine ? null : Border.all(color: scheme.outlineVariant),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      if (replyTo != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: (mine ? Colors.white : scheme.primary).withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(10),
                            border: Border(left: BorderSide(color: mine ? Colors.white : scheme.primary, width: 3)),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(replyTo!.senderId == uid ? 'You' : nameOf(replyTo!.senderId),
                                style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12)),
                            Text(
                              replyTo!.isDeleted ? 'Deleted message' : (replyTo!.kind == 'text' ? replyTo!.body ?? '' : (replyTo!.kind == 'image' ? '📷 Photo' : '🎤 Voice note')),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: fg.withValues(alpha: 0.85), fontSize: 13),
                            ),
                          ]),
                        ),
                      content,
                      const SizedBox(height: 3),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(Fmt.time(m.createdAt), style: TextStyle(color: fg.withValues(alpha: 0.75), fontSize: 11)),
                        if (status != null) ...[const SizedBox(width: 4), status],
                      ]),
                    ]),
                  ),
                ),
                if (m.failed)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    TextButton(onPressed: onRetry, child: const Text('Retry')),
                    TextButton(onPressed: onDiscard, child: const Text('Discard')),
                  ]),
                if (grouped.isNotEmpty)
                  Transform.translate(
                    offset: const Offset(0, -6),
                    child: Wrap(spacing: 4, children: [
                      for (final entry in grouped.entries)
                        _ReactionChip(
                          emoji: entry.key,
                          count: entry.value.length,
                          mine: entry.value.any((r) => r.userId == uid),
                          onTap: () => onReactionTap(entry.key, entry.value.any((r) => r.userId == uid)),
                        ),
                    ]),
                  ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  void _openImage(BuildContext context, String path) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: Center(child: InteractiveViewer(child: StorageImage(path, fit: BoxFit.contain))),
      ),
    ));
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({required this.emoji, required this.count, required this.mine, required this.onTap});
  final String emoji;
  final int count;
  final bool mine;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: '$emoji reaction, $count',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: mine ? scheme.primaryContainer : scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: mine ? scheme.primary : scheme.outlineVariant),
          ),
          child: Text(count > 1 ? '$emoji $count' : emoji, style: const TextStyle(fontSize: 14)),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focus,
    required this.replyTo,
    required this.replyName,
    required this.recording,
    required this.recordElapsed,
    required this.compact,
    required this.onCancelReply,
    required this.onChanged,
    required this.onSend,
    required this.onPhoto,
    required this.onCamera,
    required this.onMic,
    required this.onCancelRecording,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final Message? replyTo;
  final String? replyName;
  final bool recording;
  final Duration recordElapsed;
  final bool compact;
  final VoidCallback onCancelReply;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;
  final VoidCallback onPhoto;
  final VoidCallback onCamera;
  final VoidCallback onMic;
  final VoidCallback onCancelRecording;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasText = controller.text.trim().isNotEmpty;
    return Material(
      color: scheme.surfaceContainerLowest,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (replyTo != null)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      'Replying to $replyName: ${replyTo!.kind == 'text' ? replyTo!.body : (replyTo!.kind == 'image' ? '📷 Photo' : '🎤 Voice note')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(tooltip: 'Cancel reply', onPressed: onCancelReply, icon: const Icon(Icons.close, size: 18)),
                ]),
              ),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (recording) ...[
                IconButton(tooltip: 'Cancel recording', onPressed: onCancelRecording, icon: const Icon(Icons.delete_outline)),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Row(children: [
                      const Icon(Icons.fiber_manual_record, color: LBColors.danger, size: 14),
                      const SizedBox(width: 6),
                      Text('Recording  ${Fmt.duration(recordElapsed)}'),
                    ]),
                  ),
                ),
              ] else ...[
                if (!compact) IconButton(tooltip: 'Take a photo', onPressed: onCamera, icon: const Icon(Icons.photo_camera_outlined)),
                IconButton(tooltip: 'Send a photo', onPressed: onPhoto, icon: const Icon(Icons.image_outlined)),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focus,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 4000,
                    textCapitalization: TextCapitalization.sentences,
                    keyboardType: TextInputType.multiline,
                    onChanged: onChanged,
                    decoration: const InputDecoration(
                      hintText: 'Message',
                      counterText: '',
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              if (hasText && !recording)
                IconButton.filled(tooltip: 'Send', onPressed: onSend, icon: const Icon(Icons.send_rounded))
              else
                IconButton.filled(
                  tooltip: recording ? 'Send voice note' : 'Record a voice note',
                  onPressed: onMic,
                  icon: Icon(recording ? Icons.send_rounded : Icons.mic_none_rounded),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}
