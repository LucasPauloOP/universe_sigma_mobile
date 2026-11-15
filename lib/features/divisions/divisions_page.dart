import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/api_exception.dart';
import '../../core/division_logic.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui.dart';
import '../resources/field_widgets.dart';

/// Quadro de divisões (`GET card-divisions/board`).
final divisionsBoardProvider = FutureProvider<List<Entity>>((ref) async {
  ref.watch(selectedUniverseProvider);
  final d = await ref.watch(apiProvider).get('card-divisions/board') as List;
  return d.map((e) => Map<String, dynamic>.from(e as Map)).toList();
});

class DivisionsPage extends ConsumerStatefulWidget {
  const DivisionsPage({super.key});
  @override
  ConsumerState<DivisionsPage> createState() => _DivisionsPageState();
}

class _DivisionsPageState extends ConsumerState<DivisionsPage> {
  String? _brandId;
  bool _saving = false;
  // ordem otimista por divisão enquanto salva
  final _local = <String, List<Entity>>{};

  Future<void> _reload() async {
    _local.clear();
    ref.invalidate(divisionsBoardProvider);
    await ref.read(divisionsBoardProvider.future);
  }

  Future<void> _save(Entity d, List<String> keys) async {
    setState(() => _saving = true);
    try {
      await ref.read(apiProvider).put('card-divisions/${d.id}/entries', body: {'entries': entriesBody(keys)});
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
      await _reload(); // volta ao estado do servidor
    }
  }

  Future<void> _reorder(Entity d, int from, int to) async {
    final entries = [...(_local[d.id] ?? d.list('entries'))];
    entries.insert(to, entries.removeAt(from));
    setState(() => _local[d.id] = entries);
    await _save(d, entries.map(entryKey).toList());
  }

  Future<void> _createDefaults() async {
    try {
      final res = await ref.read(apiProvider).post('card-divisions/defaults') as Map;
      final n = (res['created'] as num?)?.toInt() ?? 0;
      if (mounted) showInfo(context, n > 0 ? '$n divisões criadas' : 'Nada a criar: todas as divisões padrão já existem');
      await _reload();
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _editChampion(Entity d) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ChampionSheet(division: d),
    );
    if (ok == true) {
      await _reload();
      if (mounted) showInfo(context, 'Campeão atualizado');
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(divisionsBoardProvider);
    return AppPage(
      title: 'Divisões',
      subtitle: 'O campeão fica acima; o 1º da lista é o próximo desafiante.',
      actions: [
        PopupMenuButton<String>(
          onSelected: (v) => v == 'defaults' ? _createDefaults() : context.push('/r/card-divisions'),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'defaults', child: Text('Criar divisões padrão')),
            PopupMenuItem(value: 'config', child: Text('Configurar divisões')),
          ],
        ),
      ],
      body: AsyncBody<List<Entity>>(
        value: async,
        onRetry: _reload,
        builder: (all) {
          if (all.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const EmptyState('Ainda não há divisões.\nCrie as padrão ou cadastre as suas em “Configurar”.', icon: Icons.format_list_numbered),
                FilledButton.icon(onPressed: _createDefaults, icon: const Icon(Icons.bolt), label: const Text('Criar divisões padrão')),
              ]),
            );
          }
          final brands = brandOptions(all);
          final brandId = brands.any((b) => b.id == _brandId) ? _brandId : brands.firstOrNull?.id;
          final visible = visibleDivisions(all, brandId);
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(padding: const EdgeInsets.all(12), children: [
              if (_saving) const LinearProgressIndicator(),
              if (brands.length > 1)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final b in brands) ...[
                      ChoiceChip(label: Text(b.name), selected: b.id == brandId, onSelected: (_) => setState(() => _brandId = b.id)),
                      const SizedBox(width: 8),
                    ],
                  ]),
                ),
              const SizedBox(height: 8),
              for (final d in visible) _DivisionCard(
                division: d,
                entries: _local[d.id] ?? d.list('entries'),
                onReorder: (a, b) => _reorder(d, a, b),
                onSave: (keys) => _save(d, keys),
                onChampion: () => _editChampion(d),
              ),
              const SizedBox(height: 48),
            ]),
          );
        },
      ),
    );
  }
}

