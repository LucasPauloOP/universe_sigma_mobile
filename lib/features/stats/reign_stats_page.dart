import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/reign_logic.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui.dart';
import '../resources/field_widgets.dart';

/// Estatísticas de reinados (`GET stats/titles`).
final reignStatsProvider = FutureProvider<Entity>((ref) async {
  ref.watch(selectedUniverseProvider);
  return Map<String, dynamic>.from(await ref.watch(apiProvider).get('stats/titles') as Map);
});

class ReignStatsPage extends ConsumerStatefulWidget {
  const ReignStatsPage({super.key});
  @override
  ConsumerState<ReignStatsPage> createState() => _ReignStatsPageState();
}

class _ReignStatsPageState extends ConsumerState<ReignStatsPage> {
  bool _byTitle = true;
  String? _titleId;
  final _open = <String>{};

  Future<void> _importHistory() async {
    try {
      final r = await ref.read(apiProvider).post('title-baselines/defaults') as Map;
      ref.invalidate(reignStatsProvider);
      if (!mounted) return;
      final created = (r['created'] as num?)?.toInt() ?? 0;
      showInfo(context, created > 0 ? '$created históricos importados' : 'O histórico padrão já está cadastrado');
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _toggle(String k) => setState(() => _open.contains(k) ? _open.remove(k) : _open.add(k));

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(reignStatsProvider);
    return AppPage(
      title: 'Estatísticas de reinados',
      subtitle: async.value != null ? 'Contado até ${fmtDate(async.value!['asOf'] as String?)} (último episódio realizado)' : null,
      actions: [
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'import') {
              _importHistory();
            } else {
              context.push(v);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'import', child: Text('Importar histórico padrão')),
            PopupMenuItem(value: '/r/title-baselines', child: Text('Histórico anterior')),
            PopupMenuItem(value: '/r/title-reigns', child: Text('Reinados')),
          ],
        ),
      ],
      body: AsyncBody<Entity>(
        value: async,
        onRetry: () => ref.invalidate(reignStatsProvider),
        builder: (d) {
          final titles = d.list('titles');
          if (titles.isEmpty) {
            return const EmptyState('Ainda não há reinados para analisar.\nCadastre o histórico anterior ou os reinados do universe.', icon: Icons.bar_chart);
          }
          final current = titles.where((t) => t.obj('title')?['id'] == _titleId).firstOrNull ?? titles.first;
          return RefreshIndicator(
            onRefresh: () => ref.refresh(reignStatsProvider.future),
            child: ListView(padding: const EdgeInsets.all(12), children: [
              for (final h in highlightsOf(titles))
                Card(
                  child: ListTile(
                    leading: Icon(h.label.contains('dias') ? Icons.schedule : (h.label.contains('reinados') ? Icons.tag : Icons.emoji_events)),
                    title: Text(h.value, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${h.label} · ${h.detail}'),
                  ),
                ),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [ButtonSegment(value: true, label: Text('Por título')), ButtonSegment(value: false, label: Text('Por lutador'))],
                selected: {_byTitle},
                onSelectionChanged: (s) => setState(() => _byTitle = s.first),
              ),
              const SizedBox(height: 12),
              if (_byTitle) ..._byTitleView(titles, current) else ..._byWrestlerView(titles),
              const SizedBox(height: 32),
            ]),
          );
        },
      ),
    );
  }

  List<Widget> _byTitleView(List<Entity> titles, Entity current) {
    final holders = current.list('holders');
    final top = holders.take(10).toList();
    final maxDays = top.fold<int>(1, (m, h) => ((h['days'] as num?)?.toInt() ?? 0) > m ? (h['days'] as num).toInt() : m);
    final scheme = Theme.of(context).colorScheme;
    final id = current.obj('title')?['id'] as String?;
    return [
      PickerField(
        label: 'Título',
        required: true,
        value: id,
        choices: [for (final t in titles) Choice(t.obj('title')!['id'] as String, t.obj('title')!['name'] as String)],
        onChanged: (v) => setState(() => _titleId = v as String?),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Dias com o cinturão (top 10)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final h in top)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  SizedBox(width: 110, child: Text(h['name'] as String, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: ((h['days'] as num?) ?? 0) / maxDays, minHeight: 14, color: scheme.primary, backgroundColor: scheme.surfaceContainerHighest),
                    ),
                  ),
                  SizedBox(width: 56, child: Text(fmtInt((h['days'] as num?)?.toInt() ?? 0), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
                ]),
              ),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      Card(
        child: Column(children: [
          for (var i = 0; i < holders.length; i++) _holderTile(id ?? '', i, holders[i]),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('“Maior reinado” considera só reinados com data; o histórico anterior entra apenas como total.',
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ]),
      ),
    ];
  }

  Widget _holderTile(String titleId, int i, Entity h) {
    final key = '$titleId${h['key']}';
    final baselineReigns = (h['baselineReigns'] as num?)?.toInt() ?? 0;
    final reignList = h.list('reignList');
    final hasDetail = reignList.isNotEmpty || baselineReigns > 0;
    final open = _open.contains(key);
    final longest = h['longestDays'] as num?;
    return Column(children: [
      ListTile(
        dense: true,
        leading: Text('${i + 1}', style: Theme.of(context).textTheme.bodySmall),
        title: Row(children: [
          Flexible(child: Text(h['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
          if (h['isCurrent'] == true) const Padding(padding: EdgeInsets.only(left: 6), child: Chip(label: Text('Atual', style: TextStyle(fontSize: 10)), visualDensity: VisualDensity.compact, padding: EdgeInsets.zero)),
        ]),
        subtitle: Text('${h['reigns']}x · ${fmtInt((h['days'] as num).toInt())} dias · maior: ${longest == null ? '—' : fmtInt(longest.toInt())}'),
        trailing: hasDetail ? Icon(open ? Icons.expand_less : Icons.expand_more) : null,
        onTap: hasDetail ? () => _toggle(key) : null,
      ),
      if (open)
        Padding(
          padding: const EdgeInsets.fromLTRB(56, 0, 16, 8),
          child: Column(children: [
            if (baselineReigns > 0)
              _detailRow('Antes do universe${(h['baselineNote'] as String?)?.isNotEmpty == true ? ' — ${h['baselineNote']}' : ''}',
                  '$baselineReigns reinado(s) · ${fmtInt((h['baselineDays'] as num?)?.toInt() ?? 0)} dias'),
            for (var n = 0; n < reignList.length; n++)
              _detailRow(
                'Reinado #${baselineReigns + n + 1} · ${fmtDate(reignList[n]['startDate'] as String?)} → ${reignList[n]['endDate'] != null ? fmtDate(reignList[n]['endDate'] as String?) : 'atual'}',
                '${fmtInt((reignList[n]['days'] as num?)?.toInt() ?? 0)} dias',
              ),
          ]),
        ),
      const Divider(height: 1),
    ]);
  }

  Widget _detailRow(String left, String right) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(left, style: const TextStyle(fontSize: 12))),
          const SizedBox(width: 8),
          Text(right, style: Theme.of(context).textTheme.bodySmall),
        ]),
      );

  List<Widget> _byWrestlerView(List<Entity> titles) {
    final all = overallOf(titles);
    return [
      Card(
        child: Column(children: [
          for (var i = 0; i < all.length; i++) ...[
            ListTile(
              dense: true,
              leading: Text('${i + 1}', style: Theme.of(context).textTheme.bodySmall),
              title: Text(all[i].name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${all[i].reigns}x · ${fmtInt(all[i].days)} dias'),
              trailing: Icon(_open.contains('o${all[i].key}') ? Icons.expand_less : Icons.expand_more),
              onTap: () => _toggle('o${all[i].key}'),
            ),
            if (_open.contains('o${all[i].key}'))
              Padding(
                padding: const EdgeInsets.fromLTRB(56, 0, 16, 8),
                child: Column(children: [
                  for (final t in all[i].titles)
                    _detailRow('${t.title}${t.current ? '  (atual)' : ''}', '${t.reigns}x · ${fmtInt(t.days)} dias'),
                ]),
              ),
            const Divider(height: 1),
          ],
        ]),
      ),
    ];
  }
}
