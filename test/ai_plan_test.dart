import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:universe_sigma_mobile/app.dart';
import 'package:universe_sigma_mobile/core/ai_plan_logic.dart';
import 'package:universe_sigma_mobile/router.dart';

import 'support/common_server.dart';
import 'support/fake_server.dart';

Map<String, dynamic> _seg(List<(String, String, int)> people, {bool main = false, String? notes}) => {
  'type': 'MATCH',
  'matchTypeId': 'mt1',
  'stakes': 'NONE',
  'isMainEvent': main,
  'isDone': false,
  'titleChanged': false,
  'startsRivalry': false,
  'endsRivalry': false,
  'notes': notes,
  'participants': [
    for (final (id, name, side) in people) {'wrestlerId': id, 'side': side, 'isWinner': false, 'wrestlerName': name},
  ],
};

Map<String, dynamic> _suggested(String id, String label, List<Map<String, dynamic>> segments) => {
  'episodeId': id,
  'label': label,
  'showName': 'RAW',
  'date': '2026-07-06T00:00:00.000Z',
  'segments': segments,
  'warnings': <String>[],
};

void main() {
  group('lógica', () {
    test('lados agrupados e texto', () {
      final s = _seg([('a', 'Ana', 2), ('b', 'Bia', 1), ('c', 'Cris', 2)]);
      expect(aiSides(s), [
        ['Bia'],
        ['Ana', 'Cris'],
      ]);
      expect(aiSidesText(s), 'Bia x Ana + Cris');
    });

    test('payload sem os campos de exibição; bulk só marcados e com segmentos', () {
      final eps = [
        _suggested('e1', 'A', [
          _seg([('a', 'Ana', 1), ('b', 'Bia', 2)]),
        ]),
        _suggested('e2', 'B', []),
        _suggested('e3', 'C', [
          _seg([('c', 'Cris', 1), ('d', 'Dani', 2)]),
        ]),
      ];
      final items = aiBulkItems(eps, {'e1', 'e2'}, replace: true);
      expect(items.map((i) => i['episodeId']), ['e1']);
      expect(items.first['replace'], true);
      expect((items.first['segments'] as List).first['participants'][0], {
        'wrestlerId': 'a',
        'side': 1,
        'isWinner': false,
      });
    });

    test('remover segmento não altera o original', () {
      final e = _suggested('e1', 'A', [_seg([]), _seg([])]);
      expect((aiWithoutSegment(e, 0)['segments'] as List).length, 1);
      expect((e['segments'] as List).length, 2);
    });

    test('período no calendário do jogo (maio → abril)', () {
      expect(aiRangeInverted(fromMonth: 7, fromWeek: 2, toMonth: 7, toWeek: 1), isTrue);
      expect(aiRangeInverted(fromMonth: 11, fromWeek: 4, toMonth: 1, toWeek: 1), isFalse); // vira o ano
      expect(aiRangeInverted(fromMonth: 1, fromWeek: 1, toMonth: 11, toWeek: 4), isTrue);
      expect(
        aiRangeBody(
          seasonId: 's1',
          fromMonth: 7,
          fromWeek: 1,
          toMonth: 11,
          toWeek: 4,
          count: 5,
          includeMainEvent: true,
          skipPlanned: true,
          guidance: '  ',
        ),
        {
          'seasonId': 's1',
          'from': {'month': 7, 'week': 1},
          'to': {'month': 11, 'week': 4},
          'count': 5,
          'includeMainEvent': true,
          'skipPlanned': true,
        },
      );
      expect(aiProgress({'total': 4, 'done': 1}), 0.25);
      expect(aiProgress(null), 0);
    });
  });

  group('telas', () {
    final raw = {'id': 'sh1', 'name': 'RAW', 'kind': 'WEEKLY', 'weekday': 1, 'brandId': null};
    final emptyCard = {
      'id': 'e1',
      'seasonId': 's1',
      'month': 7,
      'week': 1,
      'night': null,
      'status': 'UNPLANNED',
      'title': null,
      'show': raw,
      'segments': <Object>[],
    };

    FakeServer server({Map<String, Handler> extra = const {}}) => FakeServer({
      ...commonServer().routes,
      'GET /universes/u1/seasons': (o) => (
        200,
        page([
          {'id': 's1', 'number': 1, 'startMonth': 5, 'name': null},
        ]),
      ),
      'GET /universes/u1/shows': (o) => (200, page([raw])),
      'GET /universes/u1/episodes': (o) => (
        200,
        page([
          {
            'id': 'e1',
            'showId': 'sh1',
            'seasonId': 's1',
            'month': 7,
            'week': 1,
            'night': null,
            'status': 'UNPLANNED',
            'title': null,
            'show': raw,
            '_count': {'segments': 0},
          },
        ]),
      ),
      'GET /universes/u1/episodes/e1/card': (o) => (200, emptyCard),
      'GET /universes/u1/match-types': (o) => (
        200,
        page([
          {'id': 'mt1', 'name': 'Singles'},
        ]),
      ),
      'GET /universes/u1/card-divisions': (o) => (200, page([])),
      ...extra,
    });

    Future<void> open(WidgetTester tester, FakeServer s, String location) async {
      final overrides = await testOverrides(s, token: 'tk', prefs: {'universe-sigma:universe': 'u1'});
      await tester.pumpWidget(ProviderScope(retry: (_, _) => null, overrides: overrides, child: const UniverseApp()));
      await tester.pumpAndSettle();
      final c = ProviderScope.containerOf(tester.element(find.byType(UniverseApp)));
      c.read(routerProvider).go(location);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
    }

    testWidgets('card: gera com IA, mostra a prévia e salva sem os nomes', (tester) async {
      final s = server(
        extra: {
          'POST /universes/u1/episodes/e1/segments/suggest': (o) => (
            200,
            _suggested('e1', 'RAW — Semana 1', [
              _seg([('w1', 'John Cena', 1), ('w2', 'CM Punk', 2)], main: true, notes: 'Revanche esperada'),
            ]),
          ),
          'POST /universes/u1/episodes/e1/segments': (o) => (201, <Object>[]),
        },
      );
      await open(tester, s, '/episodes/e1/card');
      await tester.tap(find.byTooltip('Gerar com IA'));
      await tester.pumpAndSettle();
      expect(find.text('Gerar com IA'), findsWidgets);
      await tester.tap(find.widgetWithText(FilledButton, 'Gerar'));
      await tester.pumpAndSettle();

      expect(s.bodies['POST /universes/u1/episodes/e1/segments/suggest'], {'count': 5, 'includeMainEvent': true});
      expect(find.text('John Cena x CM Punk'), findsOneWidget);
      expect(find.text('Singles'), findsOneWidget);
      expect(find.text('MAIN EVENT'), findsOneWidget);
      expect(find.text('Revanche esperada'), findsOneWidget);

      await tester.tap(find.text('Salvar card'));
      await tester.pumpAndSettle();
      final body = s.bodies['POST /universes/u1/episodes/e1/segments'] as Map;
      expect(body['replace'], false);
      final p = (body['segments'] as List).first['participants'] as List;
      expect(p.first, {'wrestlerId': 'w1', 'side': 1, 'isWinner': false});
    });

    testWidgets('período: mês/semana do jogo, progresso, prévia e gravação em lote', (tester) async {
      var polls = 0;
      final s = server(
        extra: {
          'POST /universes/u1/episodes/suggest-range': (o) => (202, {'jobId': 'j1', 'total': 2}),
          'GET /universes/u1/episodes/suggest-range/j1': (o) {
            polls++;
            return (
              200,
              {
                'id': 'j1',
                'status': polls < 2 ? 'running' : 'done',
                'total': 2,
                'done': polls < 2 ? 1 : 2,
                'current': polls < 2 ? 'RAW — Semana 2' : null,
                'error': null,
                'episodes': [
                  _suggested('e1', 'RAW — Semana 1', [
                    _seg([('w1', 'John Cena', 1), ('w2', 'CM Punk', 2)]),
                  ]),
                  if (polls >= 2)
                    _suggested('e2', 'RAW — Semana 2', [
                      _seg([('w3', 'Roman Reigns', 1), ('w4', 'Seth Rollins', 2)]),
                    ]),
                ],
              },
            );
          },
          'POST /universes/u1/episodes/segments/bulk': (o) => (
            200,
            {
              'results': [
                {'episodeId': 'e1', 'ok': true, 'count': 1},
                {'episodeId': 'e2', 'ok': true, 'count': 1},
              ],
            },
          ),
        },
      );
      await open(tester, s, '/episodes');
      await tester.tap(find.byTooltip('Planejar com IA'));
      await tester.pumpAndSettle();
      expect(find.text('Planejar com IA'), findsWidgets);
      expect(find.text('Temporada 1'), findsOneWidget); // já vem com a temporada da tela

      // "Até" antes de "De" bloqueia
      await tester.tap(find.text('Semana 4'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Semana 1').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Semana 1').first); // De: semana 1 → 2
      await tester.pumpAndSettle();
      await tester.tap(find.text('Semana 2').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('O fim vem antes do início'), findsOneWidget);

      // Até: Julho, semana 1 (De continua Maio, semana 2)
      await tester.tap(find.text('Maio').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Julho').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('O fim vem antes do início'), findsNothing);

      final gerar = find.widgetWithText(FilledButton, 'Gerar');
      await tester.scrollUntilVisible(gerar, 200, scrollable: find.byType(Scrollable).last);
      await tester.pumpAndSettle();
      await tester.tap(gerar);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final sent = s.bodies['POST /universes/u1/episodes/suggest-range'] as Map;
      expect(sent['seasonId'], 's1');
      expect(sent['from'], {'month': 5, 'week': 2});
      expect(sent['to'], {'month': 7, 'week': 1});

      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Planejando 1 de 2 episódios'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Roman Reigns x Seth Rollins'), findsOneWidget);

      await tester.tap(find.text('Salvar 2 episódio(s)'));
      await tester.pumpAndSettle();
      final bulk = s.bodies['POST /universes/u1/episodes/segments/bulk'] as Map;
      expect((bulk['items'] as List).map((i) => i['episodeId']), ['e1', 'e2']);
      expect(find.text('2 episódio(s) planejado(s)'), findsOneWidget);
    });
  });
}
