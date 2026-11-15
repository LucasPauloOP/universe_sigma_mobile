import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'core/providers.dart';
import 'features/auth/auth_pages.dart';
import 'features/divisions/divisions_page.dart';
import 'features/episodes/episode_card_page.dart';
import 'features/episodes/episodes_page.dart';
import 'features/episodes/segment_form_page.dart';
import 'features/home/dashboard_page.dart';
import 'features/import/import_page.dart';
import 'features/resources/resource_form_page.dart';
import 'features/resources/resource_list_page.dart';
import 'features/stats/reign_stats_page.dart';
import 'features/tournaments/tournament_page.dart';
import 'features/universes/universes_page.dart';
import 'resources/resources.dart';

/// Faz o GoRouter reavaliar os redirects quando a sessão ou o universe mudam.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(authProvider, (_, _) => notifyListeners());
    ref.listen(selectedUniverseProvider, (_, _) => notifyListeners());
    ref.listen(universesProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  const guestPaths = {'/login', '/register', '/forgot'};

  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final path = state.uri.path;
      if (auth.status == AuthStatus.loading) return path == '/splash' ? null : '/splash';
      final loggedIn = auth.status == AuthStatus.loggedIn;
      if (!loggedIn) return guestPaths.contains(path) ? null : '/login'; // authGuard
      if (guestPaths.contains(path) || path == '/splash') return '/dashboard'; // guestGuard

      // universeGuard: precisa de um universe selecionado
      final universes = ref.read(universesProvider);
      final selected = ref.read(selectedUniverseProvider);
      if (path != '/universes' && universes.hasValue && selected == null) return '/universes';

      // resourceGuard: o :resource precisa existir
      if (state.pathParameters['resource'] != null && !resources.containsKey(state.pathParameters['resource'])) {
        return '/dashboard';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const Scaffold(body: Center(child: CircularProgressIndicator()))),
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterPage()),
      GoRoute(path: '/forgot', builder: (_, _) => const ForgotPage()),
      GoRoute(path: '/', redirect: (_, _) => '/dashboard'),
      GoRoute(path: '/dashboard', builder: (_, _) => const DashboardPage()),
      GoRoute(
        path: '/episodes',
        builder: (_, _) => const EpisodesPage(),
        routes: [
          GoRoute(path: ':id/card', builder: (_, s) => EpisodeCardPage(episodeId: s.pathParameters['id']!)),
          GoRoute(
            path: ':id/segments/new',
            builder: (_, s) => SegmentFormPage(episodeId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: ':id/segments/:sid',
            builder: (_, s) => SegmentFormPage(
              episodeId: s.pathParameters['id']!,
              segmentId: s.pathParameters['sid'],
              markDone: s.uri.queryParameters['markDone'] == '1',
            ),
          ),
        ],
      ),
      GoRoute(path: '/import', builder: (_, _) => const ImportPage()),
      GoRoute(path: '/divisions', builder: (_, _) => const DivisionsPage()),
      GoRoute(path: '/stats/reigns', builder: (_, _) => const ReignStatsPage()),
      GoRoute(path: '/tournaments/:id', builder: (_, s) => TournamentPage(tournamentId: s.pathParameters['id']!)),
      GoRoute(path: '/universes', builder: (_, _) => const UniversesPage()),
      GoRoute(
        path: '/r/:resource',
        builder: (_, s) => ResourceListPage(resourceKey: s.pathParameters['resource']!),
        routes: [
          GoRoute(
            path: 'new',
            builder: (_, s) => ResourceFormPage(resourceKey: s.pathParameters['resource']!),
          ),
          GoRoute(
            path: ':id/edit',
            builder: (_, s) => ResourceFormPage(
              resourceKey: s.pathParameters['resource']!,
              id: s.pathParameters['id'],
            ),
          ),
        ],
      ),
    ],
  );
});
