import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config.dart';
import 'core/theme/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();

  if (!AppConfig.isConfigured) {
    runApp(const _MissingConfigApp());
    return;
  }

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
  );

  runApp(const ProviderScope(child: LovebirdApp()));
}

class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: LBTheme.light(),
      home: const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Lovebird needs SUPABASE_URL and SUPABASE_ANON_KEY.\n\n'
              'Run with --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
