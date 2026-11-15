import 'package:flutter_test/flutter_test.dart';
import 'package:universe_sigma_mobile/core/models.dart';
import 'package:universe_sigma_mobile/core/tournament_logic.dart';

Entity w(String id, String name) => {'id': id, 'wrestlerId': id, 'wrestler': {'name': name}};

Entity match(String id, int round, int slot,
        {Entity? a, Entity? b, List<Entity> extras = const [], String? winnerId, Entity? winner, String? segmentId}) =>
    {
      'id': id, 'round': round, 'slot': slot,
      'entrantA': a, 'entrantB': b, 'entrantAId': a?.id, 'entrantBId': b?.id,
      'extras': [for (final x in extras) {'entrantId': x.id, 'entrant': x}],
      'winnerId': winnerId, 'winner': winner, 'segmentId': segmentId,
    };

void main() {
  final a = w('a', 'Ana'), b = w('b', 'Bia'), c = w('c', 'Cris'), d = w('d', 'Dani');

  test('nomes e competidores (A, B e extras) / versus', () {
    final m = match('m', 1, 1, a: a, b: b, extras: [c]);
    expect(competitorsOf(m).map(entrantName), ['Ana', 'Bia', 'Cris']);
    expect(versus(m), 'Ana x Bia x Cris');
    expect(versus(match('m', 1, 1, a: a)), 'Ana x a definir');
    expect(versus(match('m', 1, 1)), 'a definir');
    expect(entrantName({'team': {'name': 'Time'}}), 'Time');
  });

  group('rodadas', () {
    test('2 semis + final: nomes pela maior rodada existente', () {
      final rounds = roundsOf([
        match('f', 2, 1), match('s2', 1, 2, a: c, b: d), match('s1', 1, 1, a: a, b: b),
      ]);
      expect(rounds.map((r) => r.title), ['Semifinal', 'Final']);
      expect(rounds.first.matches.map((m) => m.id), ['s1', 's2']); // por slot
    });

    test('oitavas → quartas → semi → final com lutadores entrando depois', () {
      final matches = [
        for (var s = 2; s <= 8; s++) match('o$s', 1, s),
        for (var s = 1; s <= 4; s++) match('q$s', 2, s),
        match('s1', 3, 1), match('s2', 3, 2), match('f', 4, 1),
      ];
      final rounds = roundsOf(matches);
      expect(rounds.map((r) => r.title), ['Rodada 1', 'Quartas de final', 'Semifinal', 'Final']);
      expect(rounds.first.matches.length, 7); // a luta 1 saiu da chave
    });

    test('quantas lutas da rodada ainda não têm episódio', () {
      final r = roundsOf([match('1', 1, 1, segmentId: 's'), match('2', 1, 2), match('3', 1, 3)]).single;
      expect(r.unscheduled, 2);
    });

    test('campeão = vencedor da final', () {
      final rounds = roundsOf([match('s', 1, 1, a: a, b: b, winner: a), match('f', 2, 1, a: a, b: c, winner: a, winnerId: 'a')]);
      expect(entrantName(championOf(rounds)), 'Ana');
      expect(championOf(const []), isNull);
      expect(championOf(roundsOf([match('f', 1, 1)])), isNull);
    });
  });

  group('pontos corridos', () {
    test('grupos e classificação (vitórias, depois nome)', () {
      final matches = [
        match('1', 1, 1, a: a, b: b, winnerId: 'a')..['groupName'] = 'Grupo A',
        match('2', 1, 2, a: a, b: c, winnerId: 'c')..['groupName'] = 'Grupo A',
        match('3', 1, 3, a: b, b: c, winnerId: 'b'),
      ];
      expect(groupsOf(matches).keys, ['Grupo A', 'Grupo único']);
      final st = standingsOf([a, b, c], matches);
      // empatados em 1 vitória: desempata por nome
      expect(st.map((s) => '${s.name}:${s.wins}/${s.played}'), ['Ana:1/2', 'Bia:1/2', 'Cris:1/2']);
      // com líder claro, mais vitórias vem primeiro
      final lead = standingsOf([a, b, c], [
        match('1', 1, 1, a: c, b: a, winnerId: 'c'),
        match('2', 1, 2, a: c, b: b, winnerId: 'c'),
      ]);
      expect(lead.first.name, 'Cris');
      expect(lead.first.wins, 2);
    });
  });

  group('começa em rodada posterior', () {
    final t = {'format': 'SINGLE_ELIMINATION', 'size': 16, 'firstRoundMatches': 8};
    test('opções de rodada de entrada', () {
      final o = startRoundOptions(t);
      expect(o.length, 4);
      expect(o.first.$2, 'Desde o início (rodada 1)');
      expect(o.map((e) => e.$2).skip(1), ['Quartas de final', 'Semifinal', 'Final']);
    });
    test('texto do inscrito', () {
      expect(startsAt(t, {'startRound': 1}), '');
      expect(startsAt(t, {}), '');
      expect(startsAt(t, {'startRound': 2}), 'Quartas de final');
      expect(startsAt(t, {'startRound': 3}), 'Semifinal');
    });
    test('mini torneio: 2 triple threats + final', () {
      final mini = {'format': 'SINGLE_ELIMINATION', 'size': 6, 'firstRoundMatches': 2, 'firstRoundPerMatch': 3};
      expect(startRoundOptions(mini).map((e) => e.$1), [1, 2]);
    });
  });
}
