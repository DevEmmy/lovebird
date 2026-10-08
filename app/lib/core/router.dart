import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/admin/admin_screen.dart';
import '../features/auth/auth_screens.dart';
import '../features/chat/chat_screen.dart';
import '../features/competition/competition_screens.dart';
import '../features/dates/date_ideas_screen.dart';
import '../features/dates/date_night_screens.dart';
import '../features/diary/diary_screens.dart';
import '../features/games/game_session_screen.dart';
import '../features/games/games_screen.dart';
import '../features/home/home_screen.dart';
import '../features/landing/landing_screen.dart';
import '../features/library/book_screen.dart';
import '../features/library/library_screen.dart';
import '../features/library/reader_screen.dart';
import '../features/memories/memories_screens.dart';
import '../features/more/more_screen.dart';
import '../features/more/notifications_screen.dart';
import '../features/more/profile_screen.dart';
import '../features/more/relationship_screens.dart';
import '../features/more/report_screen.dart';
import '../features/more/settings_screens.dart';
import '../features/movie/movie_lobby_screen.dart';
import '../features/movie/movie_room_screen.dart';
import '../features/onboarding/circle_setup_screen.dart';
import '../features/plans/plans_screens.dart';
import '../features/recap/recap_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/shell/splash_screen.dart';
import '../features/special_dates/special_dates_screen.dart';
import '../features/together/create_screen.dart';
import '../features/together/talk_screen.dart';
import '../features/together/together_screen.dart';
import '../state/session.dart';
import 'supabase.dart';

const _publicRoutes = {'/welcome', '/sign-in', '/sign-up', '/reset'};

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authStateProvider, (_, __) => refresh.value++);
  ref.listen(membershipProvider, (_, __) => refresh.value++);
  ref.listen(circleProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final signedIn = sb.auth.currentUser != null;
      if (!signedIn) return _publicRoutes.contains(loc) ? null : '/welcome';
      if (loc == '/new-password') return null;

      final membership = ref.read(membershipProvider);
      if (!membership.hasValue) return loc == '/splash' ? null : '/splash';
      final cid = membership.valueOrNull;
      if (cid == null) return (loc == '/setup' || loc == '/profile') ? null : '/setup';

      final circle = ref.read(circleProvider);
      if (!circle.hasValue) return loc == '/splash' ? null : '/splash';
      final c = circle.valueOrNull;
      if (c == null || !c.isActive) return (loc == '/setup' || loc == '/profile') ? null : '/setup';

      if (_publicRoutes.contains(loc) || loc == '/setup' || loc == '/splash') return '/home';
      return null;
    },
    errorBuilder: (context, state) => const NotFoundScreen(),
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/welcome', builder: (_, __) => const LandingScreen()),
      GoRoute(path: '/sign-in', builder: (_, __) => const SignInScreen()),
      GoRoute(path: '/sign-up', builder: (_, __) => const SignUpScreen()),
      GoRoute(path: '/reset', builder: (_, __) => const ResetPasswordScreen()),
      GoRoute(path: '/new-password', builder: (_, __) => const NewPasswordScreen()),
      GoRoute(path: '/setup', builder: (_, __) => const CircleSetupScreen()),

      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, __) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/chat', builder: (_, __) => const ChatScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/together', builder: (_, __) => const TogetherScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/memories', builder: (_, __) => const MemoriesScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/more', builder: (_, __) => const MoreScreen())]),
        ],
      ),

      // Together
      GoRoute(path: '/games', builder: (_, __) => const GamesScreen()),
      GoRoute(path: '/game/:id', builder: (_, s) => GameSessionScreen(sessionId: s.pathParameters['id']!)),
      GoRoute(path: '/movie', builder: (_, __) => const MovieLobbyScreen()),
      GoRoute(path: '/movie/:id', builder: (_, s) => MovieRoomScreen(sessionId: s.pathParameters['id']!)),
      GoRoute(path: '/date-night', builder: (_, __) => const DateNightScreen()),
      GoRoute(path: '/date-night/:key', builder: (_, s) => DateNightGuideScreen(guideKey: s.pathParameters['key']!)),
      GoRoute(path: '/date-ideas', builder: (_, __) => const DateIdeasScreen()),
      GoRoute(path: '/talk', builder: (_, __) => const TalkScreen()),
      GoRoute(path: '/create', builder: (_, __) => const CreateScreen()),
      GoRoute(path: '/library', builder: (_, __) => const LibraryScreen()),
      GoRoute(path: '/book/:id', builder: (_, s) => BookScreen(bookId: s.pathParameters['id']!)),
      GoRoute(
        path: '/read/:circleBookId',
        builder: (_, s) => ReaderScreen(
          circleBookId: s.pathParameters['circleBookId']!,
          initialChapter: int.tryParse(s.uri.queryParameters['chapter'] ?? ''),
        ),
      ),

      // Memories
      GoRoute(path: '/memory/new', builder: (_, __) => const MemoryEditorScreen()),
      GoRoute(path: '/memory/:id', builder: (_, s) => MemoryDetailScreen(memoryId: s.pathParameters['id']!)),
      GoRoute(path: '/memory/:id/edit', builder: (_, s) => MemoryEditorScreen(memoryId: s.pathParameters['id'])),
      GoRoute(
        path: '/diary/new',
        builder: (_, s) => DiaryEditorScreen(together: s.uri.queryParameters['together'] == '1', prompt: s.uri.queryParameters['prompt']),
      ),
      GoRoute(path: '/diary/:id', builder: (_, s) => DiaryEntryScreen(entryId: s.pathParameters['id']!)),
      GoRoute(path: '/diary/:id/edit', builder: (_, s) => DiaryEditorScreen(entryId: s.pathParameters['id'])),
      GoRoute(path: '/plans', builder: (_, __) => const PlansScreen()),
      GoRoute(path: '/plans/:id', builder: (_, s) => PlanDetailScreen(planId: s.pathParameters['id']!)),
      GoRoute(path: '/special-dates', builder: (_, __) => const SpecialDatesScreen()),
      GoRoute(path: '/recap', builder: (_, s) => RecapScreen(year: int.tryParse(s.uri.queryParameters['year'] ?? ''))),

      // More
      GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
      GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
      GoRoute(path: '/settings/notifications', builder: (_, __) => const NotificationSettingsScreen()),
      GoRoute(path: '/settings/privacy', builder: (_, __) => const PrivacyScreen()),
      GoRoute(path: '/relationship', builder: (_, __) => const RelationshipScreen()),
      GoRoute(path: '/relationship/end', builder: (_, __) => const EndRelationshipScreen()),
      GoRoute(path: '/report', builder: (_, s) => ReportScreen(snapshot: s.extra as Map<String, dynamic>?)),
      GoRoute(path: '/competition', builder: (_, __) => const CompetitionScreen()),
      GoRoute(path: '/competition/enter', builder: (_, __) => const CompetitionEntryScreen()),
      GoRoute(path: '/competition/finalists', builder: (_, __) => const FinalistsScreen()),
      GoRoute(path: '/competition/judge', builder: (_, __) => const JudgeScreen()),
      GoRoute(path: '/admin', builder: (_, __) => const AdminScreen()),
    ],
  );

  ref.listen(authStateProvider, (_, next) {
    if (next.valueOrNull?.event == AuthChangeEvent.passwordRecovery) router.go('/new-password');
  });
  ref.onDispose(router.dispose);
  return router;
});

class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('🕊️', style: TextStyle(fontSize: 44)),
            const SizedBox(height: 12),
            Text('This page flew away.', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => context.go('/home'), child: const Text('Go home')),
          ]),
        ),
      );
}
