import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:universe_sigma_mobile/app.dart';
import 'package:universe_sigma_mobile/router.dart';

import 'support/common_server.dart';
import 'support/fake_server.dart';

Map<String, dynamic> _show(String id, String name, String kind, {int? weekday}) =>
    {'id': id, 'name': name, 'kind': kind, 'weekday': weekday, 'brand': {'color': '#ef4444'}};

Map<String, dynamic> _ep(String id, Map<String, dynamic> show, int month, int week, String status, {int segments = 0}) => {
      'id': id, 'showId': show['id'], 'seasonId': 's1', 'month': month, 'week': week, 'night': null, 'status': status,
      'title': null, 'show': show, '_count': {'segments': segments},
    };

final _raw = _show('sh1', 'RAW', 'WEEKLY', weekday: 1);
final _sd = _show('sh2', 'SmackDown', 'WEEKLY', weekday: 5);

Map<String, dynamic> _card({String status = 'PLANNED', bool done = false}) => {
      'id': 'e1', 'seasonId': 's1', 'month': 8, 'week': 2, 'night': null, 'status': status, 'title': null, 'show': _raw,
      'segments': [
        {
          'id': 'sg1', 'type': 'MATCH', 'position': 1, 'isMainEvent': false, 'isDone': done, 'isDraw': false,
          'finishType': done ? 'PINFALL' : null, 'notes': 'Abertura', 'matchTypeId': 'mt1', 'matchType': {'name': 'Singles'},
          'titleId': null, 'title': null, 'stakes': 'NONE', 'cardDivision': null,
          'participants': [
            {'wrestlerId': 'w1', 'side': 1, 'isWinner': done, 'wrestler': {'name': 'John Cena'}},
            {'wrestlerId': 'w2', 'side': 2, 'isWinner': false, 'wrestler': {'name': 'CM Punk'}},
          ],
        },
        {
          'id': 'sg2', 'type': 'MATCH', 'position': 2, 'isMainEvent': true, 'isDone': false, 'isDraw': false,
          'finishType': null, 'notes': null, 'matchTypeId': null, 'matchType': null, 'titleId': 't1',
          'title': {'name': 'World Heavyweight'}, 'titleChanged': false, 'stakes': 'NONE', 'cardDivision': null,
          'participants': [
            {'wrestlerId': 'w3', 'side': 1, 'isWinner': false, 'wrestler': {'name': 'Roman Reigns'}},
            {'wrestlerId': 'w4', 'side': 2, 'isWinner': false, 'wrestler': {'name': 'Seth Rollins'}},
          ],
        },
      ],
    };

FakeServer _server({Map<String, Handler> extra = const {}}) {
  final base = commonServer();
  return FakeServer({
    ...base.routes,
    'GET /universes/u1/seasons': (o) => (200, page([{'id': 's1', 'number': 1, 'startMonth': 5, 'name': null}])),
    'GET /universes/u1/episodes': (o) => (200, page([
          _ep('e1', _raw, 8, 2, 'PLANNED', segments: 2),
          _ep('e2', _sd, 8, 2, 'UNPLANNED'),
          _ep('e3', _raw, 8, 1, 'DONE', segments: 1),
        ])),
    'GET /universes/u1/episodes/e1/card': (o) => (200, _card()),
    'GET /universes/u1/wrestlers': (o) => (200, page([
          {'id': 'w1', 'name': 'John Cena'}, {'id': 'w2', 'name': 'CM Punk'},
          {'id': 'w3', 'name': 'Roman Reigns'}, {'id': 'w4', 'name': 'Seth Rollins'},
        ])),
    'GET /universes/u1/match-types': (o) => (200, page([{'id': 'mt1', 'name': 'Singles'}])),
    'GET /universes/u1/titles': (o) => (200, page([{'id': 't1', 'name': 'World Heavyweight'}])),
    'GET /universes/u1/card-divisions': (o) => (200, page([])),
    'GET /universes/u1/tournaments/open-matches': (o) => (200, []),
    ...extra,
  });
}

