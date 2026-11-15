import 'format.dart';
import 'models.dart';

bool isWeekly(Entity e) => e.obj('show')?['kind'] == 'WEEKLY';

/// Episódios da temporada escolhida, na ordem de jogo (maio → abril).
List<Entity> episodesOfSeason(List<Entity> all, String? seasonId) =>
    all.where((e) => e['seasonId'] == seasonId).toList()..sort(compareEpisodeEntities);

/// Episódios que contam para o jogo (do mês de início em diante).
List<Entity> playableEpisodes(List<Entity> ofSeason, int startMonth) =>
    ofSeason.where((e) => !beforeStart((e['month'] as num).toInt(), startMonth)).toList();

/// O primeiro ainda planejado é o próximo a ser jogado.
String? nextEpisodeId(List<Entity> playable) =>
    playable.where((e) => e['status'] == 'PLANNED').firstOrNull?.id;

class MonthGroup {
  MonthGroup(this.month, this.episodes);
  final int month;
  final List<Entity> episodes;
  String get name => monthName(month);
  int get done => episodes.where((e) => e['status'] == 'DONE').length;
}

/// Episódios agrupados por mês da temporada (maio → abril), só os meses que têm episódio.
List<MonthGroup> groupByMonth(List<Entity> episodes, {required bool weekly, String? showId}) {
  final list = episodes.where((e) => isWeekly(e) == weekly && (showId == null || e['showId'] == showId));
  return [
    for (final m in seasonMonths)
      if (list.any((e) => e['month'] == m))
        MonthGroup(m, list.where((e) => e['month'] == m).toList()),
  ];
}

/// Meses do calendário (maio → abril) que têm episódios.
List<int> calendarMonths(List<Entity> episodes) =>
    [for (final m in seasonMonths) if (episodes.any((e) => e['month'] == m)) m];

/// 4 semanas × 7 dias (segunda a domingo): o mês do jogo sempre tem 4 semanas.
List<List<List<Entity>>> calendarRows(List<Entity> episodes, int month) {
  final rows = List.generate(4, (_) => List.generate(7, (_) => <Entity>[]));
  final inMonth = episodes.where((e) => e['month'] == month).toList()..sort(compareEpisodeEntities);
  for (final e in inMonth) {
    final like = EpisodeLike.fromEntity(e);
    rows[gameWeek((e['week'] as num?)?.toInt()) - 1][gameDayOffset(like)].add(e);
  }
  return rows;
}

/// Nome curto no calendário: "RAW" ou "WrestleMania · N1".
String calendarChip(Entity e) =>
    '${e.obj('show')?['name'] ?? 'Episódio'}${e['night'] != null ? ' · N${e['night']}' : ''}';

/// "Agosto · semana 1 · Noite 2"
String episodeWhen(Entity e) {
  final m = monthName((e['month'] as num?)?.toInt());
  final when = e['week'] != null ? '$m · semana ${e['week']}' : m;
  return e['night'] != null ? '$when · Noite ${e['night']}' : when;
}

/// Temporada em andamento: a primeira que ainda tem episódio não realizado; senão a última.
String? currentSeasonId(List<Entity> seasons, List<Entity> episodes) {
  if (seasons.isEmpty) return null;
  final sorted = [...seasons]..sort((a, b) => (a['number'] as num).compareTo(b['number'] as num));
  final current = sorted.where((s) => episodes.any((e) => e['seasonId'] == s.id && e['status'] != 'DONE')).firstOrNull;
  return (current ?? sorted.last).id;
}

/// Mês do último episódio realizado (na ordem de jogo); sem nenhum realizado, o do primeiro episódio.
int? lastDoneMonth(List<Entity> ordered) {
  final done = ordered.where((e) => e['status'] == 'DONE').lastOrNull;
  final ref = done ?? ordered.firstOrNull;
  return (ref?['month'] as num?)?.toInt();
}

/// Mês aberto por padrão entre [months] (os que têm episódio): o do último realizado; se esse
/// mês não existe na lista, o mais próximo antes dele; senão o primeiro.
int? defaultMonth(List<int> months, int? lastDone) {
  if (months.isEmpty) return null;
  if (lastDone == null) return months.first;
  final order = seasonMonths;
  final target = order.indexOf(lastDone);
  final before = months.where((m) => order.indexOf(m) <= target).toList()
    ..sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));
  return before.lastOrNull ?? months.first;
}
