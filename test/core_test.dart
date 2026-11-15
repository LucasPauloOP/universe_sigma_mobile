import 'package:flutter_test/flutter_test.dart';
import 'package:universe_sigma_mobile/core/format.dart';
import 'package:universe_sigma_mobile/core/segment_result.dart';

EpisodeLike weekly(String name, int weekday, int month, int? week) =>
    EpisodeLike(month: month, week: week, kind: 'WEEKLY', weekday: weekday, showName: name);

EpisodeLike ple(String name, int month, int? week, {String kind = 'PLE', int? night}) =>
    EpisodeLike(month: month, week: week, kind: kind, showName: name, night: night);

void main() {
  group('calendário da temporada (maio → abril)', () {
    test('maio é o primeiro mês e abril o último', () {
      expect(seasonMonths.first, 5);
      expect(seasonMonths.last, 4);
      expect(seasonMonthIndex(5), 0);
      expect(seasonMonthIndex(12), 7);
      expect(seasonMonthIndex(1), 8);
      expect(seasonMonthIndex(4), 11);
    });

    test('ordena como a planilha: RAW, SmackDown, depois o PLE da semana', () {
      final eps = [
        weekly('RAW', 1, 6, 1),
        ple('Bad Blood', 5, 4),
        weekly('SmackDown', 5, 5, 4),
        weekly('RAW', 1, 5, 4),
        weekly('RAW', 1, 1, 1), // janeiro vem depois de dezembro
        weekly('RAW', 1, 12, 2),
        ple('SNME', 5, 2, kind: 'SPECIAL'),
        weekly('SmackDown', 5, 5, 2),
      ]..sort(compareEpisodes);
      expect(eps.map((e) => '${e.month}/${e.week}/${e.showName}').toList(), [
        '5/2/SmackDown',
        '5/2/SNME',
        '5/4/RAW',
        '5/4/SmackDown',
        '5/4/Bad Blood',
        '6/1/RAW',
        '12/2/RAW',
        '1/1/RAW',
      ]);
    });

    test('episódios antes do mês de início ficam de fora', () {
      expect(beforeStart(6, 8), isTrue);
      expect(beforeStart(8, 8), isFalse);
      expect(beforeStart(1, 8), isFalse);
      expect(beforeStart(5, null), isFalse);
      expect(beforeStart(4, null), isFalse);
    });

    test('PLE em duas noites: noite 1 antes da 2, depois do semanal da semana', () {
      final eps = [
        ple('WrestleMania', 4, 3, night: 2),
        ple('WrestleMania', 4, 3, night: 1),
        weekly('SmackDown', 5, 4, 3),
      ]..sort(compareEpisodes);
      expect(eps.map((e) => e.night ?? 'smack').toList(), ['smack', 1, 2]);
    });
  });

  group('calendário do jogo (4 semanas por mês)', () {
    test('coluna = dia do show (segunda = 0); sem dia: semanal segunda, PLE sábado', () {
      int off(String kind, int? weekday, {int? night}) => gameDayOffset(
          EpisodeLike(month: 5, week: 1, kind: kind, weekday: weekday, night: night));
      expect(off('WEEKLY', 1), 0);
      expect(off('WEEKLY', 5), 4);
      expect(off('WEEKLY', 0), 6); // domingo
      expect(off('WEEKLY', null), 0);
      expect(gameDayName(const EpisodeLike(month: 5, kind: 'PLE')), 'Sábado');
      expect(gameDayName(const EpisodeLike(month: 5, kind: 'PLE', night: 2)), 'Domingo');
      expect(gameWeek(null), 4);
      expect(gameWeek(5), 4);
      expect(gameWeek(0), 1);
    });
  });

  group('rodadas de torneio', () {
    test('size potência de 2 usa lutas de 2', () {
      expect(totalRounds(const RoundInfo(size: 8)), 3);
      expect(totalRounds(const RoundInfo(size: 16)), 4);
    });

    test('2 triple threats + final (size 6 ou firstRoundMatches 2)', () {
      expect(totalRounds(const RoundInfo(size: 6)), 2);
      expect(totalRounds(const RoundInfo(size: 6, firstRoundMatches: 2)), 2);
      expect(roundName(1, 2), 'Semifinal');
      expect(roundName(2, 2), 'Final');
    });

    test('oitavas → quartas → semi → final', () {
      const t = RoundInfo(size: 16, firstRoundMatches: 8);
      expect(totalRounds(t), 4);
      expect([for (var r = 1; r <= 4; r++) roundName(r, 4)],
          ['Rodada 1', 'Quartas de final', 'Semifinal', 'Final']);
    });

    test('pontos corridos usa o nome do grupo', () {
      const t = RoundInfo(format: 'ROUND_ROBIN', size: 4);
      expect(roundTitle(t, round: 1, groupName: 'Grupo A'), 'Grupo A');
      expect(roundTitle(t, round: 1), 'Fase de grupos');
    });
  });

  group('datas e status', () {
    test('fmtDate usa só a parte da data (UTC)', () {
      expect(fmtDate('2026-11-15T00:00:00.000Z'), '15/11/2026');
      expect(fmtDate(null), '');
      expect(localDateToIso(DateTime(2026, 3, 5)), '2026-03-05');
      expect(isoToLocalDate('2026-03-05T00:00:00.000Z'), DateTime(2026, 3, 5));
    });

    test('reabrir realizado: com card = planejado, sem card = sem planejamento', () {
      expect(reopenedStatus(3), 'PLANNED');
      expect(reopenedStatus(0), 'UNPLANNED');
    });
  });

  group('resultado da luta realizada', () {
    String? p({
      String type = 'MATCH',
      bool isDone = true,
      bool isDraw = false,
      String? finishType = 'PINFALL',
      List<ParticipantResult> parts = const [],
    }) =>
        resultProblem(
            type: type, isDone: isDone, isDraw: isDraw, finishType: finishType, participants: parts);
    const win = ParticipantResult(side: 1, isWinner: true);
    const win2 = ParticipantResult(side: 2, isWinner: true);
    const lose1 = ParticipantResult(side: 1, isWinner: false);
    const lose2 = ParticipantResult(side: 2, isWinner: false);

    test('exige vencedor + como terminou, ou empate', () {
      expect(p(isDone: false), isNull);
      expect(p(type: 'PROMO'), isNull);
      expect(p(parts: [win, lose2]), isNull);
      expect(p(parts: [lose1, lose2]), contains('vencedor'));
      expect(p(finishType: null, parts: [win, lose2]), contains('terminou'));
      expect(p(parts: [win, win, lose2, lose2]), isNull); // time vencedor
      expect(p(isDraw: true, finishType: null, parts: [lose1, lose2]), isNull);
      expect(p(isDraw: true, parts: [win, lose2]), contains('empatada'));
      expect(p(parts: [win, win2]), contains('mesmo lado'));
      expect(p(), contains('participantes'));
    });
  });
}
