import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../core/providers.dart';
import '../core/theme.dart';
import '../resources/resources.dart';
import 'icons.dart';

/// Página padrão: AppBar + menu lateral com o mesmo agrupamento do web.
class AppPage extends ConsumerWidget {
  const AppPage({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.fab,
    this.subtitle,
    this.bottom,
    this.showBack = false,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget> actions;
  final Widget? fab;
  final PreferredSizeWidget? bottom;
  final bool showBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: !showBack,
      leading: showBack
          ? BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/dashboard'))
          : null,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, overflow: TextOverflow.ellipsis),
          if (subtitle != null)
            Text(subtitle!, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
        ],
      ),
      actions: actions,
      bottom: bottom,
    ),
    drawer: showBack ? null : const AppDrawer(),
    floatingActionButton: fab,
    body: body,
  );
}

class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  void _go(BuildContext context, String path) {
    Navigator.pop(context);
    context.go(path);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final universes = ref.watch(universesProvider).value ?? const [];
    final selected = ref.watch(selectedUniverseProvider);
    final universeName = universes.where((u) => u['id'] == selected).map((u) => u['name'] as String).firstOrNull;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final path = GoRouterState.of(context).uri.path;

    Widget item(IconData icon, String label, String to) => ListTile(
      leading: Icon(icon),
      title: Text(label),
      selected: path == to,
      dense: true,
      onTap: () => _go(context, to),
    );

    return Drawer(
      child: SafeArea(
        child: ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.public),
              title: Text(universeName ?? 'Selecione um universe'),
              subtitle: Text(user?['email'] as String? ?? ''),
              trailing: const Icon(Icons.swap_horiz),
              onTap: () => _go(context, '/universes'),
            ),
            const Divider(),
            item(Icons.dashboard_outlined, 'Início', '/dashboard'),
            item(Icons.calendar_month, 'Episódios e cards', '/episodes'),
            item(Icons.leaderboard, 'Divisões (ranking)', '/divisions'),
            item(Icons.workspace_premium, 'Estatísticas de reinados', '/stats/reigns'),
            for (final g in groups)
              ExpansionTile(
                title: Text(g),
                dense: true,
                initiallyExpanded: resources.values.any((r) => r.group == g && path == '/r/${r.key}'),
                children: [
                  for (final r in resources.values.where((r) => r.group == g))
                    item(iconFor(r.key), r.key == 'episodes' ? 'Episódios (cadastro)' : r.plural, '/r/${r.key}'),
                ],
              ),
            const Divider(),
            item(Icons.upload_file, 'Importar planilha', '/import'),
            ListTile(
              leading: Icon(dark ? Icons.light_mode : Icons.dark_mode),
              title: Text(dark ? 'Tema claro' : 'Tema escuro'),
              dense: true,
              onTap: () => ref.read(themeModeProvider.notifier).toggle(Theme.of(context).brightness),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sair'),
              dense: true,
              onTap: () async {
                Navigator.pop(context);
                await ref.read(authProvider.notifier).logout();
              },
            ),
          ],
        ),
      ),
    );
  }
}
