import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/api_exception.dart';
import '../../core/episodes_logic.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../resources/resource_def.dart';
import '../../resources/resources.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/net_image.dart';
import '../../shared/ui.dart';
import '../resources/field_widgets.dart';
import '../resources/generate_episodes_sheet.dart';

enum _View { cards, calendar }

class EpisodesPage extends ConsumerStatefulWidget {
  const EpisodesPage({super.key});
  @override
  ConsumerState<EpisodesPage> createState() => _EpisodesPageState();
}

class _EpisodesPageState extends ConsumerState<EpisodesPage> {
  String? _seasonId;
  String? _showId;
  bool _weekly = true;
  _View _view = _View.cards;

  /// null = automático (mês do último realizado); 0 = todos os meses.
  int? _monthSel;
  bool _showEarlier = false;

  Future<void> _refresh() async {
    ref.invalidate(itemsProvider('episodes'));
    ref.invalidate(itemsProvider('seasons'));
    await ref.read(itemsProvider('episodes').future);
  }

  Future<void> _generate() async {
    final n = await GenerateEpisodesSheet.show(context);
    if (n == null || !mounted) return;
    showInfo(context, n > 0 ? '$n episódio(s) criado(s)' : 'Nenhum episódio novo: tudo já existia');
  }

  /// Temporada exibida na tela (a escolhida ou a automática), usada pelo planejamento com IA.
  String? _visibleSeasonId;

  Future<void> _planWithAi() async {
    final season = _visibleSeasonId;
    final saved = await context.push<int>(
      Uri(path: '/episodes/ai-plan', queryParameters: {'seasonId': ?season}).toString(),
    );
    if (saved == null || saved == 0 || !mounted) return;
    showInfo(context, '$saved episódio(s) planejado(s)');
  }

  Future<void> _add() async {
    final saved = await context.push<bool>('/r/episodes/new');
    if (saved == true && mounted) showInfo(context, 'Salvo');
  }

  Future<void> _edit(Entity e) async {
    final saved = await context.push<bool>('/r/episodes/${e.id}/edit');
    if (saved == true && mounted) showInfo(context, 'Salvo');
  }

  Future<void> _remove(Entity e) async {
    final ok = await confirm(
      context,
      title: 'Excluir episódio',
      message: 'Excluir "${resources['episodes']!.label(e)}"? O card dele também será apagado.',
      confirmLabel: 'Excluir',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(apiProvider).delete('episodes/${e.id}');
      invalidateItems(ref, ['episodes']);
    } on ApiException catch (err) {
      if (mounted) showError(context, err);
    }
  }

  Future<void> _toggleStatus(Entity e) async {
    final segments = (e.obj('_count')?['segments'] as num?)?.toInt() ?? 0;
    final status = e['status'] == 'DONE' ? reopenedStatus(segments) : 'DONE';
    try {
      await ref.read(apiProvider).put('episodes/${e.id}', body: {'status': status});
      invalidateItems(ref, ['episodes']);
    } on ApiException catch (err) {
      if (mounted) showError(context, err);
    }
  }

