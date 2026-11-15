import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/ai_plan_logic.dart';
import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../resources/resources.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui.dart';
import '../resources/field_widgets.dart';

enum _Step { form, running, preview }

/// Gera segmentos com IA (Gemini gratuito) — espelha o `suggest-segments-dialog` do web.
/// Com [episodeId]: só o card daquele episódio (`POST episodes/:id/segments/suggest`).
/// Sem ele: planeja um período do calendário do jogo (`POST episodes/suggest-range` + progresso).
/// Nada é gravado até o usuário revisar a prévia e salvar. Fecha com o nº de episódios salvos.
class AiPlanPage extends ConsumerStatefulWidget {
  const AiPlanPage({super.key, this.episodeId, this.episodeLabel, this.seasonId});
  final String? episodeId;
  final String? episodeLabel;
  final String? seasonId;

  bool get single => episodeId != null;

  @override
  ConsumerState<AiPlanPage> createState() => _AiPlanPageState();
}

class _AiPlanPageState extends ConsumerState<AiPlanPage> {
  static const _aiTimeout = Duration(minutes: 3);

  _Step _step = _Step.form;
  String? _error;

  // formulário
  String? _seasonId;
  int _fromMonth = 5, _fromWeek = 1, _toMonth = 5, _toWeek = 4;
  List<Object> _showIds = [];
  int _count = 5;
  bool _mainEvent = true;
  bool _skipPlanned = true;
  final _guidance = TextEditingController();

  // andamento e prévia
  String? _jobId;
  Entity? _job;
  Timer? _timer;
  List<Entity> _episodes = [];
  Set<String> _selected = {};
  bool _replace = false;

  @override
  void initState() {
    super.initState();
    _seasonId = widget.seasonId;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _guidance.dispose();
    super.dispose();
  }

  bool get _inverted =>
      !widget.single && aiRangeInverted(fromMonth: _fromMonth, fromWeek: _fromWeek, toMonth: _toMonth, toWeek: _toWeek);

  Map<String, dynamic> get _options => {
    'count': _count,
    'includeMainEvent': _mainEvent,
    if (_guidance.text.trim().isNotEmpty) 'guidance': _guidance.text.trim(),
  };

