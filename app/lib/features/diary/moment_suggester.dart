import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../core/supabase.dart';
import '../../data/models.dart';
import 'diary_repo.dart';

/// "Remember this?" (brief §23, §26).
///
/// Privacy: detection runs ON THE DEVICE with simple heuristics. Private messages
/// are never sent to an AI service to decide what's memorable.
/// Fatigue: the server (`may_suggest`) allows at most one suggestion per ~day per
/// person, and backs off after repeated "Not now".
class MomentSuggestion {
  const MomentSuggestion({
    required this.kind,
    required this.headline,
    required this.prompt,
    required this.entryType,
    required this.title,
    this.body,
    this.payload = const {},
  });

  final String kind;
  final String headline;
  final String prompt;
  final String entryType;
  final String title;
  final String? body;
  final Map<String, dynamic> payload;
}

class MomentSuggester {
  static final _laugh = RegExp(r'(😂|🤣|😆|😹|\blo+l+\b|\blmf?a+o+\b|\bha(ha)+h?\b|\bhe(he)+\b|\bdead\b|💀)', caseSensitive: false);
  static final _love = RegExp(r'(❤️|❤|😍|🥰|😘|💕|💖|\bi love you\b|\blove you\b|\bmiss you\b|\bproud of you\b)', caseSensitive: false);
  static DateTime? _lastLocal;

  /// Looks at the most recent messages (newest first) for a burst of shared laughter
  /// or a tender exchange from both partners within a few minutes.
  static MomentSuggestion? fromChat(List<Message> newestFirst, String me) {
    final recent = newestFirst.where((m) => m.kind == 'text' && !m.isDeleted && m.body != null).take(12).toList();
    if (recent.length < 4) return null;
    final window = recent.where((m) => recent.first.createdAt.difference(m.createdAt).inMinutes <= 4).toList();
    final laughers = window.where((m) => _laugh.hasMatch(m.body!)).map((m) => m.senderId).toSet();
    final laughs = window.where((m) => _laugh.hasMatch(m.body!)).length;
    final quotes = window.reversed.take(6).map((m) => {'sender_id': m.senderId, 'body': m.body, 'at': m.createdAt.toIso8601String()}).toList();
    if (laughers.length == 2 && laughs >= 3) {
      return MomentSuggestion(
        kind: 'chat_funny',
        headline: '😂 That was too funny to forget.',
        prompt: 'Save this moment to Our Diary?',
        entryType: 'funny',
        title: 'That time we couldn\'t stop laughing',
        payload: {'messages': quotes},
      );
    }
    final lovers = window.where((m) => _love.hasMatch(m.body!)).map((m) => m.senderId).toSet();
    if (lovers.length == 2 && window.length >= 4) {
      return MomentSuggestion(
        kind: 'chat_romantic',
        headline: '❤️ This feels like a Lovebird memory.',
        prompt: 'Save it to Our Diary?',
        entryType: 'romantic',
        title: 'A sweet moment',
        payload: {'messages': quotes},
      );
    }
    return null;
  }

  /// Ask the server whether we may suggest now, then show a gentle bottom sheet.
  static Future<void> maybeSuggest(BuildContext context, String circleId, MomentSuggestion s) async {
    // Local debounce so we don't even hit the server repeatedly.
    if (_lastLocal != null && DateTime.now().difference(_lastLocal!).inMinutes < 30) return;
    _lastLocal = DateTime.now();
    try {
      final allowed = await sb.rpc('may_suggest', params: {'p_circle': circleId, 'p_kind': s.kind}) as bool? ?? false;
      if (!allowed || !context.mounted) return;
      await _log(circleId, s.kind, 'shown');
      if (!context.mounted) return;
      final saved = await showModalBottomSheet<bool>(
        context: context,
        builder: (ctx) => _SuggestionSheet(s: s),
      );
      if (saved == true) {
        await DiaryRepo.create(
          circleId: circleId,
          entryType: s.entryType,
          origin: 'suggested',
          title: s.title,
          body: s.body,
          payload: s.payload,
        );
        await _log(circleId, s.kind, 'saved');
        if (context.mounted) showToast(context, 'Saved to Our Diary ❤️');
      } else {
        await _log(circleId, s.kind, 'dismissed');
      }
    } catch (_) {
      // Suggestions are a nicety — never interrupt the moment with an error.
    }
  }

  static Future<void> _log(String circleId, String kind, String outcome) =>
      sb.from('suggestion_log').insert({'circle_id': circleId, 'user_id': requireUserId(), 'kind': kind, 'outcome': outcome});
}

class _SuggestionSheet extends StatelessWidget {
  const _SuggestionSheet({required this.s});
  final MomentSuggestion s;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(s.headline, style: t.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(s.prompt, style: t.bodyLarge, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save moment')),
          const SizedBox(height: 8),
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
        ]),
      ),
    );
  }
}
