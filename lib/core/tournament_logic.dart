import 'format.dart';
import 'models.dart';

String entrantName(Entity? e) =>
    e == null ? '' : (e.obj('wrestler')?['name'] ?? e.obj('team')?['name'] ?? '?') as String;

/// Competidores da luta na ordem: A, B e os adicionais.
List<Entity> competitorsOf(Entity m) => [
      if (m.obj('entrantA') != null) m.obj('entrantA')!,
      if (m.obj('entrantB') != null) m.obj('entrantB')!,
      for (final x in m.list('extras'))
        if (x.obj('entrant') != null) x.obj('entrant')!,
    ];

/// "A x B x C" (ou "a definir" nas vagas vazias).
String versus(Entity m) {
  final names = competitorsOf(m).map(entrantName).toList();
  if (names.isEmpty) return 'a definir';
  return names.join(' x ') + (names.length < 2 ? ' x a definir' : '');
}

class Round {
  Round(this.round, this.title, this.matches);
  final int round;
  final String title;
  final List<Entity> matches;
  int get unscheduled => matches.where((m) => m['segmentId'] == null).length;
}

/// Rodadas da eliminatória em ordem. O nome usa a maior rodada que existe na chave
/// (Final/Semifinal/...), então funciona também com lutadores que entram em rodadas
/// posteriores.
List<Round> roundsOf(List<Entity> matches) {
  if (matches.isEmpty) return const [];
  final max = matches.map((m) => (m['round'] as num).toInt()).reduce((a, b) => a > b ? a : b);
  final byRound = <int, List<Entity>>{};
  for (final m in matches) {
    byRound.putIfAbsent((m['round'] as num).toInt(), () => []).add(m);
  }
  return [
    for (final e in (byRound.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
      Round(e.key, roundName(e.key, max), e.value..sort((a, b) => (a['slot'] as num).compareTo(b['slot'] as num))),
  ];
}

/// Pontos corridos: lutas agrupadas pelo nome do grupo.
Map<String, List<Entity>> groupsOf(List<Entity> matches) {
  final by = <String, List<Entity>>{};
  for (final m in matches) {
    by.putIfAbsent(m['groupName'] as String? ?? 'Grupo único', () => []).add(m);
  }
  return by;
}

class Standing {
  Standing(this.name, this.played, this.wins);
  final String name;
  final int played;
  final int wins;
}

/// Classificação dos pontos corridos: mais vitórias primeiro, depois ordem alfabética.
List<Standing> standingsOf(List<Entity> entrants, List<Entity> matches) {
  final list = [
    for (final e in entrants)
      () {
        final mine = matches.where((m) => m['entrantAId'] == e.id || m['entrantBId'] == e.id);
        return Standing(
          entrantName(e),
          mine.where((m) => m['winnerId'] != null).length,
          mine.where((m) => m['winnerId'] == e.id).length,
        );
      }(),
  ]..sort((a, b) => b.wins != a.wins ? b.wins - a.wins : a.name.compareTo(b.name));
  return list;
}

/// Campeão = vencedor da luta final (só eliminatória).
Entity? championOf(List<Round> rounds) =>
    rounds.isEmpty ? null : rounds.last.matches.firstOrNull?.obj('winner');

/// Em que rodadas um inscrito pode entrar: 1 = início; depois quartas, semis...
List<(int, String)> startRoundOptions(Entity tournament) {
  final total = totalRounds(RoundInfo.fromTournament(tournament));
  return [for (var i = 1; i <= total; i++) (i, i == 1 ? 'Desde o início (rodada 1)' : roundName(i, total))];
}

/// "Semifinal" quando o inscrito entra numa rodada posterior; vazio no início.
String startsAt(Entity tournament, Entity entrant) {
  final start = (entrant['startRound'] as num?)?.toInt() ?? 1;
  if (start < 2) return '';
  return roundName(start, totalRounds(RoundInfo.fromTournament(tournament)));
}
