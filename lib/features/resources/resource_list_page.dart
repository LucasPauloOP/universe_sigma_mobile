import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/api_exception.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../resources/resource_def.dart';
import '../../resources/resources.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/icons.dart';
import '../../shared/net_image.dart';
import '../../shared/ui.dart';
import 'activation.dart';
import 'field_widgets.dart';
import 'generate_episodes_sheet.dart';
import 'stats_dialogs.dart';

String _norm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[áàâãä]'), 'a')
    .replaceAll(RegExp('[éèêë]'), 'e')
    .replaceAll(RegExp('[íìîï]'), 'i')
    .replaceAll(RegExp('[óòôõö]'), 'o')
    .replaceAll(RegExp('[úùûü]'), 'u')
    .replaceAll('ç', 'c');

/// Lista genérica de um recurso: busca, filtros, ações por linha. Equivale ao ResourceList do web.
class ResourceListPage extends ConsumerStatefulWidget {
  const ResourceListPage({super.key, required this.resourceKey});
  final String resourceKey;

  @override
  ConsumerState<ResourceListPage> createState() => _ResourceListPageState();
}

class _ResourceListPageState extends ConsumerState<ResourceListPage> {
  String _search = '';
  final _filters = <String, Object?>{};

  Resource get res => resources[widget.resourceKey]!;

  @override
  void didUpdateWidget(covariant ResourceListPage old) {
    super.didUpdateWidget(old);
    if (old.resourceKey != widget.resourceKey) {
      _search = '';
      _filters.clear();
    }
  }

  String _name(String refKey, String? id) {
    if (id == null) return '';
    final e = ref.watch(itemsProvider(refKey)).value?.where((x) => x.id == id).firstOrNull;
    return e == null ? '' : (resources[refKey]?.label(e) ?? e['name'] as String? ?? '');
  }

  List<FieldDef> get _filterFields => [
        for (final k in res.filters) ?res.fields.where((f) => f.key == k).firstOrNull,
      ];

  List<Choice> _filterChoices(FieldDef f) {
    switch (f.type) {
      case FieldType.boolean:
        return const [Choice(true, 'Sim'), Choice(false, 'Não')];
      case FieldType.select:
        return [for (final o in f.options ?? const <Option>[]) Choice(o.value, o.label)];
      case FieldType.ref:
        final items = ref.watch(itemsProvider(f.ref!)).value ?? const <Entity>[];
        return [
          for (final e in items)
            if (f.refWhere == null || f.refWhere!(e)) Choice(e.id, resources[f.ref]?.label(e) ?? ''),
        ]..sort((a, b) => a.label.compareTo(b.label));
      default:
        return const [];
    }
  }

  List<(Entity, List<(String, String)>, String)> _rows(List<Entity> items) {
    final cols = res.columns.where((c) => c.type != ColumnType.image).toList();
    final out = <(Entity, List<(String, String)>, String)>[];
    for (final e in items) {
      final cells = <(String, String)>[];
      for (final c in cols) {
        final v = c.render != null ? c.render!(e, _name) : (e[c.key]?.toString() ?? '');
        cells.add((c.key, v));
      }
      out.add((e, cells, _norm([res.label(e), ...cells.map((c) => c.$2)].join(' '))));
    }
    return out;
  }

  Future<void> _openForm([Entity? e]) async {
    final saved = await context.push<bool>(e == null ? '/r/${res.key}/new' : '/r/${res.key}/${e.id}/edit');
    if (saved == true && mounted) showInfo(context, 'Salvo');
  }

  Future<void> _remove(Entity e) async {
    final ok = await confirm(
      context,
      title: 'Excluir ${res.singular.toLowerCase()}',
      message: 'Excluir "${res.label(e)}"? Registros ligados a ele podem ser afetados.',
      confirmLabel: 'Excluir',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(apiProvider).delete('${res.key}/${e.id}');
      invalidateItems(ref, [res.key]);
    } on ApiException catch (err) {
      if (mounted) showError(context, err);
    }
  }

  Future<void> _toggleActive(Entity e, bool active) async {
    final changed = await setActive(context, ref.read(apiProvider), res.key, e, active);
    if (changed) {
      invalidateItems(ref, [res.key, if (res.key == 'brands') ...['shows', 'card-divisions', 'episodes']]);
      if (mounted) showInfo(context, active ? 'Ativado' : 'Desativado');
    } else {
      invalidateItems(ref, [res.key]); // volta o switch
    }
  }

  void _runAction(RowAction a, Entity e) {
    switch (a.kind) {
      case RowActionKind.wrestlerRecord:
        WrestlerRecordSheet.show(context, e);
      case RowActionKind.titleHistory:
        TitleHistorySheet.show(context, e);
      case RowActionKind.episodeCard:
        context.push('/episodes/${e.id}/card');
      case RowActionKind.tournamentBracket:
        context.push('/tournaments/${e.id}');
    }
  }

