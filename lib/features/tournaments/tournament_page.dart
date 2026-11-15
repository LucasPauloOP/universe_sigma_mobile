import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/tournament_logic.dart';
import '../../resources/resource_def.dart';
import '../../resources/resources.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui.dart';
import '../resources/field_widgets.dart';

class Bracket {
  Bracket(this.tournament, this.entrants, this.matches);
  final Entity tournament;
  final List<Entity> entrants;
  final List<Entity> matches;
}

/// Chave completa (`GET tournaments/:id/bracket`).
final bracketProvider = FutureProvider.family<Bracket, String>((ref, id) async {
  final d = await ref.watch(apiProvider).get('tournaments/$id/bracket') as Map;
  Entity e(Object? o) => Map<String, dynamic>.from(o as Map);
  List<Entity> l(Object? o) => (o as List).map(e).toList();
  return Bracket(e(d['tournament']), l(d['entrants']), l(d['matches']));
});

class TournamentPage extends ConsumerStatefulWidget {
  const TournamentPage({super.key, required this.tournamentId});
  final String tournamentId;

  @override
  ConsumerState<TournamentPage> createState() => _TournamentPageState();
}

class _TournamentPageState extends ConsumerState<TournamentPage> {
  String? _newEntrant;
  final _seed = TextEditingController();
  int _newStartRound = 1;

  String get id => widget.tournamentId;

  @override
  void dispose() {
    _seed.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    ref.invalidate(bracketProvider(id));
    ref.invalidate(itemsProvider('tournaments'));
    await ref.read(bracketProvider(id).future);
  }

  Future<void> _run(Future<void> Function() action, {String? ok}) async {
    try {
      await action();
      if (ok != null && mounted) showInfo(context, ok);
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    }
    await _reload();
  }

  Future<void> _addEntrant(Bracket b) async {
    final picked = _newEntrant;
    if (picked == null) return;
    final seed = int.tryParse(_seed.text.trim());
    await _run(() async {
      await ref.read(apiProvider).post('tournament-entrants', body: {
        'tournamentId': b.tournament.id,
        b.tournament['isTag'] == true ? 'teamId' : 'wrestlerId': picked,
        if (seed != null && seed > 0) 'seed': seed,
        'startRound': _newStartRound,
      });
    });
    setState(() {
      _newEntrant = null;
      _newStartRound = 1;
      _seed.clear();
    });
  }

  Future<void> _removeEntrant(Entity e) =>
      _run(() => ref.read(apiProvider).delete('tournament-entrants/${e.id}'));

  Future<void> _generate(Bracket b) async {
    if (b.matches.isNotEmpty) {
      final ok = await confirm(
        context,
        title: 'Gerar chave novamente',
        message: 'A chave atual (com resultados) será apagada e gerada do zero.',
        confirmLabel: 'Gerar',
        danger: true,
      );
      if (!ok) return;
    }
    await _run(() async {
      await ref.read(apiProvider).post('tournaments/${b.tournament.id}/generate-bracket');
    }, ok: 'Chave gerada');
  }

  Future<void> _setStatus(Bracket b, String status) =>
      _run(() => ref.read(apiProvider).put('tournaments/${b.tournament.id}', body: {'status': status}));

  Future<void> _unlink(Entity m) async {
    final ok = await confirm(
      context,
      title: 'Desvincular do episódio',
      message: 'A luta da chave deixa de apontar para o episódio. O segmento continua no card e pode ser apagado lá.',
      confirmLabel: 'Desvincular',
    );
    if (!ok) return;
    await _run(() => ref.read(apiProvider).post('tournament-matches/${m.id}/unlink'));
  }

  Future<void> _scheduleMatch(Bracket b, Entity m) async {
    final res = await _ScheduleSheet.show(
      context,
      summary: '${_matchTitle(b, m)} · ${versus(m)}',
      askMatchType: true,
      matchTypeId: m['matchTypeId'] as String?,
    );
    if (res == null) return;
    await _run(() async {
      await ref.read(apiProvider).post('tournament-matches/${m.id}/schedule', body: {
        'episodeId': res.episodeId,
        if (res.matchTypeId != null) 'matchTypeId': res.matchTypeId,
      });
    }, ok: 'Luta agendada no episódio');
  }

