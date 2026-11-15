import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/division_logic.dart';
import '../../core/models.dart';
import 'divisions_page.dart';

/// Ranking das divisões em folha modal, para consultar durante o planejamento
/// de um segmento. Somente leitura; [scheduledIds] destaca quem já está escalado.
class DivisionRankingSheet extends ConsumerStatefulWidget {
  const DivisionRankingSheet({super.key, this.brandId, this.scheduledIds = const {}});
  final String? brandId;
  final Set<String> scheduledIds;

  static Future<void> show(BuildContext context, {String? brandId, Set<String> scheduledIds = const {}}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => DivisionRankingSheet(brandId: brandId, scheduledIds: scheduledIds),
      );

  @override
  ConsumerState<DivisionRankingSheet> createState() => _DivisionRankingSheetState();
}

class _DivisionRankingSheetState extends ConsumerState<DivisionRankingSheet> {
  String? _brandId;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(divisionsBoardProvider);
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Não foi possível carregar o ranking.'),
            TextButton(onPressed: () => ref.invalidate(divisionsBoardProvider), child: const Text('Tentar de novo')),
          ]),
        ),
        data: (all) {
          final brands = brandOptions(all);
          final pick = _brandId ?? widget.brandId;
          final brandId = brands.any((b) => b.id == pick) ? pick : brands.firstOrNull?.id;
          final visible = visibleDivisions(all, brandId);
          return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
            Text('Ranking das divisões', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (brands.isNotEmpty)
              Wrap(spacing: 8, children: [
                for (final b in brands)
                  ChoiceChip(label: Text(b.name), selected: b.id == brandId, onSelected: (_) => setState(() => _brandId = b.id)),
              ]),
            if (visible.isEmpty)
              const Padding(padding: EdgeInsets.only(top: 24), child: Text('Nenhuma divisão ativa nesta marca.')),
            for (final d in visible)
              Card(
                margin: const EdgeInsets.only(top: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(d['name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    if (d.obj('title') != null) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 2, bottom: 6),
                        child: Text(d.obj('title')!['name'] as String? ?? '', style: Theme.of(context).textTheme.bodySmall),
                      ),
                      if (d.list('champions').isEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
                          child: const Row(children: [Icon(Icons.workspace_premium, size: 18), SizedBox(width: 8), Text('Título vago')]),
                        ),
                      for (final c in d.list('champions'))
                        Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: isChampionScheduled(c, widget.scheduledIds) ? scheme.primary : scheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Builder(builder: (_) {
                            final fg = isChampionScheduled(c, widget.scheduledIds) ? scheme.onPrimary : scheme.onTertiaryContainer;
                            return Row(children: [
                              Icon(Icons.workspace_premium, size: 18, color: fg),
                              const SizedBox(width: 8),
                              Expanded(child: Text(c['name'] as String? ?? '', style: TextStyle(fontWeight: FontWeight.w700, color: fg))),
                              Text('Campeão', style: TextStyle(fontSize: 12, color: fg)),
                            ]);
                          }),
                        ),
                      const SizedBox(height: 6),
                    ],
                    for (final (i, e) in d.list('entries').indexed)
                      Container(
                        margin: const EdgeInsets.only(top: 3),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: isEntryScheduled(e, widget.scheduledIds)
                              ? scheme.primaryContainer
                              : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(children: [
                          SizedBox(width: 24, child: Text('${i + 1}', textAlign: TextAlign.right)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(entryName(e), style: TextStyle(fontWeight: i == 0 ? FontWeight.w600 : null))),
                          if (isChampion(d, e)) const Icon(Icons.workspace_premium, size: 18),
                        ]),
                      ),
                    if (d.list('entries').isEmpty) const Text('Ninguém na divisão.'),
                  ]),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