  Future<void> _importHistory() async {
    try {
      final r = await ref.read(apiProvider).post('title-baselines/defaults') as Map;
      invalidateItems(ref, ['title-baselines', 'wrestlers', 'teams']);
      if (!mounted) return;
      final created = (r['created'] as num?)?.toInt() ?? 0;
      final extra = ((r['wrestlersCreated'] as num?) ?? 0) > 0 || ((r['teamsCreated'] as num?) ?? 0) > 0
          ? ' (${r['wrestlersCreated']} lutadores e ${r['teamsCreated']} duplas históricos criados como inativos)'
          : '';
      showInfo(context, created > 0 ? '$created históricos importados$extra' : 'Nada novo: o histórico padrão já está cadastrado');
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _generate() async {
    final n = await GenerateEpisodesSheet.show(context);
    if (n == null || !mounted) return;
    showInfo(context, n > 0 ? '$n episódio(s) criado(s)' : 'Nenhum episódio novo: tudo já existia');
  }

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text('Filtros', style: Theme.of(ctx).textTheme.titleLarge)),
                TextButton(
                  onPressed: () {
                    setState(_filters.clear);
                    setSheet(() {});
                  },
                  child: const Text('Limpar'),
                ),
              ]),
              for (final f in _filterFields) ...[
                const SizedBox(height: 12),
                PickerField(
                  label: f.label,
                  choices: _filterChoices(f),
                  value: _filters[f.key],
                  onChanged: (v) {
                    setState(() => v == null ? _filters.remove(f.key) : _filters[f.key] = v);
                    setSheet(() {});
                  },
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Aplicar')),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(itemsProvider(res.key));
    // nomes de referências usados nas colunas/filtros (carregam em segundo plano)
    for (final f in _filterFields.where((f) => f.type == FieldType.ref)) {
      ref.watch(itemsProvider(f.ref!));
    }
    if (res.key == 'episodes') ref.watch(itemsProvider('seasons'));

    final active = _filters.length;
    return AppPage(
      title: res.plural,
      actions: [
        if (res.toolbar == Toolbar.generateEpisodes)
          IconButton(tooltip: 'Gerar episódios', onPressed: _generate, icon: const Icon(Icons.bolt)),
        if (res.toolbar == Toolbar.importHistory)
          IconButton(tooltip: 'Importar histórico padrão', onPressed: _importHistory, icon: const Icon(Icons.download)),
        if (_filterFields.isNotEmpty)
          IconButton(
            tooltip: 'Filtros',
            onPressed: _openFilters,
            icon: Badge(isLabelVisible: active > 0, label: Text('$active'), child: const Icon(Icons.filter_list)),
          ),
      ],
      fab: FloatingActionButton(onPressed: _openForm, tooltip: 'Novo', child: const Icon(Icons.add)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar', isDense: true),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        Expanded(
          child: AsyncBody<List<Entity>>(
            value: items,
            onRetry: () => ref.invalidate(itemsProvider(res.key)),
            builder: (list) {
              final q = _norm(_search.trim());
              final rows = _rows(list).where((r) {
                for (final f in _filters.entries) {
                  if (r.$1[f.key] != f.value) return false;
                }
                return q.isEmpty || r.$3.contains(q);
              }).toList();
              final imageCol = res.columns.where((c) => c.type == ColumnType.image).firstOrNull;
              final switchCol = res.columns.where((c) => c.type == ColumnType.switchy).firstOrNull;
              return RefreshIndicator(
                onRefresh: () => ref.refresh(itemsProvider(res.key).future),
                child: rows.isEmpty
                    ? ListView(children: [
                        SizedBox(
                          height: 320,
                          child: EmptyState(list.isEmpty ? 'Nada cadastrado ainda.' : 'Nenhum resultado para os filtros.'),
                        ),
                      ])
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (ctx, i) => _tile(rows[i].$1, rows[i].$2, imageCol, switchCol),
                      ),
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _tile(Entity e, List<(String, String)> cells, ColumnDef? imageCol, ColumnDef? switchCol) {
    final subtitle = [
      for (final c in cells)
        if (c.$1 != 'name' && res.columns.firstWhere((x) => x.key == c.$1).type == ColumnType.text && c.$2.isNotEmpty)
          '${res.columns.firstWhere((x) => x.key == c.$1).label}: ${c.$2}',
    ].take(3).join('  ·  ');
    final chipCol = res.columns.where((c) => c.type == ColumnType.chips).firstOrNull;
    final chips = chipCol == null
        ? const <String>[]
        : (cells.where((c) => c.$1 == chipCol.key).firstOrNull?.$2 ?? '').split('|').where((s) => s.isNotEmpty).toList();
    final primary = res.rowActions.firstOrNull;
    final goesToDetail = primary != null &&
        (primary.kind == RowActionKind.episodeCard || primary.kind == RowActionKind.tournamentBracket);

    return ListTile(
      leading: imageCol != null
          ? NetImage(e[imageCol.key] as String?, fallback: iconFor(res.key))
          : CircleAvatar(child: Icon(iconFor(res.key), size: 20)),
      title: Text(res.label(e), maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (subtitle.isNotEmpty) Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        if (chips.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(spacing: 4, runSpacing: 0, children: [
              for (final c in chips.take(4)) Chip(label: Text(c), visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
              if (chips.length > 4) Chip(label: Text('+${chips.length - 4}'), visualDensity: VisualDensity.compact),
            ]),
          ),
      ]),
      isThreeLine: chips.isNotEmpty || subtitle.length > 50,
      onTap: () => goesToDetail ? _runAction(primary, e) : _openForm(e),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (switchCol != null)
          Switch(value: e[switchCol.key] == true, onChanged: (v) => _toggleActive(e, v)),
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'edit') {
              _openForm(e);
            } else if (v == 'delete') {
              _remove(e);
            } else {
              _runAction(res.rowActions[int.parse(v.substring(1))], e);
            }
          },
          itemBuilder: (_) => [
            for (var i = 0; i < res.rowActions.length; i++)
              PopupMenuItem(value: 'a$i', child: ListTile(leading: Icon(rowActionIcon(res.rowActions[i].icon)), title: Text(res.rowActions[i].label), dense: true, contentPadding: EdgeInsets.zero)),
            const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit), title: Text('Editar'), dense: true, contentPadding: EdgeInsets.zero)),
            const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Excluir'), dense: true, contentPadding: EdgeInsets.zero)),
          ],
        ),
      ]),
    );
  }
}