class _DivisionCard extends ConsumerWidget {
  const _DivisionCard({required this.division, required this.entries, required this.onReorder, required this.onSave, required this.onChampion});
  final Entity division;
  final List<Entity> entries;
  final void Function(int from, int to) onReorder;
  final ValueChanged<List<String>> onSave;
  final VoidCallback onChampion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final d = division;
    final wrestlers = ref.watch(itemsProvider('wrestlers')).value ?? const <Entity>[];
    final teams = ref.watch(itemsProvider('teams')).value ?? const <Entity>[];
    final opts = pickerOptions(d, wrestlers, teams);
    final tagFirst = isTagDivision(d);
    final choices = [
      if (tagFirst) ...opts.teams.map((o) => Choice(o.key, '${o.name}  (dupla/facção)')),
      ...opts.wrestlers.map((o) => Choice(o.key, o.name)),
      if (!tagFirst) ...opts.teams.map((o) => Choice(o.key, '${o.name}  (dupla/facção)')),
    ];
    final keys = entries.map(entryKey).toList();
    final champions = d.list('champions');
    final since = d['championSince'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(d['name'] as String, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Wrap(spacing: 6, children: [
            Chip(label: Text(genderLabel(d)), visualDensity: VisualDensity.compact),
            if (d.list('brands').length > 1) const Chip(label: Text('Todos os shows'), avatar: Icon(Icons.share, size: 14), visualDensity: VisualDensity.compact),
          ]),
          Text(d.obj('title') != null ? '🏆 ${d.obj('title')!['name']}' : 'Sem título vinculado', style: Theme.of(context).textTheme.bodySmall),
          if (d.obj('title') != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('CAMPEÃO', style: TextStyle(fontSize: 11, color: scheme.onPrimary.withValues(alpha: 0.8))),
                    Text(champions.isEmpty ? 'Vago' : championLabel(d), style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.bold)),
                    if (since != null && champions.isNotEmpty)
                      Text('desde ${fmtDate(since)}', style: TextStyle(fontSize: 11, color: scheme.onPrimary.withValues(alpha: 0.8))),
                  ]),
                ),
                IconButton(tooltip: 'Alterar campeão', onPressed: onChampion, icon: Icon(Icons.edit, color: scheme.onPrimary)),
              ]),
            ),
          ],
          const SizedBox(height: 8),
          if (entries.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Ninguém na divisão ainda.'))
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: entries.length,
              onReorderItem: onReorder,
              itemBuilder: (ctx, i) {
                final e = entries[i];
                final champ = isChampion(d, e);
                return Container(
                  key: ValueKey(e.id),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
                  child: Opacity(
                    opacity: champ ? 0.6 : 1,
                    child: Row(children: [
                      ReorderableDragStartListener(index: i, child: const Padding(padding: EdgeInsets.all(10), child: Icon(Icons.drag_handle, size: 18))),
                      SizedBox(width: 22, child: Text('${i + 1}', textAlign: TextAlign.right, style: Theme.of(context).textTheme.bodySmall)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(entryName(e), style: TextStyle(fontWeight: i == 0 ? FontWeight.bold : FontWeight.normal), overflow: TextOverflow.ellipsis)),
                      if (champ) const Padding(padding: EdgeInsets.only(right: 4), child: Chip(label: Text('Campeão', style: TextStyle(fontSize: 10)), visualDensity: VisualDensity.compact, padding: EdgeInsets.zero)),
                      if (i > 0) IconButton(visualDensity: VisualDensity.compact, tooltip: 'Mover para o topo (desafiante)', icon: const Icon(Icons.keyboard_double_arrow_up, size: 18), onPressed: () => onSave(toTop(keys, entryKey(e)))),
                      IconButton(visualDensity: VisualDensity.compact, tooltip: 'Remover', icon: const Icon(Icons.close, size: 18), onPressed: () => onSave(keys.where((k) => k != entryKey(e)).toList())),
                    ]),
                  ),
                );
              },
            ),
          const SizedBox(height: 8),
          PickerField(
            label: 'Adicionar à divisão',
            value: null,
            choices: choices,
            onChanged: (v) {
              if (v != null) onSave([...keys, v as String]);
            },
          ),
        ]),
      ),
    );
  }
}

