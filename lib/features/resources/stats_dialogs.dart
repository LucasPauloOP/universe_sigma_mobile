import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../shared/ui.dart';

/// Retrospecto de um lutador (`GET wrestlers/:id/record`).
class WrestlerRecordSheet extends ConsumerWidget {
  const WrestlerRecordSheet({super.key, required this.wrestler});
  final Entity wrestler;

  static Future<void> show(BuildContext context, Entity w) => showModalBottomSheet(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => WrestlerRecordSheet(wrestler: w),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final future = ref.read(apiProvider).get('wrestlers/${wrestler.id}/record');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Retrospecto — ${wrestler['name']}', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        FutureBuilder(
          future: future,
          builder: (ctx, snap) {
            if (snap.hasError) return Text('${snap.error}');
            if (!snap.hasData) return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
            final r = snap.data as Map;
            final matches = (r['matches'] as num).toInt();
            final wins = (r['wins'] as num).toInt();
            final tiles = [
              ('Lutas', '$matches'),
              ('Vitórias', '$wins'),
              ('Derrotas', '${r['losses']}'),
              ('Empates', '${r['draws']}'),
              ('Reinados', '${r['titleReigns']}'),
              ('Aproveitamento', matches > 0 ? '${(wins / matches * 100).round()}%' : '—'),
            ];
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.3,
                children: [
                  for (final t in tiles)
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(t.$2, style: Theme.of(ctx).textTheme.headlineSmall),
                        Text(t.$1, style: Theme.of(ctx).textTheme.bodySmall),
                      ]),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Considera apenas lutas marcadas como realizadas.', style: Theme.of(ctx).textTheme.bodySmall),
            ]);
          },
        ),
      ]),
    );
  }
}

/// Histórico de reinados de um título (`GET titles/:id/history`).
class TitleHistorySheet extends ConsumerWidget {
  const TitleHistorySheet({super.key, required this.title});
  final Entity title;

  static Future<void> show(BuildContext context, Entity t) => showModalBottomSheet(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => TitleHistorySheet(title: t),
      );

  String _holders(Entity r) {
    final names = r
        .list('holders')
        .map((h) => (h.obj('wrestler')?['name'] ?? h.obj('team')?['name']) as String?)
        .whereType<String>();
    return names.isEmpty ? '—' : names.join(' & ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final future = ref.read(apiProvider).get('titles/${title.id}/history');
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Histórico — ${title['name']}', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Expanded(
            child: FutureBuilder(
              future: future,
              builder: (ctx, snap) {
                if (snap.hasError) return Text('${snap.error}');
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final reigns = ((snap.data as Map)['reigns'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
                if (reigns.isEmpty) return const EmptyState('Nenhum reinado registrado para este título.');
                return ListView.separated(
                  itemCount: reigns.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final r = reigns[i];
                    final end = r['endDate'] as String?;
                    return ListTile(
                      leading: CircleAvatar(child: Text('${i + 1}')),
                      title: Text(_holders(r)),
                      subtitle: Text('${fmtDate(r['startDate'] as String?)} → ${end != null ? fmtDate(end) : 'atual'}'),
                      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('${r['days']} dias'),
                        Text('${r['defenses']} defesas', style: Theme.of(ctx).textTheme.bodySmall),
                      ]),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
