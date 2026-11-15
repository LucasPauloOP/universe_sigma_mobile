import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/api_exception.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/segment_logic.dart';
import '../../resources/resources.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui.dart';
import '../divisions/ranking_sheet.dart';
import '../resources/field_widgets.dart';
import 'episode_card_page.dart';

/// Formulário de segmento (luta, promo ou outro). Porte do SegmentDialog do web.
class SegmentFormPage extends ConsumerStatefulWidget {
  const SegmentFormPage({super.key, required this.episodeId, this.segmentId, this.markDone = false});
  final String episodeId;
  final String? segmentId;
  final bool markDone;

  @override
  ConsumerState<SegmentFormPage> createState() => _SegmentFormPageState();
}

class _SegmentFormPageState extends ConsumerState<SegmentFormPage> {
  SegmentDraft? _d;
  Entity? _segment;
  List<Entity> _openMatches = const [];
  bool _busy = false;
  final _notes = TextEditingController();

  bool get _editing => widget.segmentId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      if (_editing) {
        final card = await ref.read(episodeCardProvider(widget.episodeId).future);
        _segment = card.list('segments').where((s) => s.id == widget.segmentId).firstOrNull;
      }
      _d = _segment != null ? SegmentDraft.fromEntity(_segment!, markDone: widget.markDone) : SegmentDraft(isDone: widget.markDone);
      _notes.text = _d!.notes;
      final m = await ref.read(apiProvider).get('tournaments/open-matches') as List;
      _openMatches = m.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
      _d ??= SegmentDraft(isDone: widget.markDone);
    }
    if (mounted) setState(() {});
  }

  List<Choice> _items(String key, {String Function(Entity)? label}) {
    final list = ref.watch(itemsProvider(key)).value ?? const <Entity>[];
    return [for (final e in list) Choice(e.id, label != null ? label(e) : (e['name'] as String? ?? ''))]
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  }

  /// Luta de torneio: a atual do segmento (se houver) + as que ainda não têm episódio.
  List<Choice> get _tournamentChoices {
    final list = [for (final m in _openMatches) Choice(m.id, tournamentMatchLabel(m))];
    final cur = _segment?.obj('tournamentMatch');
    if (cur != null && !list.any((c) => c.value == cur.id)) {
      list.insert(0, Choice(cur.id, '${cur.obj('tournament')?['name']} (atual)'));
    }
    return list;
  }

  /// Abre o ranking das divisões (na marca do show do episódio) para apoiar o planejamento.
  Future<void> _showRanking() async {
    String? brandId;
    try {
      final card = await ref.read(episodeCardProvider(widget.episodeId).future);
      brandId = card.obj('show')?['brandId'] as String?;
    } catch (_) {}
    if (!mounted) return;
    await DivisionRankingSheet.show(context, brandId: brandId, scheduledIds: {for (final p in _d!.participants) p.wrestlerId});
  }

  Future<void> _save() async {
    final d = _d!;
    d.notes = _notes.text;
    if (!d.canSave) return;
    setState(() => _busy = true);
    try {
      final api = ref.read(apiProvider);
      final body = d.toBody(widget.episodeId);
      if (_editing) {
        await api.put('segments/${widget.segmentId}', body: body);
      } else {
        await api.post('segments', body: body);
      }
      invalidateItems(ref, ['episodes', 'title-reigns', 'card-divisions']);
      if (mounted) context.pop(true);
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) {
      return const AppPage(title: 'Segmento', showBack: true, body: Center(child: CircularProgressIndicator()));
    }
    final wrestlers = ref.watch(itemsProvider('wrestlers')).value ?? const <Entity>[];
    final nameOf = {for (final w in wrestlers) w.id: w['name'] as String? ?? ''};
    final used = d.participants.map((p) => p.wrestlerId).toSet();
    final available = [
      for (final w in wrestlers)
        if (!used.contains(w.id)) Choice(w.id, w['name'] as String? ?? ''),
    ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    final matchTypes = ref.watch(itemsProvider('match-types')).value ?? const <Entity>[];
    final scheme = Theme.of(context).colorScheme;
    final problem = d.problem;

    return AppPage(
      title: _editing ? 'Editar segmento' : 'Novo segmento',
      showBack: true,
      actions: [TextButton(onPressed: _busy || !d.canSave ? null : _save, child: const Text('Salvar'))],
      body: ListView(padding: const EdgeInsets.all(16), children: [
        PickerField(
          label: 'Tipo',
          required: true,
          value: d.type,
          choices: [for (final o in segmentType) Choice(o.value, o.label)],
          onChanged: (v) => setState(() => d.type = v as String),
        ),
        if (d.isMatch) ...[
          const SizedBox(height: 14),
          PickerField(
            label: 'Tipo de luta',
            value: d.matchTypeId,
            choices: _items('match-types'),
            onChanged: (v) => setState(() => d.matchTypeId = v as String?),
          ),
          const SizedBox(height: 14),
          PickerField(
            label: 'Valendo título',
            value: d.titleId,
            choices: _items('titles', label: (e) => resources['titles']!.label(e)),
            onChanged: (v) => setState(() {
              d.titleId = v as String?;
              if (v == null) d.titleChanged = false;
            }),
          ),
          const SizedBox(height: 14),
          PickerField(
            label: 'Como terminou${d.needsResult && !d.isDraw ? ' *' : ''}',
            value: d.finishType,
            choices: [for (final o in finishType) Choice(o.value, o.label)],
            onChanged: (v) => setState(() => d.finishType = v as String?),
          ),
          const SizedBox(height: 14),
          PickerField(
            label: 'O que está em jogo no ranking',
            required: true,
            value: d.stakes,
            choices: const [
              Choice('NONE', 'Nada (luta comum)'),
              Choice('RANKING', 'Vale subida de divisão'),
              Choice('CONTENDER', 'Decide o desafiante'),
            ],
            onChanged: (v) => setState(() {
              d.stakes = v as String;
              if (d.stakes == 'NONE') d.cardDivisionId = null;
            }),
          ),
          if (d.hasStakes) ...[
            const SizedBox(height: 14),
            PickerField(
              label: 'Divisão afetada',
              required: true,
              value: d.cardDivisionId,
              error: d.missingDivision ? 'Escolha a divisão' : null,
              choices: _items('card-divisions', label: (e) => resources['card-divisions']!.label(e)),
              onChanged: (v) => setState(() => d.cardDivisionId = v as String?),
            ),
          ],
          if (_tournamentChoices.isNotEmpty) ...[
            const SizedBox(height: 14),
            PickerField(
              label: 'Luta de torneio',
              value: d.tournamentMatchId,
              hint: 'Ao marcar a luta como realizada com vencedor, a vaga é decidida e a chave do torneio avança.',
              choices: _tournamentChoices,
              onChanged: (v) => setState(() {
                if (v == null) {
                  d.tournamentMatchId = null;
                } else {
                  d.pickTournamentMatch(_openMatches.where((m) => m.id == v).firstOrNull ?? {'id': v}, matchTypes);
                }
              }),
            ),
          ],
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(onPressed: _showRanking, icon: const Icon(Icons.leaderboard), label: const Text('Ver ranking das divisões')),
        ),
        if (d.isMatch && d.hasTitle)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Houve troca de campeão'),
            subtitle: const Text('Com a luta realizada e o vencedor marcado (estrela), o novo reinado é criado e o ex-campeão entra na fila da divisão.'),
            value: d.titleChanged,
            onChanged: (v) => setState(() => d.titleChanged = v),
          ),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Main event'), value: d.isMainEvent, onChanged: (v) => setState(() => d.isMainEvent = v)),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Realizado'), value: d.isDone, onChanged: (v) => setState(() => d.isDone = v)),
        if (d.isMatch)
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Empate'), value: d.isDraw, onChanged: (v) => setState(() => d.setDraw(v))),
        const Divider(),
        Text('Participantes', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('Cada lado é um time (em lutas individuais, um lutador por lado). Toque na estrela para marcar o vencedor.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        for (final side in d.sides)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('Lado $side', style: const TextStyle(fontWeight: FontWeight.w600))),
                  if (d.isMatch && d.onSide(side).isNotEmpty)
                    d.sideWins(side)
                        ? FilledButton.icon(onPressed: () => setState(() => d.toggleSideWinner(side)), icon: const Icon(Icons.star, size: 16), label: const Text('Vencedor'))
                        : OutlinedButton.icon(onPressed: () => setState(() => d.toggleSideWinner(side)), icon: const Icon(Icons.star_border, size: 16), label: const Text('Venceu')),
                ]),
                const SizedBox(height: 8),
                if (d.onSide(side).isEmpty)
                  Text('Ninguém neste lado.', style: Theme.of(context).textTheme.bodySmall)
                else
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    for (final p in d.onSide(side))
                      InputChip(
                        avatar: IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: Icon(p.isWinner ? Icons.star : Icons.star_border, size: 18, color: p.isWinner ? scheme.onPrimary : null),
                          onPressed: d.isMatch ? () => setState(() => d.toggleWinner(p.wrestlerId)) : null,
                        ),
                        label: Text(nameOf[p.wrestlerId] ?? '…', style: TextStyle(color: p.isWinner ? scheme.onPrimary : null)),
                        backgroundColor: p.isWinner ? scheme.primary : null,
                        deleteIconColor: p.isWinner ? scheme.onPrimary : null,
                        onDeleted: () => setState(() => d.removeParticipant(p.wrestlerId)),
                      ),
                  ]),
                const SizedBox(height: 8),
                PickerField(
                  label: 'Adicionar lutador',
                  value: null,
                  choices: available,
                  onChanged: (v) => setState(() {
                    if (v != null) d.addParticipant(side, v as String);
                  }),
                ),
              ]),
            ),
          ),
        Row(children: [
          TextButton.icon(onPressed: () => setState(d.addSide), icon: const Icon(Icons.add), label: const Text('Lado')),
          if (d.sideCount > 1) TextButton.icon(onPressed: () => setState(d.removeSide), icon: const Icon(Icons.remove), label: const Text('Lado')),
        ]),
        if (problem != null)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Icon(Icons.error_outline, color: scheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(child: Text(problem, style: TextStyle(color: scheme.onErrorContainer))),
            ]),
          ),
        const SizedBox(height: 16),
        TextField(controller: _notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Notas')),
        const SizedBox(height: 20),
        BusyButton(label: 'Salvar', icon: Icons.check, onPressed: _busy || !d.canSave ? null : _save),
        const SizedBox(height: 48),
      ]),
    );
  }
}
