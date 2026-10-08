import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/supabase.dart';
import '../../core/widgets/widgets.dart';
import '../../state/session.dart';

/// Reporting workflow (brief §51). Private content stays private by default:
/// only the snapshot the reporter explicitly chooses to include is shared with moderators.
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key, this.snapshot});
  final Map<String, dynamic>? snapshot;
  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  static const categories = {
    'abuse': 'Abuse',
    'harassment': 'Harassment',
    'inappropriate': 'Inappropriate content',
    'illegal': 'Illegal content',
    'account_abuse': 'Account abuse / hacked account',
    'competition_manipulation': 'Competition manipulation',
    'other': 'Something else',
  };
  String _category = 'abuse';
  final _desc = TextEditingController();
  late bool _includeSnapshot = widget.snapshot != null;
  bool _busy = false;
  bool _sent = false;

  Future<void> _submit() async {
    if (_desc.text.trim().isEmpty) return showToast(context, 'Please tell us what happened.');
    setState(() => _busy = true);
    try {
      final circle = ref.read(circleProvider).valueOrNull;
      final partner = ref.read(partnerProvider).valueOrNull;
      await sb.from('reports').insert({
        'reporter_id': requireUserId(),
        'circle_id': circle?.id,
        'target_user_id': widget.snapshot != null ? partner?.id : null,
        'category': _category,
        'description': _desc.text.trim(),
        'snapshot': _includeSnapshot ? widget.snapshot : <String, dynamic>{},
      });
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (_sent) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          emoji: '🛡️',
          title: 'Thank you for telling us',
          message: 'Our team will review your report. If you\'re in immediate danger, please contact local emergency services.',
          action: FilledButton(onPressed: () => context.pop(), child: const Text('Done')),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Report a problem')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Constrained(
          maxWidth: 600,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('What\'s going on?', style: t.titleLarge),
            const SizedBox(height: 10),
            RadioGroupFallback(
              value: _category,
              options: categories,
              onChanged: (v) => setState(() => _category = v),
            ),
            const SizedBox(height: 12),
            TextField(controller: _desc, minLines: 4, maxLines: 8, maxLength: 4000, decoration: const InputDecoration(labelText: 'Describe what happened')),
            if (widget.snapshot != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _includeSnapshot,
                onChanged: (v) => setState(() => _includeSnapshot = v),
                title: const Text('Include the reported message'),
                subtitle: Text('"${widget.snapshot!['body'] ?? '[${widget.snapshot!['kind']}]'}" — moderators only see what you include.'),
              ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _busy ? null : _submit, child: const Text('Send report')),
            const SizedBox(height: 12),
            Text('If you are in immediate danger, contact local emergency services.', style: t.bodySmall, textAlign: TextAlign.center),
          ]),
        ),
      ]),
    );
  }
}

/// Simple accessible single-choice list (works across Flutter versions).
class RadioGroupFallback extends StatelessWidget {
  const RadioGroupFallback({super.key, required this.value, required this.options, required this.onChanged});
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => Column(children: [
        for (final o in options.entries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(value == o.key ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: Theme.of(context).colorScheme.primary),
            title: Text(o.value),
            selected: value == o.key,
            onTap: () => onChanged(o.key),
          ),
      ]);
}
