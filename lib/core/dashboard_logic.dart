import 'format.dart';
import 'models.dart';

/// Fila do que jogar: episódios planejados do mês de início do universe em diante,
/// por temporada e depois na ordem do jogo. Porte do cálculo do Dashboard do web.
List<Entity> upcomingEpisodes(List<Entity> planned, List<Entity> seasons, {int take = 4}) {
  final seasonOf = {for (final s in seasons) s.id: s};
  int seasonNumber(Entity e) => (seasonOf[e['seasonId']]?['number'] as num?)?.toInt() ?? 0;
  final list = planned
      .where((e) => !beforeStart(
            (e['month'] as num).toInt(),
            (seasonOf[e['seasonId']]?['startMonth'] as num?)?.toInt(),
          ))
      .toList()
    ..sort((a, b) {
      final d = seasonNumber(a) - seasonNumber(b);
      return d != 0 ? d : compareEpisodeEntities(a, b);
    });
  return list.take(take).toList();
}

/// "Segunda · Agosto · semana 1 · Noite 2"
String whenLabel(Entity e) {
  final parts = <String>[
    gameDayName(EpisodeLike.fromEntity(e)),
    monthName((e['month'] as num?)?.toInt()),
    if (e['week'] != null) 'semana ${e['week']}',
    if (e['night'] != null) 'Noite ${e['night']}',
  ];
  return parts.where((s) => s.isNotEmpty).join(' · ');
}

class CurrentChampion {
  const CurrentChampion(this.title, this.holders, this.since);
  final String title;
  final String holders;
  final String since;
}

/// Reinados em aberto (sem `endDate`), por título.
List<CurrentChampion> currentChampions(List<Entity> reigns) {
  final out = [
    for (final r in reigns.where((r) => r['endDate'] == null))
      CurrentChampion(
        r.obj('title')?['name'] as String? ?? '—',
        r
                .list('holders')
                .map((h) => (h.obj('wrestler')?['name'] ?? h.obj('team')?['name']) as String?)
                .whereType<String>()
                .join(' & ')
                .ifEmpty('—'),
        fmtDate(r['startDate'] as String?),
      ),
  ]..sort((a, b) => a.title.compareTo(b.title));
  return out;
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
