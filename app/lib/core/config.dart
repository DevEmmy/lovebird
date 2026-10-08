/// Build-time configuration. Pass with --dart-define, e.g.
/// flutter run --dart-define=SUPABASE_URL=https://xyz.supabase.co --dart-define=SUPABASE_ANON_KEY=...
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Deep link used in auth emails (confirm / reset password).
  static const authRedirect = String.fromEnvironment(
    'AUTH_REDIRECT',
    defaultValue: 'io.lovebird.app://login-callback',
  );

  /// Public web origin used in invitation share text.
  static const webOrigin = String.fromEnvironment('WEB_ORIGIN', defaultValue: 'https://lovebird.app');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
