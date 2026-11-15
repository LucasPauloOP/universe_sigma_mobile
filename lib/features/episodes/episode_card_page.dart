import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/segment_result.dart';
import '../../core/theme.dart';
import '../../resources/resource_def.dart';
import '../../resources/resources.dart';
import '../divisions/ranking_sheet.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui.dart';

/// Card completo de um episódio, já ordenado (`GET episodes/:id/card`).
final episodeCardProvider = FutureProvider.family<Entity, String>((ref, id) async {
  final d = await ref.watch(apiProvider).get('episodes/$id/card');
  return Map<String, dynamic>.from(d as Map);
});

class EpisodeCardPage extends ConsumerStatefulWidget {
  const EpisodeCardPage({super.key, required this.episodeId});
  final String episodeId;

  @override
  ConsumerState<EpisodeCardPage> createState() => _EpisodeCardPageState();
}

class _EpisodeCardPageState extends ConsumerState<EpisodeCardPage> {
  List<Entity>? _local; // ordem otimista durante o arrastar

  Future<void> _reload() async {
    _local = null;
    ref.invalidate(episodeCardProvider(widget.episodeId));
    ref.invalidate(itemsProvider('episodes'));
    await ref.read(episodeCardProvider(widget.episodeId).future);
  }

  Future<void> _toggleStatus(Entity e) async {
    final segments = e.list('segments').length;
    final status = e['status'] == 'DONE' ? reopenedStatus(segments) : 'DONE';
    try {
      await ref.read(apiProvider).put('episodes/${e.id}', body: {'status': status});
      await _reload();
    } on ApiException catch (err) {
      if (mounted) showError(context, err);
    }
  }

  Future<void> _toggleDone(Entity s, bool done) async {
    // Realizada exige resultado (vencedor + como terminou, ou empate): se falta, abre a luta
    if (done && _problem(s) != null) {
      await _openForm(segment: s, markDone: true);
      return;
    }
    try {
      await ref.read(apiProvider).put('segments/${s.id}', body: {'isDone': done});
      await _reload();
    } on ApiException catch (err) {
      if (mounted) showError(context, err);
    }
  }

  String? _problem(Entity s) => resultProblem(
        type: s['type'] as String?,
        isDone: true,
        isDraw: s['isDraw'] == true,
        finishType: s['finishType'] as String?,
        participants: [
          for (final p in s.list('participants'))
            ParticipantResult(side: (p['side'] as num).toInt(), isWinner: p['isWinner'] == true),
        ],
      );

  Future<void> _openForm({Entity? segment, bool markDone = false}) async {
    final base = '/episodes/${widget.episodeId}/segments';
    final saved = await context.push<bool>(
      segment == null ? '$base/new' : '$base/${segment.id}${markDone ? '?markDone=1' : ''}',
    );
    if (saved == true) await _reload();
  }

  Future<void> _remove(Entity s) async {
    final ok = await confirm(
      context,
      title: 'Excluir segmento',
      message: 'Excluir este segmento do card? Os demais sobem uma posição.',
      confirmLabel: 'Excluir',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(apiProvider).delete('segments/${s.id}');
      await _reload();
    } on ApiException catch (err) {
      if (mounted) showError(context, err);
    }
  }

