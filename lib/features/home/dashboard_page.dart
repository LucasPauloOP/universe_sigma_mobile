import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/dashboard_logic.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../resources/resources.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/icons.dart';
import '../../shared/ui.dart';

const _statKeys = ['wrestlers', 'teams', 'titles', 'shows', 'episodes', 'tournaments', 'rivalries'];

class DashboardData {
  DashboardData(this.totals, this.champions, this.upcoming, this.seasons);
  final Map<String, int> totals;
  final List<CurrentChampion> champions;
  final List<Entity> upcoming;
  final List<Entity> seasons;
}

final dashboardProvider = FutureProvider<DashboardData>((ref) async {
  ref.watch(selectedUniverseProvider);
  final api = ref.watch(apiProvider);
  final results = await Future.wait([
    Future.wait(_statKeys.map(api.count)),
    api.all('title-reigns'),
    api.all('episodes', query: {'status': 'PLANNED'}),
    api.all('seasons'),
  ]);
  final totals = results[0] as List<int>;
  final seasons = results[3] as List<Entity>;
  return DashboardData(
    {for (var i = 0; i < _statKeys.length; i++) _statKeys[i]: totals[i]},
    currentChampions(results[1] as List<Entity>),
    upcomingEpisodes(results[2] as List<Entity>, seasons),
    seasons,
  );
});

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dashboardProvider);
    final universe = ref.watch(universesProvider).value?.where((u) => u.id == ref.watch(selectedUniverseProvider)).firstOrNull;
    return AppPage(
      title: universe?['name'] as String? ?? 'Painel',
      subtitle: universe?['description'] as String?,
      body: AsyncBody<DashboardData>(
        value: data,
        onRetry: () => ref.invalidate(dashboardProvider),
        builder: (d) => RefreshIndicator(
          onRefresh: () => ref.refresh(dashboardProvider.future),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _NextEpisode(d),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 2.2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                children: [
                  for (final k in _statKeys)
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => context.go('/r/$k'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(children: [
                            Icon(iconFor(k), color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${d.totals[k]}', style: Theme.of(context).textTheme.headlineSmall),
                                Text(resources[k]!.plural, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                              ]),
                            ),
                          ]),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Text('Campeões atuais', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (d.champions.isEmpty)
                const Text('Nenhum reinado em aberto. Cadastre em Reinados.')
              else
                for (final c in d.champions)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.emoji_events),
                      title: Text(c.holders, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${c.title} · desde ${c.since}'),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NextEpisode extends StatelessWidget {
  const _NextEpisode(this.d);
  final DashboardData d;

  @override
  Widget build(BuildContext context) {
    if (d.upcoming.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            const Expanded(child: Text('Nenhum episódio planejado. Gere o calendário em Episódios.')),
            TextButton(onPressed: () => context.go('/episodes'), child: const Text('Abrir')),
          ]),
        ),
      );
    }
    final next = d.upcoming.first;
    final seasonOf = {for (final s in d.seasons) s.id: s};
    final season = seasonOf[next['seasonId']];
    final color = parseBrandColor(next.obj('show')?.obj('brand')?['color'] as String?) ?? Theme.of(context).colorScheme.primary;
    final show = next.obj('show')?['name'] as String? ?? 'Episódio';
    final title = next['title'] as String?;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: color, width: 2)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Próximo episódio a jogar', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(show, style: Theme.of(context).textTheme.titleLarge),
          Text('${whenLabel(next)} · ${season != null ? resources['seasons']!.label(season) : ''}${title != null && title.isNotEmpty && title != show ? ' · $title' : ''}'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => context.push('/episodes/${next.id}/card'),
            icon: const Icon(Icons.list),
            label: const Text('Abrir card'),
          ),
          if (d.upcoming.length > 1) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('Em seguida:', style: Theme.of(context).textTheme.bodySmall),
              for (final u in d.upcoming.skip(1))
                ActionChip(
                  label: Text('${u.obj('show')?['name']} · ${whenLabel(u)}'),
                  onPressed: () => context.push('/episodes/${u.id}/card'),
                ),
            ]),
          ],
        ]),
      ),
    );
  }
}

Color? parseBrandColor(String? hex) {
  if (hex == null) return null;
  final h = hex.replaceFirst('#', '');
  final v = int.tryParse(h, radix: 16);
  if (v == null || (h.length != 6 && h.length != 8)) return null;
  return Color(h.length == 6 ? 0xFF000000 | v : v);
}