  void _menu(Entity e) {
    final segments = (e.obj('_count')?['segments'] as num?)?.toInt() ?? 0;
    final done = e['status'] == 'DONE';
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.list),
              title: const Text('Abrir card'),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/episodes/${e.id}/card');
              },
            ),
            ListTile(
              leading: Icon(done ? Icons.schedule : Icons.check_circle_outline),
              title: Text(
                done
                    ? (segments > 0 ? 'Marcar como planejado' : 'Marcar como sem planejamento')
                    : 'Marcar como realizado',
              ),
              onTap: () {
                Navigator.pop(ctx);
                _toggleStatus(e);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Editar'),
              onTap: () {
                Navigator.pop(ctx);
                _edit(e);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
              title: Text('Excluir', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              onTap: () {
                Navigator.pop(ctx);
                _remove(e);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final episodesAsync = ref.watch(itemsProvider('episodes'));
    final seasonsAsync = ref.watch(itemsProvider('seasons'));

    return AppPage(
      title: 'Episódios',
      subtitle: 'Temporada de maio a abril',
      actions: [
        IconButton(tooltip: 'Planejar com IA', onPressed: _planWithAi, icon: const Icon(Icons.auto_awesome)),
        IconButton(tooltip: 'Gerar episódios', onPressed: _generate, icon: const Icon(Icons.bolt)),
        IconButton(tooltip: 'Novo episódio', onPressed: _add, icon: const Icon(Icons.add)),
      ],
      body: AsyncBody<List<Entity>>(
        value: episodesAsync,
        onRetry: _refresh,
        builder: (all) {
          final seasons = [...(seasonsAsync.value ?? const <Entity>[])]
            ..sort((a, b) => (a['number'] as num).compareTo(b['number'] as num));
          if (seasonsAsync.hasValue && seasons.isEmpty) {
            return const EmptyState(
              'Nenhuma temporada cadastrada.\nCrie uma em Temporadas e depois gere os episódios.',
              icon: Icons.event,
            );
          }
          final seasonId = seasons.any((s) => s.id == _seasonId) ? _seasonId : currentSeasonId(seasons, all);
          _visibleSeasonId = seasonId;
          final season = seasons.where((s) => s.id == seasonId).firstOrNull;
          final startMonth = (season?['startMonth'] as num?)?.toInt() ?? 5;
          final ofSeason = episodesOfSeason(all, seasonId);
          final playable = playableEpisodes(ofSeason, startMonth);
          final base = _showEarlier ? ofSeason : playable;
          final earlier = ofSeason.length - playable.length;
          final next = nextEpisodeId(playable);

          // shows do filtro (semanal ou PLE)
          final showChoices = <String, String>{
            for (final e in ofSeason)
              if (isWeekly(e) == _weekly) e['showId'] as String: e.obj('show')?['name'] as String? ?? '',
          };

          final groups = groupByMonth(base, weekly: _weekly, showId: _showId);
          final months = [for (final g in groups) g.month];
          final autoMonth = defaultMonth(months, lastDoneMonth(ofSeason));
          final month = _monthSel == 0 ? null : (months.contains(_monthSel) ? _monthSel : autoMonth);

          return Column(
            children: [
              _Toolbar(
                seasons: seasons,
                seasonId: seasonId,
                onSeason: (id) => setState(() {
                  _seasonId = id;
                  _showId = null;
                  _monthSel = null;
                }),
                view: _view,
                onView: (v) => setState(() => _view = v),
                weekly: _weekly,
                weeklyCount: playable.where(isWeekly).length,
                pleCount: playable.where((e) => !isWeekly(e)).length,
                onWeekly: (w) => setState(() {
                  _weekly = w;
                  _showId = null;
                }),
                showChoices: showChoices,
                showId: _showId,
                onShow: (id) => setState(() => _showId = id),
                months: months,
                month: month,
                onMonthSel: (m) => setState(() => _monthSel = m ?? 0),
              ),
              if (startMonth != 5 || earlier > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  child: Card(
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.flag),
                      title: Text(
                        'O universe começa em ${monthName(startMonth)} nesta temporada.'
                        '${earlier > 0 ? ' $earlier episódio(s) de meses anteriores ficam ${_showEarlier ? 'visíveis' : 'ocultos'}.' : ''}',
                      ),
                      trailing: earlier > 0
                          ? TextButton(
                              onPressed: () => setState(() => _showEarlier = !_showEarlier),
                              child: Text(_showEarlier ? 'Ocultar' : 'Mostrar'),
                            )
                          : null,
                    ),
                  ),
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: _view == _View.cards
                      ? _CardsView(
                          groups: month == null ? groups : groups.where((g) => g.month == month).toList(),
                          nextId: next,
                          startMonth: startMonth,
                          onOpen: (e) => context.push('/episodes/${e.id}/card'),
                          onMenu: _menu,
                        )
                      : _CalendarView(
                          episodes: base,
                          month: month,
                          onMonth: (m) => setState(() => _monthSel = m),
                          nextId: next,
                          onOpen: (e) => context.push('/episodes/${e.id}/card'),
                          onMenu: _menu,
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.seasons,
    required this.seasonId,
    required this.onSeason,
    required this.view,
    required this.onView,
    required this.weekly,
    required this.weeklyCount,
    required this.pleCount,
    required this.onWeekly,
    required this.showChoices,
    required this.showId,
    required this.onShow,
    required this.months,
    required this.month,
    required this.onMonthSel,
  });

  final List<Entity> seasons;
  final String? seasonId;
  final ValueChanged<String?> onSeason;
  final _View view;
  final ValueChanged<_View> onView;
  final bool weekly;
  final int weeklyCount;
  final int pleCount;
  final ValueChanged<bool> onWeekly;
  final Map<String, String> showChoices;
  final String? showId;
  final ValueChanged<String?> onShow;
  final List<int> months;
  final int? month;
  final ValueChanged<int?> onMonthSel;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: PickerField(
                label: 'Temporada',
                required: true,
                value: seasonId,
                choices: [for (final s in seasons) Choice(s.id, resources['seasons']!.label(s))],
                onChanged: (v) => onSeason(v as String?),
              ),
            ),
            const SizedBox(width: 12),
            SegmentedButton<_View>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: _View.cards, icon: Icon(Icons.grid_view)),
                ButtonSegment(value: _View.calendar, icon: Icon(Icons.calendar_month)),
              ],
              selected: {view},
              onSelectionChanged: (s) => onView(s.first),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: true, label: Text('Semanais ($weeklyCount)')),
            ButtonSegment(value: false, label: Text('PLEs e especiais ($pleCount)')),
          ],
          selected: {weekly},
          onSelectionChanged: (s) => onWeekly(s.first),
        ),
        if (showChoices.length > 1)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                FilterChip(label: const Text('Todos'), selected: showId == null, onSelected: (_) => onShow(null)),
                for (final e in showChoices.entries) ...[
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text(e.value),
                    selected: showId == e.key,
                    onSelected: (_) => onShow(showId == e.key ? null : e.key),
                  ),
                ],
              ],
            ),
          ),
        if (months.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                if (view == _View.cards) ...[
                  ChoiceChip(
                    label: const Text('Todos os meses'),
                    selected: month == null,
                    onSelected: (_) => onMonthSel(null),
                  ),
                  const SizedBox(width: 8),
                ],
                for (final m in months) ...[
                  ChoiceChip(label: Text(monthName(m)), selected: month == m, onSelected: (_) => onMonthSel(m)),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
      ],
    ),
  );
}