  Future<void> _reorder(Entity e, int oldIndex, int newIndex) async {
    final segments = [...(_local ?? e.list('segments'))];
    if (oldIndex == newIndex) return;
    segments.insert(newIndex, segments.removeAt(oldIndex));
    setState(() => _local = segments);
    try {
      await ref.read(apiProvider).put('episodes/${e.id}/segments/order', body: {'order': [for (final s in segments) s.id]});
    } on ApiException catch (err) {
      if (mounted) showError(context, err);
    } finally {
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = ref.watch(episodeCardProvider(widget.episodeId));
    return AppPage(
      title: card.value == null ? 'Card' : ((card.value!['title'] as String?)?.isNotEmpty == true ? card.value!['title'] as String : card.value!.obj('show')?['name'] as String? ?? 'Card'),
      subtitle: card.value == null ? null : _subtitle(card.value!),
      showBack: true,
      actions: [
        if (card.value != null)
          IconButton(
            tooltip: 'Ranking das divisões',
            icon: const Icon(Icons.leaderboard),
            onPressed: () => DivisionRankingSheet.show(
              context,
              brandId: card.value!.obj('show')?['brandId'] as String?,
              scheduledIds: {
                for (final s in card.value!.list('segments'))
                  for (final p in s.list('participants')) p['wrestlerId'] as String,
              },
            ),
          ),
        if (card.value != null)
          IconButton(
            tooltip: labelOfOption(episodeStatus, card.value!['status']),
            icon: Icon(card.value!['status'] == 'DONE' ? Icons.check_circle : Icons.schedule, color: statusColor(card.value!['status'] as String?)),
            onPressed: () => _toggleStatus(card.value!),
          ),
      ],
      fab: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Segmento'),
      ),
      body: AsyncBody<Entity>(
        value: card,
        onRetry: _reload,
        builder: (e) {
          final segments = _local ?? e.list('segments');
          return RefreshIndicator(
            onRefresh: _reload,
            child: segments.isEmpty
                ? ListView(children: [
                    SizedBox(
                      height: 360,
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const EmptyState('O card ainda está vazio.', icon: Icons.list),
                        FilledButton(onPressed: () => _openForm(), child: const Text('Adicionar o primeiro segmento')),
                      ]),
                    ),
                  ])
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                    itemCount: segments.length,
                    onReorderItem: (a, b) => _reorder(e, a, b),
                    itemBuilder: (ctx, i) => _SegmentTile(
                      key: ValueKey(segments[i].id),
                      index: i,
                      s: segments[i],
                      onDone: (v) => _toggleDone(segments[i], v),
                      onEdit: () => _openForm(segment: segments[i]),
                      onDelete: () => _remove(segments[i]),
                    ),
                  ),
          );
        },
      ),
    );
  }

  String _subtitle(Entity e) => [
        e.obj('show')?['name'] as String? ?? '',
        monthName((e['month'] as num?)?.toInt()),
        if (e['week'] != null) 'Semana ${e['week']}',
        if (e['night'] != null) 'Noite ${e['night']}',
        gameDayName(EpisodeLike.fromEntity(e)),
      ].where((s) => s.isNotEmpty).join(' • ');
}

class _SegmentTile extends StatelessWidget {
  const _SegmentTile({super.key, required this.index, required this.s, required this.onDone, required this.onEdit, required this.onDelete});
  final int index;
  final Entity s;
  final ValueChanged<bool> onDone;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  bool get _isMatch => s['type'] == 'MATCH';
  bool get _done => s['isDone'] == true;
  bool get _draw => s['isDraw'] == true;

  String get _headline => _isMatch ? (s.obj('matchType')?['name'] as String? ?? 'Luta') : (s['type'] == 'PROMO' ? 'Promo' : 'Segmento');

  IconData get _icon => _isMatch ? Icons.person : (s['type'] == 'PROMO' ? Icons.campaign : Icons.more_horiz);

  /// Lados agrupados, ordenados por lado.
  List<List<Entity>> get _sides {
    final map = <int, List<Entity>>{};
    for (final p in s.list('participants')) {
      map.putIfAbsent((p['side'] as num).toInt(), () => []).add(p);
    }
    return (map.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).map((e) => e.value).toList();
  }

