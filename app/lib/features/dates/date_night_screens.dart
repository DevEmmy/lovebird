import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/theme/colors.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/widgets.dart';
import '../../data/together_repo.dart';
import '../../state/circle_channel.dart';
import '../../state/session.dart';
import '../diary/diary_repo.dart';
import 'date_night_guides.dart';

class DateNightScreen extends ConsumerWidget {
  const DateNightScreen({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref, DateGuide g) async {
    await guard(context, () => TogetherRepo.start(
          circleId: ref.read(circleIdProvider),
          activity: 'date',
          refType: 'date',
          title: '${g.key}|${g.emoji} ${g.title}',
        ));
    if (context.mounted) context.push('/date-night/${g.key}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Date Night 🍿')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        Constrained(
          maxWidth: 860,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Pick a date. Lovebird guides you both, step by step, in sync.', style: t.bodyLarge),
            const SizedBox(height: 16),
            LBCard(
              gradient: LBColors.heroGradient,
              onTap: () => _open(context, ref, DateNightGuides.all[Random().nextInt(DateNightGuides.all.length)]),
              child: Row(children: [
                const Text('🎲', style: TextStyle(fontSize: 30)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Surprise Date', style: t.titleLarge?.copyWith(color: Colors.white)),
                    Text('Let Lovebird choose tonight\'s date.', style: t.bodyMedium?.copyWith(color: Colors.white)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            for (final g in DateNightGuides.all)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: LBCard(
                  onTap: () => _open(context, ref, g),
                  child: Row(children: [
                    Text(g.emoji, style: const TextStyle(fontSize: 30)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(g.title, style: t.titleMedium),
                        Text(g.blurb, style: t.bodySmall),
                      ]),
                    ),
                    Text('${g.steps.length} steps', style: t.labelMedium),
                  ]),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: () => context.push('/date-ideas'), icon: const Icon(Icons.lightbulb_outline), label: const Text('Need ideas? Date Idea Generator')),
          ]),
        ),
      ]),
    );
  }
}

/// Step-by-step guide; step index syncs between partners over the circle channel.
class DateNightGuideScreen extends ConsumerStatefulWidget {
  const DateNightGuideScreen({super.key, required this.guideKey});
  final String guideKey;
  @override
  ConsumerState<DateNightGuideScreen> createState() => _DateNightGuideScreenState();
}

class _DateNightGuideScreenState extends ConsumerState<DateNightGuideScreen> {
  int _step = 0;
  StreamSubscription<Map<String, dynamic>>? _sub;
  CircleChannel? _channel;
  Timer? _timer;
  Duration? _remaining;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _channel = ref.read(circleChannelProvider);
      _channel?.setActivity('on a date');
      _sub = _channel?.on('date_step').listen((e) {
        if (e['guide'] != widget.guideKey || !mounted) return;
        if (e['hello'] == true) {
          // Partner just arrived: bring them to where we are instead of resetting us.
          _channel?.send('date_step', {'guide': widget.guideKey, 'step': _step});
          return;
        }
        _goTo((e['step'] as num).toInt(), broadcast: false);
      });
      _channel?.send('date_step', {'guide': widget.guideKey, 'step': _step, 'hello': true});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    _channel?.setActivity(null);
    super.dispose();
  }

  void _goTo(int step, {bool broadcast = true}) {
    _timer?.cancel();
    setState(() {
      _step = step;
      _remaining = null;
    });
    if (broadcast) _channel?.send('date_step', {'guide': widget.guideKey, 'step': step});
  }

  void _startTimer(int minutes) {
    _timer?.cancel();
    setState(() => _remaining = Duration(minutes: minutes));
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      final r = _remaining! - const Duration(seconds: 1);
      if (r <= Duration.zero) {
        t.cancel();
        setState(() => _remaining = Duration.zero);
        showToast(context, 'Time\'s up! ⏰');
      } else {
        setState(() => _remaining = r);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final g = DateNightGuides.byKey(widget.guideKey);
    if (g == null) return Scaffold(appBar: AppBar(), body: const EmptyState(emoji: '🕊️', title: 'Date not found'));
    final t = Theme.of(context).textTheme;
    final step = g.steps[_step];
    final last = _step == g.steps.length - 1;
    return Scaffold(
      appBar: AppBar(title: Text('${g.emoji} ${g.title}')),
      body: Constrained(
        maxWidth: 640,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Row(children: [
            for (var i = 0; i < g.steps.length; i++)
              Expanded(
                child: Container(
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: i <= _step ? LBColors.rose : Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 8),
          Text('Step ${_step + 1} of ${g.steps.length} · you\'re both on this step', style: t.labelMedium),
          const SizedBox(height: 20),
          Semantics(
            liveRegion: true,
            child: LBCard(
              padding: const EdgeInsets.all(24),
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(step.title, style: t.headlineSmall),
                const SizedBox(height: 10),
                Text(step.body, style: t.bodyLarge),
                if (step.minutes != null) ...[
                  const SizedBox(height: 16),
                  if (_remaining == null)
                    OutlinedButton.icon(onPressed: () => _startTimer(step.minutes!), icon: const Icon(Icons.timer_outlined), label: Text('Start ${step.minutes} min timer'))
                  else
                    Text('⏱ ${Fmt.duration(_remaining!)}', style: t.headlineMedium),
                ],
                if (step.action != null) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => context.push(step.action!),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: Text(step.actionLabel ?? 'Open'),
                  ),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: _step == 0 ? null : () => _goTo(_step - 1), child: const Text('Back'))),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: last
                    ? () async {
                        await guard(context, () => DiaryRepo.create(
                              circleId: ref.read(circleIdProvider),
                              entryType: 'memory',
                              origin: 'together',
                              title: '${g.emoji} ${g.title}',
                              body: 'We had a ${g.title.toLowerCase()} together.',
                              payload: {'date_guide': g.key},
                            ));
                        final live = ref.read(liveTogetherProvider).valueOrNull;
                        if (live != null) await TogetherRepo.end(live.id);
                        if (context.mounted) {
                          showToast(context, 'Date complete! Saved to Our Diary ❤️');
                          context.pop();
                        }
                      }
                    : () => _goTo(_step + 1),
                child: Text(last ? 'Finish date ❤️' : 'Next step'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