class _ChampionSheet extends ConsumerStatefulWidget {
  const _ChampionSheet({required this.division});
  final Entity division;

  @override
  ConsumerState<_ChampionSheet> createState() => _ChampionSheetState();
}

class _ChampionSheetState extends ConsumerState<_ChampionSheet> {
  String _mode = 'fix';
  late List<String> _wrestlerIds = [for (final c in widget.division.list('champions')) if (c['wrestlerId'] != null) c['wrestlerId'] as String];
  late String? _teamId = widget.division.list('champions').where((c) => c['teamId'] != null).map((c) => c['teamId'] as String).firstOrNull;
  bool _busy = false;

  bool get _isTag => isTagDivision(widget.division);

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).put(
            'card-divisions/${widget.division.id}/champion',
            body: championBody(_mode, teamId: _teamId, wrestlerIds: _wrestlerIds),
          );
      invalidateItems(ref, ['title-reigns']);
      ref.invalidate(divisionsBoardProvider);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.division;
    final gender = d['gender'] as String?;
    final wrestlers = [
      for (final w in ref.watch(itemsProvider('wrestlers')).value ?? const <Entity>[])
        if (gender == null || w['gender'] == null || w['gender'] == gender) Choice(w.id, w['name'] as String? ?? ''),
    ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    final teams = [
      for (final t in ref.watch(itemsProvider('teams')).value ?? const <Entity>[])
        if (t['kind'] != 'FACTION') Choice(t.id, t['name'] as String? ?? ''),
    ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    final valid = championValid(isTag: _isTag, teamId: _teamId, wrestlerIds: _wrestlerIds);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Campeão — ${d['name']}', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Título: ${d.obj('title')?['name']}${championLabel(d).isNotEmpty ? ' · campeão atual: ${championLabel(d)}' : ''}',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'fix', label: Text('Corrigir')), ButtonSegment(value: 'change', label: Text('Troca de título'))],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 6),
          Text(
            _mode == 'fix'
                ? 'Corrige quem é o campeão atual, mantendo o reinado em andamento (use para ajustar o universe ao seu).'
                : 'Registra uma troca de título: encerra o reinado atual e abre outro. O ex-campeão volta para o meio da fila.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          if (_isTag) ...[
            PickerField(
              label: 'Dupla campeã',
              value: _teamId,
              choices: teams,
              onChanged: (v) => setState(() {
                _teamId = v as String?;
                if (_teamId != null) _wrestlerIds = [];
              }),
            ),
            const SizedBox(height: 14),
            MultiPickerField(
              label: 'ou 2 lutadores',
              values: _wrestlerIds.cast<Object>(),
              choices: wrestlers,
              hint: 'Escolha exatamente 2',
              error: _teamId == null && _wrestlerIds.length == 1 ? 'Escolha 2 lutadores' : null,
              onChanged: (v) => setState(() {
                _wrestlerIds = v.cast<String>().take(2).toList();
                if (_wrestlerIds.isNotEmpty) _teamId = null;
              }),
            ),
          ] else
            PickerField(
              label: 'Campeão',
              value: _wrestlerIds.firstOrNull,
              choices: wrestlers,
              onChanged: (v) => setState(() => _wrestlerIds = v == null ? [] : [v as String]),
            ),
          const SizedBox(height: 8),
          Text('Deixe vazio para deixar o título vago.', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          BusyButton(label: 'Salvar campeão', icon: Icons.check, onPressed: _busy || !valid ? null : _save),
        ]),
      ),
    );
  }
}