  /// Vencedor verde, perdedores vermelho, empate neutro (só depois da luta realizada).
  TextStyle _nameStyle(BuildContext context, Entity p) {
    final base = DefaultTextStyle.of(context).style;
    if (!_done || !_isMatch) return p['isWinner'] == true ? base.copyWith(fontWeight: FontWeight.w600) : base;
    if (_draw) return base.copyWith(fontWeight: FontWeight.w600);
    final hasWinner = s.list('participants').any((x) => x['isWinner'] == true);
    if (!hasWinner) return base;
    return p['isWinner'] == true
        ? base.copyWith(fontWeight: FontWeight.w600, color: const Color(0xFF22C55E))
        : base.copyWith(color: const Color(0xFFEF4444));
  }

  String get _stakes {
    final st = s['stakes'] as String?;
    final div = s.obj('cardDivision');
    if (st == null || st == 'NONE' || div == null) return '';
    final what = st == 'CONTENDER' ? 'Desafiante' : 'Subida de divisão';
    return '$what: ${div['name']}${_done && s['rankingApplied'] == true ? ' ✓' : ''}';
  }

  String get _tournament {
    final m = s.obj('tournamentMatch');
    final t = m?.obj('tournament');
    if (m == null || t == null) return '';
    final round = roundTitle(RoundInfo.fromTournament(t), round: (m['round'] as num).toInt(), groupName: m['groupName'] as String?);
    return '${t['name']} · $round';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final main = s['isMainEvent'] == true;
    final title = s.obj('title');
    final finish = s['finishType'] != null ? labelOfOption(finishType, s['finishType']) : '';
    final sides = _sides;
    Widget tag(String text, {IconData? icon, Color? color}) => Chip(
          label: Text(text, style: const TextStyle(fontSize: 11)),
          avatar: icon != null ? Icon(icon, size: 14) : null,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          backgroundColor: color,
        );

    return Card(
      key: key,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: main ? scheme.primary : scheme.outlineVariant, width: main ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ReorderableDragStartListener(
            index: index,
            child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle)),
          ),
          SizedBox(width: 24, child: Text('${index + 1}', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium)),
          const SizedBox(width: 6),
          Expanded(
            child: Opacity(
              opacity: _done ? 0.8 : 1,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(_icon, size: 18, color: scheme.primary),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_headline, style: const TextStyle(fontWeight: FontWeight.w700))),
                ]),
                Wrap(spacing: 4, runSpacing: 0, children: [
                  if (main) tag('MAIN EVENT', color: scheme.primaryContainer),
                  if (title != null) tag('${title['name']}${s['titleChanged'] == true ? ' · novo campeão' : ''}', icon: Icons.emoji_events),
                  if (_tournament.isNotEmpty) tag(_tournament, icon: Icons.account_tree),
                  if (_stakes.isNotEmpty) tag(_stakes, icon: Icons.checklist),
                  if (_draw) tag('Empate', icon: Icons.drag_handle),
                  if (finish.isNotEmpty) tag(finish),
                ]),
                if (sides.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text.rich(TextSpan(children: [
                      for (var i = 0; i < sides.length; i++) ...[
                        for (var j = 0; j < sides[i].length; j++) ...[
                          if (sides[i][j]['isWinner'] == true) const WidgetSpan(child: Icon(Icons.star, size: 12), alignment: PlaceholderAlignment.middle),
                          TextSpan(text: sides[i][j].obj('wrestler')?['name'] as String? ?? '…', style: _nameStyle(context, sides[i][j])),
                          if (j < sides[i].length - 1) const TextSpan(text: ' & '),
                        ],
                        if (i < sides.length - 1) TextSpan(text: '  vs  ', style: TextStyle(color: scheme.outline, fontSize: 12)),
                      ],
                    ])),
                  ),
                if ((s['notes'] as String?)?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(s['notes'] as String, style: Theme.of(context).textTheme.bodySmall),
                  ),
              ]),
            ),
          ),
          Checkbox(value: _done, onChanged: (v) => onDone(v == true)),
          PopupMenuButton<String>(
            onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Editar')),
              PopupMenuItem(value: 'delete', child: Text('Excluir')),
            ],
          ),
        ]),
      ),
    );
  }
}