class _CardsView extends StatelessWidget {
  const _CardsView({
    required this.groups,
    required this.nextId,
    required this.startMonth,
    required this.onOpen,
    required this.onMenu,
  });

  final List<MonthGroup> groups;
  final String? nextId;
  final int startMonth;
  final ValueChanged<Entity> onOpen;
  final ValueChanged<Entity> onMenu;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return ListView(
        children: const [
          SizedBox(
            height: 320,
            child: EmptyState('Nenhum episódio aqui. Use “Gerar episódios”.', icon: Icons.calendar_month),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        for (final g in groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
            child: Row(
              children: [
                Expanded(child: Text(g.name, style: Theme.of(context).textTheme.titleLarge)),
                Text('${g.done}/${g.episodes.length} realizados', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          for (final e in g.episodes)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _EpisodeCard(
                e: e,
                isNext: e.id == nextId,
                before: beforeStart((e['month'] as num).toInt(), startMonth),
                onTap: () => onOpen(e),
                onMenu: () => onMenu(e),
              ),
            ),
        ],
      ],
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({
    required this.e,
    required this.isNext,
    required this.before,
    required this.onTap,
    required this.onMenu,
  });
  final Entity e;
  final bool isNext;
  final bool before;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final status = e['status'] as String?;
    final color = statusColor(status);
    final title = e['title'] as String?;
    final show = e.obj('show')?['name'] as String? ?? 'Episódio';
    final segments = (e.obj('_count')?['segments'] as num?)?.toInt() ?? 0;
    final scheme = Theme.of(context).colorScheme;
    final onColor = ThemeData.estimateBrightnessForColor(color) == Brightness.dark ? Colors.white : Colors.black87;
    return Opacity(
      opacity: before ? 0.6 : 1,
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: isNext ? 4 : 0,
        shadowColor: scheme.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color, width: 2.5),
        ),
        child: InkWell(
          onTap: onTap,
          onLongPress: onMenu,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // faixa lateral com o ícone do status
                Container(
                  width: 36,
                  color: color,
                  child: Icon(statusIcon(status), size: 20, color: onColor),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                    child: Row(
                      children: [
                        NetImage(
                          e['imageUrl'] as String? ?? e.obj('show')?['imageUrl'] as String?,
                          size: 44,
                          fallback: Icons.tv,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                show,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${episodeWhen(e)} · ${gameDayName(EpisodeLike.fromEntity(e))}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (title != null && title.isNotEmpty && title != show)
                                Text(title, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(statusIcon(status), size: 14, color: onColor),
                                        const SizedBox(width: 4),
                                        Text(
                                          labelOfOption(episodeStatus, status),
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: onColor),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isNext)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: scheme.primary),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.play_arrow, size: 14, color: scheme.primary),
                                          Text('Próximo', style: TextStyle(fontSize: 12, color: scheme.primary)),
                                        ],
                                      ),
                                    ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.list, size: 16),
                                      const SizedBox(width: 2),
                                      Text('$segments'),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(icon: const Icon(Icons.more_vert), onPressed: onMenu, tooltip: 'Ações'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarView extends StatelessWidget {
  const _CalendarView({
    required this.episodes,
    required this.month,
    required this.onMonth,
    required this.nextId,
    required this.onOpen,
    required this.onMenu,
  });

  final List<Entity> episodes;
  final int? month;
  final ValueChanged<int> onMonth;
  final String? nextId;
  final ValueChanged<Entity> onOpen;
  final ValueChanged<Entity> onMenu;

  @override
  Widget build(BuildContext context) {
    final months = calendarMonths(episodes);
    if (months.isEmpty) {
      return ListView(
        children: const [SizedBox(height: 320, child: EmptyState('Sem episódios.', icon: Icons.calendar_month))],
      );
    }
    final current = months.contains(month) ? month! : months.first;
    final i = months.indexOf(current);
    final rows = calendarRows(episodes, current);
    const dayWidth = 118.0;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            IconButton(onPressed: i > 0 ? () => onMonth(months[i - 1]) : null, icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Text(
                monthName(current),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              onPressed: i < months.length - 1 ? () => onMonth(months[i + 1]) : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            children: [
              Row(
                children: [
                  const SizedBox(width: 56),
                  for (final d in gameWeekdays)
                    SizedBox(
                      width: dayWidth,
                      child: Center(child: Text(d.substring(0, 3), style: Theme.of(context).textTheme.labelMedium)),
                    ),
                ],
              ),
              for (var w = 0; w < 4; w++)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 56,
                      height: 84,
                      child: Center(child: Text('Sem. ${w + 1}', style: Theme.of(context).textTheme.labelSmall)),
                    ),
                    for (var d = 0; d < 7; d++)
                      Container(
                        width: dayWidth,
                        constraints: const BoxConstraints(minHeight: 84),
                        margin: const EdgeInsets.all(1),
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerLow,
                          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 0.5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final e in rows[w][d])
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: _CalChip(
                                  e: e,
                                  isNext: e.id == nextId,
                                  onTap: () => onOpen(e),
                                  onLongPress: () => onMenu(e),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CalChip extends StatelessWidget {
  const _CalChip({required this.e, required this.isNext, required this.onTap, required this.onLongPress});
  final Entity e;
  final bool isNext;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(e['status'] as String?);
    final done = e['status'] == 'DONE';
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: Border(left: BorderSide(color: color, width: 3)),
          borderRadius: BorderRadius.circular(4),
          boxShadow: isNext
              ? [BoxShadow(color: Theme.of(context).colorScheme.primary, blurRadius: 0, spreadRadius: 1.5)]
              : null,
        ),
        child: Row(
          children: [
            if (done)
              const Padding(padding: EdgeInsets.only(right: 3), child: Icon(Icons.check, size: 11))
            else if (isNext)
              const Padding(padding: EdgeInsets.only(right: 3), child: Icon(Icons.play_arrow, size: 11)),
            Expanded(
              child: Text(calendarChip(e), style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}
