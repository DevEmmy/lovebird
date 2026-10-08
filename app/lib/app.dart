import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
import 'core/theme/theme.dart';

class LovebirdApp extends ConsumerWidget {
  const LovebirdApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Lovebird',
      debugShowCheckedModeBanner: false,
      theme: LBTheme.light(),
      darkTheme: LBTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
      builder: (context, child) {
        // Respect user text scaling but keep layouts sane.
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.6)),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