Future<ProviderContainer> _open(WidgetTester tester, FakeServer server, String location) async {
  final overrides = await testOverrides(server, token: 'tk', prefs: {'universe-sigma:universe': 'u1'});
  await tester.pumpWidget(ProviderScope(retry: (_, _) => null, overrides: overrides, child: const UniverseApp()));
  await tester.pumpAndSettle();
  final c = ProviderScope.containerOf(tester.element(find.byType(UniverseApp)));
  c.read(routerProvider).go(location);
  await tester.pumpAndSettle();
  // deixa terminar as requisições das telas que ficam abaixo na pilha (rotas aninhadas)
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
  return c;
}

/// Rola o formulário (a tela de cima da pilha) até o fim: a lista só constrói o que aparece.
Future<void> _scrollForm(WidgetTester tester, [double dy = -1500]) async {
  await tester.drag(find.byType(ListView).last, Offset(0, dy));
  await tester.pumpAndSettle();
}

void main() {
  group('episódios', () {
    testWidgets('lista por mês com status, "Próximo" e contagem de realizados', (tester) async {
      await _open(tester, _server(), '/episodes');
      expect(find.text('Agosto'), findsNWidgets(2)); // chip do mês + título do grupo
      expect(find.text('1/3 realizados'), findsOneWidget); // e3 está DONE
      expect(find.text('Próximo'), findsOneWidget); // o primeiro PLANNED
      expect(find.text('Sem planejamento'), findsOneWidget);
      expect(find.text('Planejado'), findsWidgets);
      expect(find.text('Realizado'), findsWidgets);
    });

    testWidgets('abre no mês do último episódio realizado; "Todos os meses" mostra tudo', (tester) async {
      final server = _server(extra: {
        'GET /universes/u1/episodes': (o) => (200, page([
              _ep('e4', _raw, 6, 1, 'DONE', segments: 1),
              _ep('e5', _raw, 9, 1, 'PLANNED', segments: 1),
            ])),
      });
      await _open(tester, server, '/episodes');
      expect(find.text('1/1 realizados'), findsOneWidget); // Junho (último realizado)
      expect(find.text('0/1 realizados'), findsNothing); // Setembro oculto
      await tester.tap(find.text('Todos os meses'));
      await tester.pumpAndSettle();
      expect(find.text('0/1 realizados'), findsOneWidget);
    });

    testWidgets('troca para o calendário e mostra os chips no dia do show', (tester) async {
      await _open(tester, _server(), '/episodes');
      await tester.tap(find.byIcon(Icons.calendar_month).last);
      await tester.pumpAndSettle();
      expect(find.text('Agosto'), findsNWidgets(2)); // chip do mês + título do calendário
      expect(find.text('Seg'), findsOneWidget);
      expect(find.text('Sex'), findsOneWidget);
      expect(find.text('RAW'), findsNWidgets(3)); // chip do filtro + semana 1 + semana 2
      expect(find.text('SmackDown'), findsNWidgets(2)); // chip do filtro + chip do calendário
    });

    testWidgets('marcar realizado pelo menu envia status DONE', (tester) async {
      final server = _server(extra: {
        'PUT /universes/u1/episodes/e1': (o) => (200, {'id': 'e1', 'status': 'DONE'}),
      });
      await _open(tester, server, '/episodes');
      // ordem de jogo: e3 (realizado, sem. 1), e1 (RAW sem. 2), e2 (SmackDown sem. 2)
      await tester.tap(find.byIcon(Icons.more_vert).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Marcar como realizado'));
      await tester.pumpAndSettle();
      expect(server.bodies['PUT /universes/u1/episodes/e1'], {'status': 'DONE'});
    });

    testWidgets('reabrir realizado volta a planejado (tem card)', (tester) async {
      final server = _server(extra: {
        'PUT /universes/u1/episodes/e3': (o) => (200, {'id': 'e3', 'status': 'PLANNED'}),
      });
      await _open(tester, server, '/episodes');
      // o episódio realizado (e3) é o primeiro da lista (semana 1)
      await tester.tap(find.byIcon(Icons.more_vert).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Marcar como planejado'));
      await tester.pumpAndSettle();
      expect(server.bodies['PUT /universes/u1/episodes/e3'], {'status': 'PLANNED'});
    });
  });

  group('card do episódio', () {
    testWidgets('mostra segmentos, participantes, main event e título em jogo', (tester) async {
      await _open(tester, _server(), '/episodes/e1/card');
      expect(find.text('RAW'), findsWidgets);
      expect(find.text('Singles'), findsOneWidget);
      expect(find.text('MAIN EVENT'), findsOneWidget);
      expect(find.text('World Heavyweight'), findsOneWidget);
      expect(find.textContaining('John Cena'), findsOneWidget);
      expect(find.textContaining('Seth Rollins'), findsOneWidget);
      expect(find.text('Abertura'), findsOneWidget);
    });

    testWidgets('marcar luta como realizada sem resultado abre o formulário em vez de enviar', (tester) async {
      final server = _server();
      await _open(tester, server, '/episodes/e1/card');
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(find.text('Editar segmento'), findsOneWidget);
      expect(find.text('Realizado'), findsOneWidget);
      // Realizado já vem ligado e o resultado falta: o formulário avisa e não deixa salvar
      await _scrollForm(tester);
      expect(find.textContaining('Marque o vencedor'), findsOneWidget);
      expect(server.calls.where((c) => c.startsWith('PUT /universes/u1/segments')), isEmpty);
    });

    testWidgets('formulário de segmento: marcar vencedor + como terminou libera o salvar e envia o corpo', (tester) async {
      final server = _server(extra: {
        'PUT /universes/u1/segments/sg1': (o) => (200, {'id': 'sg1'}),
      });
      await _open(tester, server, '/episodes/e1/card');
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();

      // estrela no lado 1 (John Cena)
      await _scrollForm(tester, -600);
      await tester.tap(find.text('Venceu').first);
      await tester.pumpAndSettle();
      await _scrollForm(tester);
      expect(find.textContaining('Informe como a luta terminou'), findsOneWidget);
      await _scrollForm(tester, 3000); // volta ao topo

      await tester.tap(find.textContaining('Como terminou'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pinfall'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Informe como'), findsNothing);

      await tester.tap(find.text('Salvar').first);
      await tester.pumpAndSettle();

      final body = server.bodies['PUT /universes/u1/segments/sg1'] as Map;
      expect(body['isDone'], isTrue);
      expect(body['finishType'], 'PINFALL');
      expect(body['episodeId'], 'e1');
      expect((body['participants'] as List).first, {'wrestlerId': 'w1', 'side': 1, 'isWinner': true});
      expect((body['participants'] as List).last['isWinner'], isFalse);
    });

    testWidgets('card vazio oferece adicionar o primeiro segmento', (tester) async {
      final empty = {..._card(), 'segments': []};
      await _open(tester, _server(extra: {'GET /universes/u1/episodes/e1/card': (o) => (200, empty)}), '/episodes/e1/card');
      expect(find.text('O card ainda está vazio.'), findsOneWidget);
      expect(find.text('Adicionar o primeiro segmento'), findsOneWidget);
    });
  });

  group('torneio', () {
    final tournament = {'id': 'tn1', 'name': 'Mini Torneio', 'format': 'SINGLE_ELIMINATION', 'size': 6, 'firstRoundMatches': 2, 'firstRoundPerMatch': 3, 'isTag': false, 'status': 'PLANNED'};
    Map<String, dynamic> w(String id, String n) => {'id': 'en$id', 'wrestlerId': id, 'seed': null, 'startRound': 1, 'wrestler': {'name': n}};
    final a = w('1', 'Ana'), b = w('2', 'Bia'), c = w('3', 'Cris');

    FakeServer srv() => _server(extra: {
          'GET /universes/u1/tournaments/tn1/bracket': (o) => (200, {
                'tournament': tournament,
                'entrants': [a, b, c],
                'matches': [
                  {
                    'id': 'm1', 'round': 1, 'slot': 1, 'groupName': null, 'entrantA': a, 'entrantB': b, 'entrantAId': a['id'], 'entrantBId': b['id'],
                    'extras': [{'entrantId': c['id'], 'entrant': c}], 'winnerId': null, 'winner': null, 'matchType': {'name': 'Triple Threat'},
                    'segmentId': null, 'segment': null, 'matchTypeId': 'mt3',
                  },
                  {
                    'id': 'm2', 'round': 2, 'slot': 1, 'groupName': null, 'entrantA': null, 'entrantB': null, 'entrantAId': null, 'entrantBId': null,
                    'extras': [], 'winnerId': null, 'winner': null, 'matchType': null, 'segmentId': null, 'segment': null,
                  },
                ],
              }),
          'GET /universes/u1/teams': (o) => (200, page([])),
          'POST /universes/u1/tournaments/tn1/generate-bracket': (o) => (201, {'created': 2}),
        });

    testWidgets('mostra rodadas (Final), lutas de 3 e "A definir"', (tester) async {
      await _open(tester, srv(), '/tournaments/tn1');
      expect(find.text('Mini Torneio'), findsOneWidget);
      expect(find.text('Final'), findsOneWidget);
      expect(find.text('Semifinal'), findsOneWidget);
      expect(find.text('Triple Threat'), findsOneWidget);
      expect(find.text('Ana'), findsWidgets);
      expect(find.text('Cris'), findsWidgets);
      expect(find.text('A definir'), findsNWidgets(2));
      expect(find.text('Participantes (3/6)'), findsOneWidget);
    });

    testWidgets('regerar a chave pede confirmação e chama generate-bracket', (tester) async {
      final server = srv();
      await _open(tester, server, '/tournaments/tn1');
      await tester.tap(find.byIcon(Icons.account_tree));
      await tester.pumpAndSettle();
      expect(find.text('Gerar chave novamente'), findsOneWidget);
      await tester.tap(find.text('Gerar'));
      await tester.pumpAndSettle();
      expect(server.calls, contains('POST /universes/u1/tournaments/tn1/generate-bracket'));
    });
    testWidgets('card do episódio: ícone da barra abre o ranking das divisões', (tester) async {
      final board = [
        {
          'id': 'd1', 'name': 'Main Card Masculino', 'gender': 'M', 'isActive': true, 'championSince': null,
          'title': {'name': 'World Heavyweight', 'isTag': false},
          'brands': [{'brandId': 'b1', 'brand': {'name': 'RAW'}}],
          'champions': [], 'entries': [{'id': 'en1', 'wrestlerId': 'w1', 'wrestler': {'name': 'John Cena'}}],
        },
      ];
      await _open(tester, _server(extra: {'GET /universes/u1/card-divisions/board': (o) => (200, board)}), '/episodes/e1/card');
      await tester.tap(find.byIcon(Icons.leaderboard));
      await tester.pumpAndSettle();
      expect(find.text('Ranking das divisões'), findsOneWidget);
      expect(find.text('World Heavyweight'), findsWidgets);
      expect(find.text('Título vago'), findsOneWidget);
    });

    testWidgets('formulário de segmento: botão abre o ranking das divisões da marca do show', (tester) async {
      final board = [
        {
          'id': 'd1', 'name': 'Main Card Masculino', 'gender': 'M', 'isActive': true, 'championSince': null,
          'title': {'name': 'World Heavyweight', 'isTag': false},
          'brands': [{'brandId': 'b1', 'brand': {'name': 'RAW'}}],
          'champions': [{'wrestlerId': 'w9', 'name': 'Drew McIntyre'}],
          'entries': [
            {'id': 'en1', 'wrestlerId': 'w9', 'wrestler': {'name': 'Drew McIntyre'}},
            {'id': 'en2', 'wrestlerId': 'w2', 'wrestler': {'name': 'Kevin Owens'}},
          ],
        },
      ];
      final server = _server(extra: {'GET /universes/u1/card-divisions/board': (o) => (200, board)});
      await _open(tester, server, '/episodes/e1/card');
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ver ranking das divisões'));
      await tester.pumpAndSettle();

      expect(find.text('Ranking das divisões'), findsOneWidget);
      expect(find.text('Main Card Masculino'), findsOneWidget);
      expect(find.text('World Heavyweight'), findsWidgets);
      expect(find.text('Drew McIntyre'), findsWidgets); // campeão em destaque
      expect(find.text('Campeão'), findsOneWidget);
      expect(find.text('Kevin Owens'), findsOneWidget);
      expect(server.calls, contains('GET /universes/u1/card-divisions/board'));
    });
  });

  group('divisões e estatísticas', () {
    testWidgets('quadro de divisões mostra campeão, fila e a ordem', (tester) async {
      final board = [
        {
          'id': 'd1', 'name': 'Main Card Masculino', 'gender': 'M', 'isActive': true, 'championSince': '2026-03-29T00:00:00.000Z',
          'title': {'name': 'World Heavyweight', 'isTag': false},
          'brands': [{'brandId': 'b1', 'brand': {'name': 'RAW'}}],
          'champions': [{'wrestlerId': 'w1', 'name': 'John Cena'}],
          'entries': [
            {'id': 'en1', 'wrestlerId': 'w1', 'wrestler': {'name': 'John Cena'}},
            {'id': 'en2', 'wrestlerId': 'w2', 'wrestler': {'name': 'CM Punk'}},
          ],
        },
      ];
      await _open(tester, _server(extra: {'GET /universes/u1/card-divisions/board': (o) => (200, board)}), '/divisions');
      expect(find.text('Main Card Masculino'), findsOneWidget);
      expect(find.text('CAMPEÃO'), findsOneWidget);
      expect(find.text('desde 29/03/2026'), findsOneWidget);
      expect(find.text('CM Punk'), findsOneWidget);
      expect(find.text('Campeão'), findsOneWidget); // marca na fila
    });

    testWidgets('sem divisões oferece criar as padrão', (tester) async {
      await _open(tester, _server(extra: {'GET /universes/u1/card-divisions/board': (o) => (200, [])}), '/divisions');
      expect(find.text('Criar divisões padrão'), findsOneWidget);
    });

    testWidgets('estatísticas de reinados: destaques e ranking do título', (tester) async {
      final stats = {
        'asOf': '2026-11-01T00:00:00.000Z',
        'titles': [
          {
            'title': {'id': 't1', 'name': 'World Heavyweight'},
            'holders': [
              {'key': 'w1', 'name': 'John Cena', 'reigns': 17, 'days': 1200, 'longestDays': 300, 'isCurrent': true, 'baselineReigns': 16, 'baselineDays': 900, 'baselineNote': null, 'reignList': []},
              {'key': 'w2', 'name': 'CM Punk', 'reigns': 2, 'days': 100, 'longestDays': 80, 'isCurrent': false, 'baselineReigns': 0, 'baselineDays': 0, 'baselineNote': null, 'reignList': []},
            ],
          },
        ],
      };
      await _open(tester, _server(extra: {'GET /universes/u1/stats/titles': (o) => (200, stats)}), '/stats/reigns');
      expect(find.text('Mais reinados'), findsNothing); // o rótulo vem junto do detalhe
      expect(find.textContaining('17x campeão'), findsOneWidget);
      expect(find.textContaining('1.200 dias'), findsWidgets);
      expect(find.text('John Cena'), findsWidgets);
      expect(find.textContaining('Contado até 01/11/2026'), findsOneWidget);
    });
  });
}