  Future<void> _generate() async {
    if (!widget.single && _seasonId == null) return showInfo(context, 'Escolha a temporada.');
    if (_inverted) return;
    final api = ref.read(apiProvider);
    setState(() {
      _error = null;
      _step = _Step.running;
    });
    try {
      if (widget.single) {
        final res = await api.post(
          'episodes/${widget.episodeId}/segments/suggest',
          body: _options,
          receiveTimeout: _aiTimeout,
        );
        _showPreview([Map<String, dynamic>.from(res as Map)]);
      } else {
        final res = await api.post(
          'episodes/suggest-range',
          body: aiRangeBody(
            seasonId: _seasonId!,
            fromMonth: _fromMonth,
            fromWeek: _fromWeek,
            toMonth: _toMonth,
            toWeek: _toWeek,
            count: _count,
            includeMainEvent: _mainEvent,
            skipPlanned: _skipPlanned,
            showIds: _showIds.cast<String>(),
            guidance: _guidance.text,
          ),
        );
        _jobId = res['jobId'] as String;
        setState(() => _job = {'status': 'running', 'total': res['total'], 'done': 0, 'current': null});
        _poll();
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _step = _Step.form;
          _error = e.message;
        });
      }
    }
  }

  void _poll() {
    _timer = Timer(const Duration(milliseconds: 2500), () async {
      try {
        final j = Map<String, dynamic>.from(await ref.read(apiProvider).get('episodes/suggest-range/$_jobId') as Map);
        if (!mounted) return;
        setState(() => _job = j);
        if (j['status'] == 'running') return _poll();
        final eps = j.list('episodes');
        if (j['status'] == 'error' && !eps.any((e) => e.list('segments').isNotEmpty)) {
          setState(() {
            _step = _Step.form;
            _error = j['error'] as String? ?? 'A geração falhou.';
          });
          return;
        }
        if (j['status'] == 'error' && j['error'] != null) {
          showInfo(context, '${j['error']} Os episódios já gerados foram mantidos.');
        }
        _showPreview(eps);
      } on ApiException {
        if (!mounted) return;
        setState(() {
          _step = _Step.form;
          _error = 'Perdi o andamento da geração (o servidor pode ter reiniciado). Gere de novo.';
        });
      }
    });
  }

  Future<void> _stop() async {
    _timer?.cancel();
    try {
      await ref.read(apiProvider).delete('episodes/suggest-range/$_jobId');
      final j = Map<String, dynamic>.from(await ref.read(apiProvider).get('episodes/suggest-range/$_jobId') as Map);
      _showPreview(j.list('episodes'));
    } on ApiException {
      _showPreview(_job?.list('episodes') ?? []);
    }
  }

  void _showPreview(List<Entity> list) {
    if (!mounted) return;
    setState(() {
      _episodes = list;
      _selected = {
        for (final e in list)
          if (e.list('segments').isNotEmpty) e['episodeId'] as String,
      };
      _step = _Step.preview;
    });
  }

  Future<void> _save() async {
    final items = aiBulkItems(_episodes, _selected, replace: _replace);
    if (items.isEmpty) return;
    final api = ref.read(apiProvider);
    try {
      if (widget.single) {
        await api.post(
          'episodes/${widget.episodeId}/segments',
          body: {'replace': _replace, 'segments': items.first['segments']},
        );
        invalidateItems(ref, ['episodes']);
        if (mounted) context.pop(1);
        return;
      }
      final res = await api.post('episodes/segments/bulk', body: {'items': items});
      final results = (res['results'] as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
      final failed = {
        for (final r in results)
          if (r['ok'] != true) r['episodeId'] as String: r['error'] as String? ?? 'erro',
      };
      invalidateItems(ref, ['episodes']);
      if (!mounted) return;
      if (failed.isEmpty) {
        context.pop(results.length);
        return;
      }
      // mantém na prévia só o que falhou, com o motivo
      setState(() {
        _episodes = [
          for (final e in _episodes)
            if (failed.containsKey(e['episodeId'])) {...e, 'error': failed[e['episodeId']]},
        ];
        _selected = failed.keys.toSet();
      });
      showInfo(context, '${results.length - failed.length} episódio(s) gravado(s), ${failed.length} com erro.');
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    // nomes de tipo de luta, título e divisão na prévia
    ref.watch(itemsProvider('match-types'));
    ref.watch(itemsProvider('titles'));
    ref.watch(itemsProvider('card-divisions'));
    return AppPage(
      title: widget.single ? 'Gerar com IA' : 'Planejar com IA',
      subtitle: widget.single ? widget.episodeLabel : null,
      showBack: true,
      body: switch (_step) {
        _Step.form => _form(context),
        _Step.running => _running(context),
        _Step.preview => _preview(context),
      },
    );
  }

  Widget _form(BuildContext context) {
    final seasons = ref.watch(itemsProvider('seasons')).value ?? const <Entity>[];
    final shows = ref.watch(itemsProvider('shows')).value ?? const <Entity>[];
    final monthChoices = [for (final m in seasonMonths) Choice(m, monthName(m))];
    final weekChoices = [for (var w = 1; w <= 4; w++) Choice(w, 'Semana $w')];
    final small = Theme.of(context).textTheme.bodySmall;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'A IA (Gemini gratuito) monta ${widget.single ? 'o card deste episódio' : 'os cards do período'} usando o elenco, '
          'os rankings das divisões, os campeões, as rivalidades e as lutas já realizadas. Nada é gravado até você revisar'
          '${widget.single ? '.' : '. Só planeja: as lutas entram sem resultado.'}',
          style: small,
        ),
        const SizedBox(height: 16),
        if (!widget.single) ...[
          PickerField(
            label: 'Temporada',
            required: true,
            value: _seasonId,
            choices: [for (final s in seasons) Choice(s.id, resources['seasons']!.label(s))],
            onChanged: (v) => setState(() => _seasonId = v as String?),
          ),
          const SizedBox(height: 14),
          Text('De', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: PickerField(
                  label: 'Mês',
                  value: _fromMonth,
                  choices: monthChoices,
                  onChanged: (v) => setState(() => _fromMonth = v as int),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PickerField(
                  label: 'Semana',
                  value: _fromWeek,
                  choices: weekChoices,
                  onChanged: (v) => setState(() => _fromWeek = v as int),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text('Até', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: PickerField(
                  label: 'Mês',
                  value: _toMonth,
                  choices: monthChoices,
                  onChanged: (v) => setState(() => _toMonth = v as int),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PickerField(
                  label: 'Semana',
                  value: _toWeek,
                  choices: weekChoices,
                  onChanged: (v) => setState(() => _toWeek = v as int),
                ),
              ),
            ],
          ),
          if (_inverted)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'O fim vem antes do início (a temporada vai de maio a abril).',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 14),
          MultiPickerField(
            label: 'Shows (vazio = todos)',
            values: _showIds,
            choices: [for (final s in shows) Choice(s.id, s['name'] as String)],
            onChanged: (v) => setState(() => _showIds = v),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            const Expanded(child: Text('Segmentos por episódio')),
            IconButton(onPressed: _count > 1 ? () => setState(() => _count--) : null, icon: const Icon(Icons.remove)),
            Text('$_count'),
            IconButton(onPressed: _count < 10 ? () => setState(() => _count++) : null, icon: const Icon(Icons.add)),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Terminar com main event'),
          value: _mainEvent,
          onChanged: (v) => setState(() => _mainEvent = v),
        ),
        if (!widget.single)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Pular episódios que já têm card planejado'),
            value: _skipPlanned,
            onChanged: (v) => setState(() => _skipPlanned = v),
          ),
        const SizedBox(height: 8),
        TextField(
          controller: _guidance,
          maxLength: 500,
          maxLines: 3,
          minLines: 2,
          decoration: const InputDecoration(
            labelText: 'Orientação (opcional)',
            hintText: 'Ex.: dar destaque ao título mundial e à rivalidade do Cena',
            border: OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _inverted ? null : _generate,
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Gerar'),
        ),
      ],
    );
  }

  Widget _running(BuildContext context) {
    final done = (_job?['done'] as num?)?.toInt() ?? 0;
    final total = (_job?['total'] as num?)?.toInt() ?? 0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 40, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            if (widget.single) ...[
              const Text('Montando o card…'),
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ] else ...[
              Text('Planejando $done de $total episódios', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(_job?['current'] as String? ?? 'Preparando…', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: aiProgress(_job)),
              const SizedBox(height: 12),
              Text(
                'Cada episódio é uma chamada à IA gratuita, com pausa entre elas para respeitar o limite. '
                'Períodos longos levam alguns minutos; mantenha esta tela aberta.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _stop, child: const Text('Parar e ver o que já saiu')),
            ],
          ],
        ),
      ),
    );
  }

  String _segmentTitle(Entity s) {
    if (s['type'] != 'MATCH') return s['type'] == 'PROMO' ? 'Promo' : 'Segmento';
    return _name('match-types', s['matchTypeId']) ?? 'Luta';
  }

  String? _name(String key, Object? id) {
    if (id == null) return null;
    final list = ref.read(itemsProvider(key)).value ?? const <Entity>[];
    return list.where((e) => e.id == id).firstOrNull?['name'] as String?;
  }

  Widget _preview(BuildContext context) {
    final saveCount = _episodes
        .where((e) => _selected.contains(e['episodeId']) && e.list('segments').isNotEmpty)
        .length;
    return Column(
      children: [
        Expanded(
          child: _episodes.isEmpty
              ? const EmptyState('Nada foi gerado.', icon: Icons.auto_awesome)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  children: [
                    for (final e in _episodes) _episodeCard(context, e),
                    SwitchListTile(
                      title: const Text('Substituir o card atual dos episódios que já têm segmentos'),
                      value: _replace,
                      onChanged: (v) => setState(() => _replace = v),
                    ),
                  ],
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                TextButton(onPressed: () => setState(() => _step = _Step.form), child: const Text('Voltar')),
                const Spacer(),
                BusyButton(
                  label: widget.single ? 'Salvar card' : 'Salvar $saveCount episódio(s)',
                  icon: Icons.check,
                  onPressed: saveCount == 0 ? null : _save,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _episodeCard(BuildContext context, Entity e) {
    final theme = Theme.of(context);
    final id = e['episodeId'] as String;
    final segments = e.list('segments');
    final on = _selected.contains(id);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Opacity(
        opacity: on || segments.isEmpty ? 1 : 0.55,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (segments.isNotEmpty)
                    Checkbox(
                      value: on,
                      onChanged: (v) => setState(() => v == true ? _selected.add(id) : _selected.remove(id)),
                    )
                  else
                    const SizedBox(width: 12),
                  Expanded(child: Text(e['label'] as String? ?? '', style: theme.textTheme.titleSmall)),
                ],
              ),
              if (e['error'] != null)
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 4),
                  child: Text(e['error'] as String, style: TextStyle(color: theme.colorScheme.error)),
                ),
              for (var i = 0; i < segments.length; i++) _segmentRow(context, id, i, segments[i]),
              for (final w in (e['warnings'] as List? ?? const []))
                Padding(
                  padding: const EdgeInsets.only(left: 12, top: 2),
                  child: Text('ⓘ $w', style: theme.textTheme.bodySmall?.copyWith(color: Colors.amber.shade700)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _segmentRow(BuildContext context, String episodeId, int i, Entity s) {
    final theme = Theme.of(context);
    final tags = <Widget>[
      if (s['isMainEvent'] == true) _tag(context, 'MAIN EVENT', theme.colorScheme.primary),
      if (s['titleId'] != null) _tag(context, _name('titles', s['titleId']) ?? 'Título', Colors.amber.shade700),
      if (s['stakes'] != null && s['stakes'] != 'NONE' && s['cardDivisionId'] != null)
        _tag(
          context,
          '${s['stakes'] == 'CONTENDER' ? 'Desafiante' : 'Subida'}: ${_name('card-divisions', s['cardDivisionId']) ?? ''}',
          Colors.blue,
        ),
      if (s['startsRivalry'] == true) _tag(context, 'Começa rivalidade', Colors.red),
      if (s['endsRivalry'] == true) _tag(context, 'Encerra rivalidade', Colors.red),
    ];
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 22, child: Text('${i + 1}', style: theme.textTheme.bodySmall)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_segmentTitle(s), style: const TextStyle(fontWeight: FontWeight.w600)),
                if (tags.isNotEmpty) Wrap(spacing: 4, runSpacing: 4, children: tags),
                Text(aiSidesText(s)),
                if ((s['notes'] as String?)?.isNotEmpty == true)
                  Text(s['notes'] as String, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remover segmento',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() {
              _episodes = [for (final e in _episodes) e['episodeId'] == episodeId ? aiWithoutSegment(e, i) : e];
            }),
          ),
        ],
      ),
    );
  }

  Widget _tag(BuildContext context, String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
    ),
  );
}
