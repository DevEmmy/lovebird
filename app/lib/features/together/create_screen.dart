import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/widgets.dart';

/// Create Together: prompts that end in something you keep (saved to Our Diary).
class CreateScreen extends StatelessWidget {
  const CreateScreen({super.key});

  static const prompts = [
    ('💌', 'Love letter swap', 'Each write a short letter. Save it to the diary together and read them aloud.', 'letter'),
    ('📝', 'Six-word story of us', 'Describe your relationship in exactly six words. Then compare.', 'six_words'),
    ('🎨', 'Draw each other', 'Two minutes, no looking at the paper. Snap a photo and add it as a memory.', 'draw'),
    ('🎵', 'Our playlist', 'Each add five songs that remind you of the other. Start a "Songs" plan list.', 'playlist'),
    ('🔮', 'Letter to us in a year', 'Write together to your future selves. Lovebird keeps it in Our Diary.', 'future'),
    ('📖', 'Write a story together', 'Take turns writing one sentence each in Our Diary. Start with "Once upon a time, two lovebirds…"', 'story'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Create together ✍️')),
      body: Constrained(
        maxWidth: 720,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          for (final p in prompts)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: LBCard(
                onTap: () {
                  if (p.$4 == 'draw') {
                    context.push('/memory/new');
                  } else if (p.$4 == 'playlist') {
                    context.push('/plans');
                  } else {
                    context.push('/diary/new?together=1&prompt=${p.$4}');
                  }
                },
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.$1, style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.$2, style: t.titleMedium),
                      const SizedBox(height: 4),
                      Text(p.$3, style: t.bodyMedium),
                    ]),
                  ),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}
