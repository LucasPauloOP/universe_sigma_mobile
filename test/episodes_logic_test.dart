import 'package:flutter_test/flutter_test.dart';
import 'package:universe_sigma_mobile/core/dashboard_logic.dart';
import 'package:universe_sigma_mobile/core/episodes_logic.dart';
import 'package:universe_sigma_mobile/core/models.dart';

Entity ep(String id, String show, String kind, int month, int? week,
        {int? weekday, String status = 'UNPLANNED', int? night, String season = 's1'}) =>
    {
      'id': id,
      'showId': show,
      'seasonId': season,
      'month': month,
      'week': week,
      'night': night,
      'status': status,
      'show': {'name': show, 'kind': kind, 'weekday': weekday},
    };

void main() {
  final seasons = <Entity>[
    {'id': 's1', 'number': 1, 'startMonth': 8},
    {'id': 's2', 'number': 2, 'startMonth': 5},
  ];

  group('fila do que jogar', () {
    test('ignora meses anteriores ao início e ordena por temporada e ordem de jogo', () {
      final planned = [
        ep('a', 'RAW', 'WEEKLY', 6, 1, weekday: 1, status: 'PLANNED'), // junho < agosto: fora
        ep('b', 'SmackDown', 'WEEKLY', 8, 2, weekday: 5, status: 'PLANNED'),
        ep('c', 'RAW', 'WEEKLY', 8, 2, weekday: 1, status: 'PLANNED'),
        ep('d', 'RAW', 'WEEKLY', 5, 1, weekday: 1, status: 'PLANNED', season: 's2'),
        ep('e', 'RAW', 'WEEKLY', 1, 1, weekday: 1, status: 'PLANNED'), // janeiro vem depois de agosto
      ];
      final up = upcomingEpisodes(planned, seasons);
      expect(up.map((e) => e.id).toList(), ['c', 'b', 'e', 'd']);
      expect(upcomingEpisodes(planned, seasons, take: 2).length, 2);
    });

    test('rótulo de quando acontece', () {
      expect(whenLabel(ep('x', 'RAW', 'WEEKLY', 8, 2, weekday: 1)), 'Segunda · Agosto · semana 2');
      expect(whenLabel(ep('x', 'WM', 'PLE', 4, 3, night: 2)), 'Domingo · Abril · semana 3 · Noite 2');
    });

    test('campeões atuais: só reinados abertos, por título, com "&" entre duplas', () {
      final reigns = <Entity>[
        {'title': {'name': 'World'}, 'endDate': null, 'startDate': '2026-03-29T00:00:00.000Z',
          'holders': [{'wrestler': {'name': 'Cena'}}]},
        {'title': {'name': 'Tag'}, 'endDate': null, 'startDate': '2026-01-05T00:00:00.000Z',
          'holders': [{'wrestler': {'name': 'A'}}, {'wrestler': {'name': 'B'}}]},
        {'title': {'name': 'US'}, 'endDate': '2026-02-01T00:00:00.000Z', 'startDate': '2026-01-01T00:00:00.000Z',
          'holders': [{'wrestler': {'name': 'X'}}]},
        {'title': {'name': 'Vago'}, 'endDate': null, 'startDate': '2026-01-01T00:00:00.000Z', 'holders': []},
      ];
      final c = currentChampions(reigns);
      expect(c.map((x) => x.title).toList(), ['Tag', 'Vago', 'World']);
      expect(c.first.holders, 'A & B');
      expect(c.first.since, '05/01/2026');
      expect(c[1].holders, '—');
    });
  });

  group('tela de episódios', () {
    final all = [
      ep('1', 'RAW', 'WEEKLY', 8, 1, weekday: 1, status: 'DONE'),
      ep('2', 'RAW', 'WEEKLY', 8, 2, weekday: 1, status: 'PLANNED'),
      ep('3', 'SmackDown', 'WEEKLY', 8, 2, weekday: 5),
      ep('4', 'SummerSlam', 'PLE', 8, 4),
      ep('5', 'RAW', 'WEEKLY', 6, 1, weekday: 1),
      ep('6', 'RAW', 'WEEKLY', 5, 1, weekday: 1, season: 's2'),
    ];

    test('só a temporada escolhida, em ordem; mês de início corta os anteriores', () {
      final of = episodesOfSeason(all, 's1');
      expect(of.map((e) => e.id).toList(), ['5', '1', '2', '3', '4']);
      final playable = playableEpisodes(of, 8);
      expect(playable.map((e) => e.id).toList(), ['1', '2', '3', '4']);
      expect(nextEpisodeId(playable), '2');
    });

    test('agrupa por mês separando semanais de PLE', () {
      final playable = playableEpisodes(episodesOfSeason(all, 's1'), 8);
      final weekly = groupByMonth(playable, weekly: true);
      expect(weekly.single.month, 8);
      expect(weekly.single.episodes.length, 3);
      expect(weekly.single.done, 1);
      expect(groupByMonth(playable, weekly: false).single.episodes.single.id, '4');
      expect(groupByMonth(playable, weekly: true, showId: 'SmackDown').single.episodes.length, 1);
    });

    test('calendário: 4 semanas x 7 dias, coluna pelo dia do show', () {
      final rows = calendarRows(playableEpisodes(episodesOfSeason(all, 's1'), 8), 8);
      expect(rows.length, 4);
      expect(rows.every((r) => r.length == 7), isTrue);
      expect(rows[0][0].single.id, '1'); // semana 1, segunda
      expect(rows[1][0].single.id, '2'); // semana 2, segunda
      expect(rows[1][4].single.id, '3'); // semana 2, sexta
      expect(rows[3][5].single.id, '4'); // PLE: semana 4, sábado
      expect(calendarMonths(all), [5, 6, 8]);
    });

    test('temporada em andamento: a primeira com episódio não realizado', () {
      expect(currentSeasonId(seasons, all), 's1');
      final done = all.map((e) => {...e, 'status': 'DONE'}).toList();
      expect(currentSeasonId(seasons, done), 's2'); // todas realizadas: a última
      expect(currentSeasonId([], all), isNull);
    });

    test('textos', () {
      expect(calendarChip(ep('x', 'WrestleMania', 'PLE', 4, 3, night: 1)), 'WrestleMania · N1');
      expect(episodeWhen(ep('x', 'RAW', 'WEEKLY', 8, 2)), 'Agosto · semana 2');
    });
  });

  group('mês padrão da lista', () {
    final list = [
      ep('a', 'RAW', 'WEEKLY', 5, 1, weekday: 1, status: 'DONE'),
      ep('b', 'RAW', 'WEEKLY', 6, 1, weekday: 1, status: 'DONE'),
      ep('c', 'RAW', 'WEEKLY', 6, 2, weekday: 1, status: 'PLANNED'),
      ep('d', 'RAW', 'WEEKLY', 7, 1, weekday: 1, status: 'UNPLANNED'),
    ];
    test('lastDoneMonth: mês do último realizado na ordem de jogo', () {
      expect(lastDoneMonth(episodesOfSeason(list, 's1')), 6);
    });
    test('sem realizado, usa o mês do primeiro episódio', () {
      expect(lastDoneMonth([ep('x', 'RAW', 'WEEKLY', 8, 1, weekday: 1)]), 8);
      expect(lastDoneMonth([]), isNull);
    });
    test('defaultMonth: o do último realizado, ou o mais próximo antes dele', () {
      expect(defaultMonth([5, 6, 7], 6), 6);
      expect(defaultMonth([5, 7], 6), 5); // mês 6 não existe na aba (ex.: PLEs)
      expect(defaultMonth([7, 8], 5), 7); // nada antes: primeiro
      expect(defaultMonth([], 6), isNull);
      expect(defaultMonth([5, 6], null), 5);
    });
    test('virada de ano: janeiro vem depois de dezembro na temporada', () {
      expect(defaultMonth([11, 12, 1], 12), 12);
      expect(defaultMonth([12, 1], 3), 1);
    });
  });
}
