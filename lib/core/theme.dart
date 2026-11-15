import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'providers.dart';

const _kDark = 'universe-sigma:dark';

/// Claro/escuro/sistema, lembrado entre sessões (mesma chave lógica do web).
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final v = ref.read(sharedPrefsProvider).getString(_kDark);
    return switch (v) { 'dark' => ThemeMode.dark, 'light' => ThemeMode.light, _ => ThemeMode.system };
  }

  Future<void> toggle(Brightness current) async {
    state = current == Brightness.dark ? ThemeMode.light : ThemeMode.dark;
    await ref
        .read(sharedPrefsProvider)
        .setString(_kDark, state == ThemeMode.dark ? 'dark' : 'light');
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

ThemeData buildTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF10B981), brightness: b); // emerald
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    appBarTheme: const AppBarTheme(centerTitle: false),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    cardTheme: const CardThemeData(margin: EdgeInsets.zero),
  );
}

/// Cor da borda de um episódio por status: realizado verde, planejado amarelo, sem planejamento vermelho.
const statusColors = {
  'DONE': Color(0xFF22C55E),
  'PLANNED': Color(0xFFEAB308),
  'UNPLANNED': Color(0xFFEF4444),
};
Color statusColor(String? s) => statusColors[s] ?? const Color(0xFF94A3B8);