  Future<void> _scheduleRound(Round r) async {
    final res = await _ScheduleSheet.show(
      context,
      summary: '${r.title}: ${r.unscheduled} luta(s) ainda sem episódio entram no episódio escolhido.',
      askMatchType: false,
    );
    if (res == null) return;
    await _run(() async {
      final out = await ref.read(apiProvider).post('tournaments/$id/schedule-round', body: {'round': r.round, 'episodeId': res.episodeId}) as Map;
      if (mounted) showInfo(context, '${out['scheduled']} luta(s) agendada(s)');
    });
  }

  Future<void> _editMatch(Bracket b, Entity m) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MatchSheet(match: m, entrants: b.entrants),
    );
    if (saved == true) await _reload();
  }

  String _matchTitle(Bracket b, Entity m) {
    final t = b.tournament;
    return roundTitle(RoundInfo.fromTournament(t), round: (m['round'] as num).toInt(), groupName: m['groupName'] as String?) +
        (t['format'] == 'ROUND_ROBIN' ? '' : ' · Luta ${m['slot']}');
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(bracketProvider(id));
    final b = async.value;
    return AppPage(
      title: b?.tournament['name'] as String? ?? 'Torneio',
      subtitle: b == null
          ? null
          : '${labelOfOption(tournamentFormat, b.tournament['format'])} · ${b.tournament['size']} vagas · ${b.tournament['isTag'] == true ? 'duplas' : 'individual'} · ${labelOfOption(tournamentStatus, b.tournament['status'])}',
      showBack: true,
      actions: [
        if (b != null && b.tournament['status'] == 'PLANNED')
          IconButton(tooltip: 'Iniciar', icon: const Icon(Icons.play_arrow), onPressed: () => _setStatus(b, 'ONGOING')),
        if (b != null && b.tournament['status'] == 'ONGOING')
          IconButton(tooltip: 'Finalizar', icon: const Icon(Icons.flag), onPressed: () => _setStatus(b, 'FINISHED')),
        if (b != null)
          IconButton(
            tooltip: b.matches.isNotEmpty ? 'Regerar chave' : 'Gerar chave',
            icon: const Icon(Icons.account_tree),
            onPressed: () => _generate(b),
          ),
      ],
      body: AsyncBody<Bracket>(
        value: async,
        onRetry: _reload,
        builder: (b) => RefreshIndicator(
          onRefresh: _reload,
          child: ListView(padding: const EdgeInsets.all(12), children: [
            ..._champion(b),
            _participants(b),
            const SizedBox(height: 12),
            _bracket(b),
            const SizedBox(height: 48),
          ]),
        ),
      ),
    );
  }

  List<Widget> _champion(Bracket b) {
    if (b.tournament['format'] == 'ROUND_ROBIN') return const [];
    final champ = championOf(roundsOf(b.matches));
    if (champ == null) return const [];
    final scheme = Theme.of(context).colorScheme;
    return [
      Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(Icons.emoji_events, color: scheme.onPrimary),
          const SizedBox(width: 12),
          Expanded(child: Text('Campeão: ${entrantName(champ)}', style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.bold))),
        ]),
      ),
    ];
  }

  Widget _participants(Bracket b) {
    final isTag = b.tournament['isTag'] == true;
    final used = b.entrants.map((e) => (e['wrestlerId'] ?? e['teamId']) as String?).toSet();
    final all = ref.watch(itemsProvider(isTag ? 'teams' : 'wrestlers')).value ?? const <Entity>[];
    final options = [
      for (final x in all)
        if (!used.contains(x.id)) Choice(x.id, x['name'] as String? ?? ''),
    ]..sort((p, q) => p.label.toLowerCase().compareTo(q.label.toLowerCase()));
    final startOptions = startRoundOptions(b.tournament);
    final isRR = b.tournament['format'] == 'ROUND_ROBIN';

    return Card(
      child: ExpansionTile(
        initiallyExpanded: b.matches.isEmpty,
        title: Text('Participantes (${b.entrants.length}/${b.tournament['size']})', style: Theme.of(context).textTheme.titleMedium),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: b.entrants.isEmpty
                ? const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('Ninguém inscrito ainda.'))
                : Wrap(spacing: 6, runSpacing: 4, children: [
                    for (final e in b.entrants)
                      InputChip(
                        label: Text([
                          if (e['seed'] != null) '#${e['seed']}',
                          entrantName(e),
                          if (startsAt(b.tournament, e).isNotEmpty) '· entra: ${startsAt(b.tournament, e)}',
                        ].join(' ')),
                        onDeleted: () => _removeEntrant(e),
                      ),
                  ]),
          ),
          const SizedBox(height: 8),
          PickerField(
            label: isTag ? 'Adicionar dupla' : 'Adicionar lutador',
            value: _newEntrant,
            choices: options,
            onChanged: (v) => setState(() => _newEntrant = v as String?),
          ),
          const SizedBox(height: 12),
          Row(children: [
            SizedBox(
              width: 100,
              child: TextField(
                controller: _seed,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Seed'),
              ),
            ),
            if (startOptions.length > 1 && !isRR) ...[
              const SizedBox(width: 12),
              Expanded(
                child: PickerField(
                  label: 'Começa em',
                  required: true,
                  value: _newStartRound,
                  choices: [for (final o in startOptions) Choice(o.$1, o.$2)],
                  onChanged: (v) => setState(() => _newStartRound = v as int),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: _newEntrant == null ? null : () => _addEntrant(b),
              icon: const Icon(Icons.add),
              label: const Text('Inscrever'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Depois de inscrever todos, use “Gerar chave” para organizar as lutas pelos seeds. Com “Competidores por luta” no torneio, a 1ª rodada já sai com triple threat, fatal 4-way etc. Quem “Começa em” rodada posterior entra direto nela, sem passar pelas anteriores.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _bracket(Bracket b) {
    if (b.matches.isEmpty) {
      return const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('A chave ainda não foi gerada.')));
    }
    if (b.tournament['format'] == 'ROUND_ROBIN') return _roundRobin(b);
    final rounds = roundsOf(b.matches);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Chave', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final r in rounds)
                SizedBox(
                  width: 280,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Expanded(child: Text(r.title, style: Theme.of(context).textTheme.labelLarge)),
                        if (r.unscheduled > 0)
                          TextButton.icon(
                            onPressed: () => _scheduleRound(r),
                            icon: const Icon(Icons.event_available, size: 16),
                            label: const Text('Agendar rodada'),
                          ),
                      ]),
                      for (final m in r.matches) _matchTile(b, m),
                    ]),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _roundRobin(Bracket b) {
    final groups = groupsOf(b.matches);
    final standings = standingsOf(b.entrants, b.matches);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final g in groups.entries) ...[
        Padding(padding: const EdgeInsets.fromLTRB(4, 8, 4, 4), child: Text(g.key, style: Theme.of(context).textTheme.titleSmall)),
        for (final m in g.value) _matchTile(b, m, inline: true),
      ],
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Classificação', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Table(columnWidths: const {1: FixedColumnWidth(40), 2: FixedColumnWidth(40)}, children: [
              const TableRow(children: [Text('Participante', style: TextStyle(fontWeight: FontWeight.bold)), Text('J', style: TextStyle(fontWeight: FontWeight.bold)), Text('V', style: TextStyle(fontWeight: FontWeight.bold))]),
              for (final s in standings)
                TableRow(children: [
                  Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(s.name)),
                  Text('${s.played}'),
                  Text('${s.wins}'),
                ]),
            ]),
          ]),
        ),
      ),
    ]);
  }

  Widget _matchTile(Bracket b, Entity m, {bool inline = false}) {
    final scheme = Theme.of(context).colorScheme;
    final winnerId = m['winnerId'] as String?;
    final comps = competitorsOf(m);
    final seg = m.obj('segment');
    final episode = seg?.obj('episode');
    Widget nameRow(Entity? e) {
      final win = e != null && winnerId == e.id;
      return Row(children: [
        if (win) Icon(Icons.star, size: 14, color: scheme.primary),
        if (win) const SizedBox(width: 4),
        Expanded(
          child: Text(
            e == null ? 'A definir' : entrantName(e),
            style: TextStyle(fontWeight: win ? FontWeight.bold : FontWeight.normal, color: e == null ? scheme.outline : null),
          ),
        ),
      ]);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        color: scheme.surfaceContainerHighest,
        child: Column(children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _editMatch(b, m),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (inline || m['matchType'] != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      [if (inline) 'Luta ${m['slot']}', if (m['matchType'] != null) m.obj('matchType')!['name']].join(' · '),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                nameRow(m.obj('entrantA')),
                nameRow(m.obj('entrantB')),
                for (final x in comps.skip(2)) nameRow(x),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 4, 6),
            child: Row(children: [
              if (seg != null) ...[
                Icon(seg['isDone'] == true ? Icons.check_circle : Icons.event, size: 16, color: scheme.primary),
                const SizedBox(width: 4),
                Expanded(
                  child: InkWell(
                    onTap: () => context.push('/episodes/${seg['episodeId']}/card'),
                    child: Text(
                      episode != null ? episodeText(episode) : 'Episódio',
                      style: TextStyle(color: scheme.primary, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Desvincular do episódio',
                  icon: const Icon(Icons.link_off, size: 18),
                  onPressed: () => _unlink(m),
                ),
              ] else ...[
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _scheduleMatch(b, m),
                  icon: const Icon(Icons.event_available, size: 16),
                  label: const Text('Agendar'),
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

// ───────────────────────────── editar luta ─────────────────────────────

class _MatchSheet extends ConsumerStatefulWidget {
  const _MatchSheet({required this.match, required this.entrants});
  final Entity match;
  final List<Entity> entrants;

  @override
  ConsumerState<_MatchSheet> createState() => _MatchSheetState();
}

class _MatchSheetState extends ConsumerState<_MatchSheet> {
  late List<Object> _competitors = [for (final e in competitorsOf(widget.match)) e.id];
  late String? _matchTypeId = widget.match['matchTypeId'] as String?;
  late String? _winnerId = widget.match['winnerId'] as String?;
  bool _busy = false;

  Future<void> _save() async {
    final ids = _competitors.cast<String>();
    // vencedor que deixou de ser competidor é descartado
    final winner = _winnerId != null && ids.contains(_winnerId) ? _winnerId : null;
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).put('tournament-matches/${widget.match.id}', body: {
        'entrantAId': ids.firstOrNull,
        'entrantBId': ids.length > 1 ? ids[1] : null,
        'extraEntrantIds': ids.skip(2).toList(),
        'matchTypeId': _matchTypeId,
        'winnerId': winner,
      });
      invalidateItems(ref, ['episodes']);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final matchTypes = ref.watch(itemsProvider('match-types')).value ?? const <Entity>[];
    final all = [for (final e in widget.entrants) Choice(e.id, entrantName(e) + (e['seed'] != null ? ' (#${e['seed']})' : ''))];
    final contenders = all.where((c) => _competitors.contains(c.value)).toList();
    final m = widget.match;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Editar luta', style: Theme.of(context).textTheme.titleLarge),
          Text('${m['groupName'] != null ? '${m['groupName']} · ' : ''}Rodada ${m['round']} · Luta ${m['slot']}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          PickerField(
            label: 'Tipo de luta / estipulação',
            value: _matchTypeId,
            hint: 'Cada luta pode ter o seu: Singles, Triple Threat, Hell in a Cell...',
            choices: [for (final t in matchTypes) Choice(t.id, t['name'] as String? ?? '')],
            onChanged: (v) => setState(() => _matchTypeId = v as String?),
          ),
          const SizedBox(height: 14),
          MultiPickerField(
            label: 'Competidores',
            values: _competitors,
            choices: all,
            hint: 'Dois = luta comum; três ou mais = triple threat, fatal 4-way... Só um vence e avança na chave.',
            onChanged: (v) => setState(() => _competitors = v),
          ),
          const SizedBox(height: 14),
          PickerField(
            label: 'Vencedor',
            value: _winnerId != null && _competitors.contains(_winnerId) ? _winnerId : null,
            choices: contenders,
            onChanged: (v) => setState(() => _winnerId = v as String?),
          ),
          if (m.obj('segment') != null) ...[
            const SizedBox(height: 12),
            Text('Luta agendada no card de um episódio: os lutadores e o tipo de luta daqui são aplicados lá enquanto ela não for realizada.',
                style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 16),
          BusyButton(label: 'Salvar', icon: Icons.check, onPressed: _busy ? null : _save),
        ]),
      ),
    );
  }
}

// ───────────────────────────── agendar em episódio ─────────────────────────────

class _ScheduleResult {
  const _ScheduleResult(this.episodeId, this.matchTypeId);
  final String episodeId;
  final String? matchTypeId;
}

class _ScheduleSheet extends ConsumerStatefulWidget {
  const _ScheduleSheet({required this.summary, required this.askMatchType, this.matchTypeId});
  final String summary;
  final bool askMatchType;
  final String? matchTypeId;

  static Future<_ScheduleResult?> show(BuildContext context, {required String summary, required bool askMatchType, String? matchTypeId}) =>
      showModalBottomSheet<_ScheduleResult>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _ScheduleSheet(summary: summary, askMatchType: askMatchType, matchTypeId: matchTypeId),
      );

  @override
  ConsumerState<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends ConsumerState<_ScheduleSheet> {
  String? _episodeId;
  late String? _matchTypeId = widget.matchTypeId;
  late final Future<List<Entity>> _planned = ref.read(apiProvider).all('episodes', query: {'status': 'PLANNED'});

  @override
  Widget build(BuildContext context) {
    final seasons = ref.watch(itemsProvider('seasons')).value ?? const <Entity>[];
    final matchTypes = ref.watch(itemsProvider('match-types')).value ?? const <Entity>[];
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: FutureBuilder<List<Entity>>(
        future: _planned,
        builder: (ctx, snap) {
          if (snap.hasError) return Text('${snap.error}');
          if (!snap.hasData) return const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
          final seasonOf = {for (final s in seasons) s.id: s};
          // episódios planejados, na ordem de jogo, sem os meses anteriores ao início
          final list = snap.data!
              .where((e) => !beforeStart((e['month'] as num).toInt(), (seasonOf[e['seasonId']]?['startMonth'] as num?)?.toInt()))
              .toList()
            ..sort((a, b) {
              final na = (seasonOf[a['seasonId']]?['number'] as num?) ?? 0;
              final nb = (seasonOf[b['seasonId']]?['number'] as num?) ?? 0;
              return na != nb ? na.compareTo(nb) : compareEpisodeEntities(a, b);
            });
          final multiSeason = list.map((e) => e['seasonId']).toSet().length > 1;
          final choices = [
            for (final e in list)
              Choice(e.id, '${multiSeason && seasonOf[e['seasonId']] != null ? '${resources['seasons']!.label(seasonOf[e['seasonId']]!)} · ' : ''}${episodeText(e)}'),
          ];
          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Agendar em episódio', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(widget.summary, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            PickerField(
              label: 'Episódio',
              required: true,
              value: _episodeId,
              hint: choices.isEmpty ? 'Nenhum episódio planejado. Gere o calendário em Episódios.' : null,
              choices: choices,
              onChanged: (v) => setState(() => _episodeId = v as String?),
            ),
            if (widget.askMatchType) ...[
              const SizedBox(height: 14),
              PickerField(
                label: 'Tipo de luta',
                value: _matchTypeId,
                hint: 'Vazio = automático (pelo nº de competidores)',
                choices: [for (final t in matchTypes) Choice(t.id, t['name'] as String? ?? '')],
                onChanged: (v) => setState(() => _matchTypeId = v as String?),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _episodeId == null ? null : () => Navigator.pop(context, _ScheduleResult(_episodeId!, _matchTypeId)),
              icon: const Icon(Icons.event_available),
              label: const Text('Agendar'),
            ),
          ]);
        },
      ),
    );
  }
}
