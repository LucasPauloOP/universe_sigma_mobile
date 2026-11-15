import 'package:material_ui/material_ui.dart';

/// Ícone de cada recurso no menu e nas listas.
IconData iconFor(String key) => switch (key) {
      'wrestlers' => Icons.person,
      'teams' => Icons.groups,
      'brands' => Icons.tv,
      'rivalries' => Icons.bolt,
      'card-divisions' => Icons.tune,
      'alignments' => Icons.balance,
      'divisions' => Icons.grid_view,
      'weight-classes' => Icons.fitness_center,
      'titles' => Icons.emoji_events,
      'title-reigns' => Icons.military_tech,
      'title-baselines' => Icons.history,
      'seasons' => Icons.event,
      'shows' => Icons.videocam,
      'episodes' => Icons.calendar_month,
      'match-types' => Icons.sell,
      'tournaments' => Icons.account_tree,
      _ => Icons.list,
    };

IconData rowActionIcon(String name) => switch (name) {
      'chart' => Icons.bar_chart,
      'history' => Icons.history,
      'list' => Icons.view_list,
      'sitemap' => Icons.account_tree,
      _ => Icons.chevron_right,
    };
