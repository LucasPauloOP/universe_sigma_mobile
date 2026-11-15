import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/rivalry_logic.dart';

/// Rivalidades ativas em folha modal, para consultar ao planejar o card.
/// Somente leitura; [inCardIds] destaca as ligadas às lutas deste card.
class ActiveRivalriesSheet extends ConsumerWidget {
  const ActiveRivalriesSheet({super.key, this.inCardIds = const {}});
  final Set<String> inCardIds;

  static Future<void> show(BuildContext context, {Set<String> inCardIds = const {}}) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ActiveRivalriesSheet(inCardIds: inCardIds),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(itemsProvider('rivalries'));
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Não foi possível carregar as rivalidades.'),
              TextButton(
                onPressed: () => ref.invalidate(itemsProvider('rivalries')),
                child: const Text('Tentar de novo'),
              ),
            ],
          ),
        ),
        data: (all) {
          final active = [
            for (final r in all)
              if (r['isActive'] != false) r,
          ];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              Text('Rivalidades ativas (${active.length})', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (active.isEmpty)
                const Padding(padding: EdgeInsets.only(top: 24), child: Text('Nenhuma rivalidade ativa.')),
              for (final r in active)
                Builder(
                  builder: (_) {
                    final here = inCardIds.contains(r.id);
                    final fg = here ? scheme.onPrimary : scheme.onSurface;
                    final vs = rivalryVs(r);
                    return Card(
                      color: here ? scheme.primary : null,
                      margin: const EdgeInsets.only(top: 8),
                      child: ListTile(
                        title: Text(
                          vs.isEmpty ? (r['name'] as String? ?? '') : vs,
                          style: TextStyle(fontWeight: FontWeight.w600, color: fg),
                        ),
                        subtitle: Text(
                          [if (r['startDate'] != null) 'Desde ${r['startDate']}', if (here) 'neste card'].join(' · '),
                          style: TextStyle(color: fg.withValues(alpha: 0.8)),
                        ),
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}
