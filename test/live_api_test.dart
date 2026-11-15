// Teste de contrato contra uma API REAL. Só roda com --dart-define=LIVE_API=http://host:porta/api
//   flutter test test/live_api_test.dart --dart-define=LIVE_API=http://localhost:3100/api
// Cria um usuário descartável (e-mail live.<timestamp>@example.com) com o universe padrão.
@Timeout(Duration(minutes: 5))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:universe_sigma_mobile/core/api/api_client.dart';
import 'package:universe_sigma_mobile/core/api/token_store.dart';
import 'package:universe_sigma_mobile/core/dashboard_logic.dart';
import 'package:universe_sigma_mobile/core/division_logic.dart';
import 'package:universe_sigma_mobile/core/episodes_logic.dart';
import 'package:universe_sigma_mobile/core/format.dart';
import 'package:universe_sigma_mobile/core/models.dart';
import 'package:universe_sigma_mobile/core/reign_logic.dart';
import 'package:universe_sigma_mobile/core/segment_logic.dart';
import 'package:universe_sigma_mobile/core/tournament_logic.dart';
import 'package:universe_sigma_mobile/resources/resource_def.dart';
import 'package:universe_sigma_mobile/resources/resources.dart';

const _live = String.fromEnvironment('LIVE_API');

void main() {
  if (_live.isEmpty) {
    test('contrato com a API real', () {}, skip: 'defina --dart-define=LIVE_API=http://host:porta/api para rodar');
    return;
  }

  late ApiClient api;
  late String email;
  const password = 'senha-live-123';

  setUpAll(() async {
    api = ApiClient(tokens: MemoryTokenStore(), baseUrl: _live);
    email = 'live.${DateTime.now().millisecondsSinceEpoch}@example.com';
    final reg = await api.post('/auth/register', body: {'email': email, 'password': password, 'useTemplate': true});
    await api.tokens.save(access: reg['token'] as String, refresh: reg['refreshToken'] as String);
    api.universeId = reg['universe']['id'] as String;
  });

  group('sessão', () {
    test('registro devolve token + refresh token e /auth/me funciona', () async {
      expect(await api.tokens.refresh, isNotNull);
      final me = await api.get('/auth/me') as Map;
      expect(me['email'], email);
    });

    test('token vencido: o cliente renova sozinho com o refresh token', () async {
      await api.tokens.save(access: 'token-invalido');
      final me = await api.get('/auth/me') as Map; // 401 → refresh → repete
      expect(me['email'], email);
      expect(await api.tokens.access, isNot('token-invalido'));
    });

    test('login normal', () async {
      final c = ApiClient(tokens: MemoryTokenStore(), baseUrl: _live);
      final r = await c.post('/auth/login', body: {'email': email, 'password': password});
      expect(r['token'], isNotNull);
      expect(r['refreshToken'], isNotNull);
    });
  });

  group('recursos genéricos contra dados reais', () {
    for (final r in resources.values) {
      test('${r.key}: lista, rótulo e colunas renderizam sem erro', () async {
        final items = await api.all(r.key);
        for (final e in items) {
          expect(r.label(e), isA<String>(), reason: '${r.key} ${e['id']}');
          for (final c in r.columns) {
            final v = c.render != null ? c.render!(e, (_, id) => id ?? '') : e[c.key];
            expect(v == null || v is String || v is num || v is bool || c.render == null, isTrue, reason: '${r.key}.${c.key}');
          }
          // todo campo "fromEntity" tem que aguentar o formato real
          for (final f in r.fields) {
            if (f.fromEntity != null) f.fromEntity!(e);
          }
        }
        if (['wrestlers', 'brands', 'titles', 'shows', 'episodes', 'seasons', 'match-types', 'teams'].contains(r.key)) {
          expect(items, isNotEmpty, reason: 'o universe padrão deveria ter ${r.key}');
        }
      });
    }

    test('editar e salvar um lutador sem mexer em nada não altera o registro (round-trip do buildBody)', () async {
      final w = (await api.page('wrestlers', limit: 1)).data.first;
      final res = resources['wrestlers']!;
      final values = <String, Object?>{
        for (final f in res.fields)
          f.key: f.fromEntity != null ? f.fromEntity!(w) : (w[f.key] ?? ((f.type == FieldType.text || f.type == FieldType.textarea) ? '' : null)),
      };
      final body = buildBody(res, values, original: w);
      final saved = Map<String, dynamic>.from(await api.put('wrestlers/${w.id}', body: body) as Map);
      expect(saved['name'], w['name']);
      expect(saved['gender'], w['gender']);
      expect(saved['overall'], w['overall']);
    });
  });

  group('telas de negócio', () {
    /// Num universe novo todo episódio nasce "sem planejamento": planeja um para ter "próximo".
    Future<Entity> planOne() async {
      final eps = await api.all('episodes');
      final ep = eps.firstWhere((e) => e['status'] == 'UNPLANNED' && isWeekly(e));
      await api.put('episodes/${ep.id}', body: {'status': 'PLANNED'});
      return ep;
    }

    test('painel: contadores, fila do que jogar e campeões atuais', () async {
      expect(await api.all('episodes', query: {'status': 'PLANNED'}), isEmpty); // nada planejado ainda
      final planned0 = upcomingEpisodes(await api.all('episodes', query: {'status': 'PLANNED'}), await api.all('seasons'));
      expect(planned0, isEmpty);
      final ep = await planOne();
      final seasons = await api.all('seasons');
      final planned = await api.all('episodes', query: {'status': 'PLANNED'});
      final reigns = await api.all('title-reigns');
      final up = upcomingEpisodes(planned, seasons);
      expect(up.map((e) => e.id), contains(ep.id));
      expect(whenLabel(up.first), isNotEmpty);
      expect(currentChampions(reigns), isNotEmpty);
      expect(await api.count('wrestlers'), greaterThan(100));
    });

    test('episódios: temporada atual, agrupamento e calendário', () async {
      final planned = await planOne();
      final seasons = await api.all('seasons');
      final eps = await api.all('episodes');
      final sid = currentSeasonId(seasons, eps)!;
      final season = seasons.firstWhere((s) => s.id == sid);
      final of = episodesOfSeason(eps, sid);
      final playable = playableEpisodes(of, (season['startMonth'] as num?)?.toInt() ?? 5);
      expect(groupByMonth(playable, weekly: true), isNotEmpty);
      expect(calendarRows(playable, calendarMonths(playable).first).length, 4);
      expect(nextEpisodeId(playable), isNotNull);
      expect(playable.firstWhere((e) => e.id == planned.id)['status'], 'PLANNED');
    });

    test('card do episódio: GET card e criar/editar/reordenar/apagar segmento mudando o status', () async {
      final seasons = await api.all('seasons');
      final eps = await api.all('episodes');
      final sid = currentSeasonId(seasons, eps)!;
      final ep = episodesOfSeason(eps, sid).firstWhere((e) => e['status'] == 'UNPLANNED' && isWeekly(e));
      final matchTypes = await api.all('match-types');
      final ws = (await api.page('wrestlers', limit: 4)).data;

      Future<Entity> card() async => Map<String, dynamic>.from(await api.get('episodes/${ep.id}/card') as Map);
      expect((await card())['status'], 'UNPLANNED'); // sem lutas: sem planejamento

      // monta uma luta com o rascunho do app
      final d = SegmentDraft(matchTypeId: matchTypes.firstWhere((t) => t['name'] == 'Singles').id, notes: 'Live');
      d.addParticipant(1, ws[0].id);
      d.addParticipant(2, ws[1].id);
      final created = Map<String, dynamic>.from(await api.post('segments', body: d.toBody(ep.id)) as Map);
      var c = await card();
      expect(c['status'], 'PLANNED'); // primeiro segmento planeja o episódio
      expect(c.list('segments').length, 1);

      // luta realizada exige resultado: o backend também recusa; o app já avisa antes
      final done = SegmentDraft.fromEntity(c.list('segments').first)..isDone = true;
      expect(done.problem, isNotNull);
      done
        ..toggleWinner(ws[0].id)
        ..finishType = 'PINFALL';
      expect(done.problem, isNull);
      await api.put('segments/${created.id}', body: done.toBody(ep.id));
      c = await card();
      expect(c.list('segments').first['isDone'], isTrue);
      final part = c.list('segments').first.list('participants').firstWhere((p) => p['wrestlerId'] == ws[0].id);
      expect(part['isWinner'], isTrue);

      // segundo segmento e reordenar
      final d2 = SegmentDraft(notes: 'Promo', type: 'PROMO')..addParticipant(1, ws[2].id);
      final second = Map<String, dynamic>.from(await api.post('segments', body: d2.toBody(ep.id)) as Map);
      await api.put('episodes/${ep.id}/segments/order', body: {'order': [second.id, created.id]});
      c = await card();
      expect(c.list('segments').map((s) => s.id), [second.id, created.id]);

      // apagar todos: volta a "sem planejamento"
      await api.delete('segments/${second.id}');
      await api.delete('segments/${created.id}');
      expect((await card())['status'], 'UNPLANNED');
    });

    test('torneio: mini torneio (2 triple threats + final) e inscrito que entra na final', () async {
      final ws = (await api.page('wrestlers', limit: 8)).data;
      final t = Map<String, dynamic>.from(await api.post('tournaments', body: {
        'name': 'Mini Live', 'size': 6, 'firstRoundMatches': 2, 'firstRoundPerMatch': 3,
      }) as Map);
      for (var i = 0; i < 6; i++) {
        await api.post('tournament-entrants', body: {'tournamentId': t.id, 'wrestlerId': ws[i].id, 'seed': i + 1, 'startRound': 1});
      }
      await api.post('tournaments/${t.id}/generate-bracket');
      var b = Map<String, dynamic>.from(await api.get('tournaments/${t.id}/bracket') as Map);
      var rounds = roundsOf(b.list('matches'));
      expect(rounds.map((r) => r.title), ['Semifinal', 'Final']);
      expect(rounds.first.matches.length, 2);
      expect(competitorsOf(rounds.first.matches.first).length, 3); // triple threat
      expect(rounds.last.matches.length, 1);
      expect(totalRounds(RoundInfo.fromTournament(b.obj('tournament')!)), 2);

      // vencedor da semi avança para a final
      final semi = rounds.first.matches.first;
      final winner = competitorsOf(semi).first;
      await api.put('tournament-matches/${semi.id}', body: {'winnerId': winner.id});
      b = Map<String, dynamic>.from(await api.get('tournaments/${t.id}/bracket') as Map);
      rounds = roundsOf(b.list('matches'));
      expect(competitorsOf(rounds.last.matches.first).map((e) => e.id), contains(winner.id));

      // 7 inscritos em 8 vagas: o 7º já entra na semifinal
      final t2 = Map<String, dynamic>.from(await api.post('tournaments', body: {'name': 'Bye Live', 'size': 8, 'firstRoundMatches': 4}) as Map);
      for (var i = 0; i < 7; i++) {
        await api.post('tournament-entrants', body: {'tournamentId': t2.id, 'wrestlerId': ws[i].id, 'startRound': i == 6 ? 2 : 1});
      }
      await api.post('tournaments/${t2.id}/generate-bracket');
      final b2 = Map<String, dynamic>.from(await api.get('tournaments/${t2.id}/bracket') as Map);
      final r2 = roundsOf(b2.list('matches'));
      expect(r2.map((r) => r.title), ['Quartas de final', 'Semifinal', 'Final']);
      expect(r2.first.matches.length, 3); // uma luta das quartas saiu da chave
      expect(startsAt(b2.obj('tournament')!, b2.list('entrants').last), 'Semifinal');

      await api.delete('tournaments/${t.id}');
      await api.delete('tournaments/${t2.id}');
    });

    test('divisões e estatísticas de reinados', () async {
      await api.post('card-divisions/defaults');
      final board = (await api.get('card-divisions/board') as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      expect(board, isNotEmpty);
      expect(brandOptions(board), isNotEmpty);
      final firstBrand = brandOptions(board).first.id;
      final div = visibleDivisions(board, firstBrand).first;
      expect(genderLabel(div), isNotEmpty);
      for (final e in div.list('entries')) {
        expect(entryName(e), isNotEmpty);
      }
      final stats = Map<String, dynamic>.from(await api.get('stats/titles') as Map);
      final titles = stats.list('titles');
      expect(titles, isNotEmpty);
      expect(overallOf(titles), isNotEmpty);
      expect(highlightsOf(titles).length, greaterThanOrEqualTo(2));
    });

    test('importar histórico padrão e episódios gerados ficam sem planejamento', () async {
      final created = await api.post('title-baselines/defaults') as Map;
      expect(created.containsKey('created'), isTrue);
      final seasons = await api.all('seasons');
      final eps = await api.all('episodes');
      final unplanned = eps.where((e) => e['status'] == 'UNPLANNED').length;
      expect(unplanned, greaterThan(0));
      expect(seasons, isNotEmpty);
    });

    test('contrato de erro: 422 vira ApiException com os detalhes em português', () async {
      try {
        await api.post('wrestlers', body: {'gender': 'M'}); // sem nome
        fail('deveria falhar');
      } catch (e) {
        expect(e.toString(), contains('Dados inválidos'));
      }
    });
  });
}
