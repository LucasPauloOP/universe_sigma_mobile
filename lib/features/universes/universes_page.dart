import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui.dart';

class UniversesPage extends ConsumerWidget {
  const UniversesPage({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, [Entity? u]) async {
    final name = TextEditingController(text: u?['name'] as String? ?? '');
    final desc = TextEditingController(text: u?['description'] as String? ?? '');
    var template = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(u == null ? 'Novo universe' : 'Editar universe'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, maxLength: 100, decoration: const InputDecoration(labelText: 'Nome *')),
              const SizedBox(height: 8),
              TextField(controller: desc, maxLength: 500, maxLines: 3, decoration: const InputDecoration(labelText: 'Descrição')),
              if (u == null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Começar com elenco e títulos padrão'),
                  value: template,
                  onChanged: (v) => setState(() => template = v),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty || !context.mounted) return;
    final api = ref.read(apiProvider);
    try {
      if (u == null) {
        final created = await api.post('/universes', body: {
          'name': name.text.trim(),
          if (desc.text.trim().isNotEmpty) 'description': desc.text.trim(),
          'useTemplate': template,
        });
        ref.invalidate(universesProvider);
        await ref.read(selectedUniverseProvider.notifier).select(created['id'] as String);
        if (context.mounted) showInfo(context, 'Universe criado');
      } else {
        await api.put('/universes/${u.id}', body: {
          'name': name.text.trim(),
          'description': desc.text.trim().isEmpty ? null : desc.text.trim(),
        });
        ref.invalidate(universesProvider);
      }
    } on ApiException catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _reset(BuildContext context, WidgetRef ref, Entity u) async {
    final ok = await confirm(
      context,
      title: 'Restaurar padrão',
      message: 'Isso APAGA todos os dados de "${u['name']}" e recria o elenco, os títulos e os shows padrão. Não dá para desfazer.',
      confirmLabel: 'Restaurar',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(apiProvider).post('/universes/${u.id}/reset', body: {'confirm': true});
      // ids foram recriados: descarta as listas em cache
      ref.invalidate(itemsProvider);
      if (context.mounted) showInfo(context, 'Universe restaurado para o padrão');
    } on ApiException catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, Entity u) async {
    final ok = await confirm(
      context,
      title: 'Excluir universe',
      message: 'Excluir "${u['name']}" e todos os seus dados? Não dá para desfazer.',
      confirmLabel: 'Excluir',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(apiProvider).delete('/universes/${u.id}');
      ref.invalidate(universesProvider);
    } on ApiException catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final universes = ref.watch(universesProvider);
    final selected = ref.watch(selectedUniverseProvider);
    return AppPage(
      title: 'Meus universes',
      subtitle: 'Cada universe é um save independente do jogo.',
      fab: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Novo universe'),
      ),
      body: AsyncBody<List<Entity>>(
        value: universes,
        onRetry: () => ref.invalidate(universesProvider),
        builder: (list) => list.isEmpty
            ? const EmptyState('Você ainda não tem nenhum universe. Crie o primeiro!')
            : RefreshIndicator(
                onRefresh: () => ref.refresh(universesProvider.future),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (ctx, i) {
                    final u = list[i];
                    final current = u.id == selected;
                    return Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: current ? Theme.of(ctx).colorScheme.primary : Theme.of(ctx).colorScheme.outlineVariant,
                          width: current ? 2 : 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(
                              child: Text(u['name'] as String, style: Theme.of(ctx).textTheme.titleLarge),
                            ),
                            if (current) const Chip(label: Text('Em uso')),
                            PopupMenuButton<String>(
                              onSelected: (v) => switch (v) {
                                'edit' => _edit(ctx, ref, u),
                                'reset' => _reset(ctx, ref, u),
                                _ => _remove(ctx, ref, u),
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'edit', child: Text('Editar')),
                                PopupMenuItem(value: 'reset', child: Text('Restaurar padrão')),
                                PopupMenuItem(value: 'delete', child: Text('Excluir')),
                              ],
                            ),
                          ]),
                          Text('Criado em ${fmtDate(u['createdAt'] as String?)}', style: Theme.of(ctx).textTheme.bodySmall),
                          const SizedBox(height: 8),
                          Text((u['description'] as String?)?.isNotEmpty == true ? u['description'] as String : 'Sem descrição'),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: current
                                ? FilledButton(onPressed: () => ctx.go('/dashboard'), child: const Text('Abrir painel'))
                                : OutlinedButton(
                                    onPressed: () async {
                                      await ref.read(selectedUniverseProvider.notifier).select(u.id);
                                      if (ctx.mounted) ctx.go('/dashboard');
                                    },
                                    child: const Text('Usar este'),
                                  ),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
