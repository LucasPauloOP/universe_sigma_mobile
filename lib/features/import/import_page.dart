import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../core/import_logic.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui.dart';

class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key});
  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<ImportPage> {
  final _options = defaultImportOptions();
  PlatformFile? _file;
  bool _busy = false;
  Entity? _report;
  Entity? _result;

  Future<void> _pick() async {
    final res = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['xlsx']);
    final f = res.firstOrNull;
    if (f == null) return;
    setState(() {
      _file = f;
      _report = null;
      _result = null;
    });
  }

  Future<Entity?> _send({required bool apply}) async {
    final path = _file?.path;
    if (path == null) return null;
    setState(() => _busy = true);
    try {
      final d = await ref.read(apiProvider).upload(
        'import/universe-sheet',
        path,
        fields: {'options': optionsJson(_options)},
        query: apply ? {'apply': 'true'} : null,
      );
      return Map<String, dynamic>.from(d as Map);
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _analyze() async {
    setState(() => _result = null);
    final res = await _send(apply: false);
    if (res != null && mounted) setState(() => _report = res.obj('report'));
  }

  Future<void> _apply() async {
    final r = _report;
    if (r == null) return;
    final ok = await confirm(
      context,
      title: 'Importar planilha',
      message: importSummary(r, _options),
      confirmLabel: 'Importar',
      danger: needsDangerConfirm(_options),
    );
    if (!ok || !mounted) return;
    final res = await _send(apply: true);
    if (res == null || !mounted) return;
    // lutadores, duplas, brands, shows e divisões mudaram: a memória de listas ficou velha
    ref.invalidate(itemsProvider);
    setState(() {
      _result = res.obj('result');
      _report = null;
    });
    showInfo(context, 'Planilha importada');
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final result = _result;
    return AppPage(
      title: 'Importar planilha',
      subtitle: 'Rosters, divisões e PLEs a partir da sua planilha',
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('1. Escolha a planilha', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Formato esperado (.xlsx): aba “Roster completo” (uma coluna por brand e “… Tag teams”), uma aba por brand (ex.: raw, smackdown) com as colunas Main Card, Mid Card, Tags, Women’s World/Mid/Tag, Legends e Others, e a aba “PLEs”. As outras abas são ignoradas.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Row(children: [
                OutlinedButton.icon(onPressed: _pick, icon: const Icon(Icons.table_chart), label: const Text('Escolher arquivo')),
                const SizedBox(width: 12),
                Expanded(child: Text(_file?.name ?? 'Nenhum arquivo escolhido', overflow: TextOverflow.ellipsis)),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('2. O que importar', style: Theme.of(context).textTheme.titleMedium),
              for (final o in importOptions)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(o.label),
                  subtitle: o.hint.isEmpty ? null : Text(o.hint),
                  value: _options[o.key] ?? false,
                  // a análise depende das opções: precisa analisar de novo
                  onChanged: (v) => setState(() {
                    _options[o.key] = v;
                    _report = null;
                  }),
                ),
              const SizedBox(height: 8),
              BusyButton(label: 'Analisar planilha', icon: Icons.search, onPressed: _file == null || _busy ? null : _analyze),
              const SizedBox(height: 4),
              Text('Nada é gravado nesta etapa.', style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ),
        if (result != null) ...[const SizedBox(height: 12), _resultCard(result)],
        if (report != null) ...[const SizedBox(height: 12), _reportCard(report)],
        const SizedBox(height: 48),
      ]),
    );
  }

  Widget _resultCard(Entity r) {
    final divMissing = (r['divisionsMissing'] as List? ?? const []).cast<String>();
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text('Importação concluída', style: Theme.of(context).textTheme.titleMedium),
          ]),
          const SizedBox(height: 8),
          Text('• ${r['linksAdded']} vínculos de roster adicionados e ${r['linksRemoved']} removidos'),
          Text('• ${r['wrestlersCreated']} lutadores e ${r['teamsCreated']} duplas criados; ${r['activated']} ativados${(r['deactivated'] as num? ?? 0) > 0 ? '; ${r['deactivated']} desativados' : ''}'),
          Text('• ${r['divisionsFilled']} divisões preenchidas'),
          Text('• PLEs: ${r['plesCreated']} criados, ${r['plesUpdated']} ajustados${(r['plesDeactivated'] as num? ?? 0) > 0 ? ', ${r['plesDeactivated']} desativados' : ''}'),
          if (divMissing.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Divisões não encontradas (não preenchidas): ${divMissing.join(', ')}.', style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            FilledButton.icon(onPressed: () => context.go('/divisions'), icon: const Icon(Icons.format_list_numbered), label: const Text('Ver divisões')),
            OutlinedButton.icon(onPressed: () => context.go('/episodes'), icon: const Icon(Icons.event), label: const Text('Gerar episódios dos PLEs')),
          ]),
        ]),
      ),
    );
  }

  Widget _chips(Iterable<String> items) => Wrap(spacing: 6, runSpacing: 4, children: [for (final i in items) Chip(label: Text(i, style: const TextStyle(fontSize: 12)), visualDensity: VisualDensity.compact)]);

  Widget _reportCard(Entity r) {
    final scheme = Theme.of(context).colorScheme;
    final ples = r.obj('ples') ?? const <String, dynamic>{};
    List<Entity> pl(String k) => ((ples[k] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final warnings = (r['warnings'] as List? ?? const []).cast<String>();
    final fuzzy = r.list('fuzzy');
    final ignored = (r['ignored'] as List? ?? const []).cast<String>();
    final skipped = (r['skippedMissing'] as List? ?? const []).cast<String>();
    final newW = r.list('newWrestlers');
    final newT = r.list('newTeams');
    Widget h(String t) => Padding(padding: const EdgeInsets.only(top: 16, bottom: 6), child: Text(t, style: Theme.of(context).textTheme.titleSmall));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('3. Confira antes de importar', style: Theme.of(context).textTheme.titleMedium),
          Text('Isto é só uma prévia: nada foi gravado ainda.', style: Theme.of(context).textTheme.bodySmall),
          if (warnings.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final w in warnings) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('⚠ $w', style: TextStyle(color: scheme.onTertiaryContainer))),
              ]),
            ),
          h('Rosters e divisões por brand'),
          for (final b in r.list('brands'))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border.all(color: scheme.outlineVariant), borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(b['brand'] as String, style: Theme.of(context).textTheme.titleMedium),
                    if (b['isActive'] == false) const Padding(padding: EdgeInsets.only(left: 8), child: Chip(label: Text('Brand desativada'), visualDensity: VisualDensity.compact)),
                  ]),
                  Text.rich(TextSpan(children: [
                    TextSpan(text: 'Roster na planilha: ${b['roster']} · '),
                    TextSpan(text: '+${b['add']} entram', style: const TextStyle(color: Color(0xFF16A34A))),
                    const TextSpan(text: ' · '),
                    TextSpan(text: '−${b['remove']} saem', style: const TextStyle(color: Color(0xFFDC2626))),
                  ])),
                  const SizedBox(height: 6),
                  _chips([for (final d in b.list('divisions')) '${d['name']}: ${d['count']}']),
                ]),
              ),
            ),
          h('Lutadores a criar (${newW.length})'),
          if (newW.isEmpty)
            const Text('Todos os nomes já existem no universe.')
          else ...[
            _chips([for (final w in newW) '${w['gender'] == 'W' ? '♀' : '♂'} ${w['name']}${contractLabel(w['contractType'] as String?).isNotEmpty ? ' · ${contractLabel(w['contractType'] as String?)}' : ''}']),
            if ((r['assumedMale'] as List? ?? const []).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Gênero masculino assumido para quem não aparece em coluna feminina; ajuste depois em Lutadores se precisar.', style: Theme.of(context).textTheme.bodySmall),
              ),
          ],
          h('Duplas a criar (${newT.length})'),
          if (newT.isEmpty)
            const Text('Nenhuma dupla nova.')
          else
            for (final t in newT)
              Text('• ${t['name']}${(t['members'] as List).isNotEmpty ? ' — ${(t['members'] as List).join(' e ')}' : ' (sem integrantes)'}'),
          if (_options['importPles'] == true) ...[
            h('PLEs'),
            Text('A criar (${pl('create').length})', style: const TextStyle(fontWeight: FontWeight.w600)),
            if (pl('create').isEmpty) const Text('—'),
            for (final p in pl('create')) Text('${p['name']} · ${monthName((p['ppvMonth'] as num?)?.toInt())}, semana ${p['ppvWeek']}'),
            const SizedBox(height: 8),
            Text('Mês/semana ajustados (${pl('update').length})', style: const TextStyle(fontWeight: FontWeight.w600)),
            if (pl('update').isEmpty) const Text('—'),
            for (final p in pl('update'))
              Text('${p['name']} · ${monthName((p.obj('from')?['month'] as num?)?.toInt())} → ${monthName((p.obj('to')?['month'] as num?)?.toInt())}, semana ${p.obj('to')?['week']}'),
            const SizedBox(height: 8),
            Text('Não estão na planilha (${pl('unlisted').length})', style: const TextStyle(fontWeight: FontWeight.w600)),
            if (pl('unlisted').isEmpty) const Text('—'),
            for (final p in pl('unlisted')) Text('${p['name']}'),
            if (pl('unlisted').isNotEmpty)
              Text(_options['deactivateUnlistedPles'] == true ? 'Serão desativados (episódios apagados).' : 'Ficam como estão.', style: Theme.of(context).textTheme.bodySmall),
          ],
          if (fuzzy.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('Nomes corrigidos por semelhança (${fuzzy.length}) — confira'),
              children: [for (final f in fuzzy) Align(alignment: Alignment.centerLeft, child: Text('“${f['from']}” → ${f['to']}'))],
            ),
          if (ignored.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text('Ignorado: ${ignored.join(', ')}.', style: Theme.of(context).textTheme.bodySmall)),
          if (skipped.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Não encontrados (não criados): ${skipped.join(', ')}.', style: Theme.of(context).textTheme.bodySmall)),
          const SizedBox(height: 16),
          BusyButton(label: 'Importar', icon: Icons.check, onPressed: _busy ? null : _apply),
          const SizedBox(height: 4),
          Text('Rodar de novo é seguro: o que já foi importado não é duplicado.', style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }
}
