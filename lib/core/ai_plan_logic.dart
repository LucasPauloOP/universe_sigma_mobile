// Planejamento de cards com IA: regras puras (espelham `core/ai-plan.ts` do web).
// Os episódios sugeridos chegam da API como mapas (`GET/POST .../suggest*`) e voltam para
// `POST episodes/:id/segments` ou `POST episodes/segments/bulk` sem os campos de exibição.
import 'format.dart';
import 'models.dart';

/// Lados da luta, ordenados: [[nomes do lado 1], [nomes do lado 2]...].
List<List<String>> aiSides(Entity segment) {
  final bySide = <int, List<String>>{};
  for (final p in segment.list('participants')) {
    bySide.putIfAbsent((p['side'] as num).toInt(), () => []).add(p['wrestlerName'] as String? ?? '?');
  }
  final keys = bySide.keys.toList()..sort();
  return [for (final k in keys) bySide[k]!];
}

/// "A + B x C" para exibir.
String aiSidesText(Entity segment) => aiSides(segment).map((s) => s.join(' + ')).join(' x ');

/// Segmento no formato da API (sem `wrestlerName`).
Entity aiApiSegment(Entity segment) => {
  ...segment,
  'participants': [
    for (final p in segment.list('participants'))
      {'wrestlerId': p['wrestlerId'], 'side': p['side'], 'isWinner': p['isWinner'] == true},
  ],
};

/// Itens do `POST episodes/segments/bulk`: só os episódios marcados e com segmentos.
List<Entity> aiBulkItems(List<Entity> episodes, Set<String> selected, {required bool replace}) => [
  for (final e in episodes)
    if (selected.contains(e['episodeId']) && e.list('segments').isNotEmpty)
      {
        'episodeId': e['episodeId'],
        'replace': replace,
        'segments': [for (final s in e.list('segments')) aiApiSegment(s)],
      },
];

/// Episódio sem o segmento [index] (não altera o original).
Entity aiWithoutSegment(Entity episode, int index) {
  final segments = [...episode.list('segments')]..removeAt(index);
  return {...episode, 'segments': segments};
}

/// Posição no calendário do jogo (maio = 0 ... abril = 11, 4 semanas por mês).
int gameSlot(int month, int week) => seasonMonthIndex(month) * 4 + (week - 1);

/// O fim do período vem antes do início?
bool aiRangeInverted({required int fromMonth, required int fromWeek, required int toMonth, required int toWeek}) =>
    gameSlot(toMonth, toWeek) < gameSlot(fromMonth, fromWeek);

/// Corpo do `POST episodes/suggest-range`.
Entity aiRangeBody({
  required String seasonId,
  required int fromMonth,
  required int fromWeek,
  required int toMonth,
  required int toWeek,
  required int count,
  required bool includeMainEvent,
  required bool skipPlanned,
  List<String> showIds = const [],
  String guidance = '',
}) => {
  'seasonId': seasonId,
  'from': {'month': fromMonth, 'week': fromWeek},
  'to': {'month': toMonth, 'week': toWeek},
  'count': count,
  'includeMainEvent': includeMainEvent,
  'skipPlanned': skipPlanned,
  if (showIds.isNotEmpty) 'showIds': showIds,
  if (guidance.trim().isNotEmpty) 'guidance': guidance.trim(),
};

/// Progresso do job (0..1).
double aiProgress(Entity? job) {
  final total = (job?['total'] as num?)?.toInt() ?? 0;
  return total == 0 ? 0 : ((job?['done'] as num?)?.toInt() ?? 0) / total;
}
