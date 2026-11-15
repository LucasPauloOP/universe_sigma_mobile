import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:universe_sigma_mobile/app.dart';
import 'package:universe_sigma_mobile/router.dart';

import 'support/common_server.dart';
import 'support/fake_server.dart';

final _wrestlers = [
  {'id': 'w1', 'name': 'John Cena', 'gender': 'M', 'contractType': 'FULL_TIME', 'overall': 90, 'brands': []},
  {'id': 'w2', 'name': 'Rhea Ripley', 'gender': 'W', 'contractType': 'FULL_TIME', 'overall': 92, 'brands': []},
];

FakeServer _server({List<Map<String, dynamic>>? wrestlers}) {
  final base = commonServer();
  return FakeServer({
    ...base.routes,
    'GET /universes/u1/wrestlers': (o) => (200, page(wrestlers ?? _wrestlers)),
    'GET /universes/u1/brands': (o) => (200, page([
          {'id': 'b1', 'name': 'RAW', 'isActive': true, 'gm': 'Adam Pearce', 'color': '#ef4444'},
        ])),
    'GET /universes/u1/alignments': (o) => (200, page([])),
    'GET /universes/u1/divisions': (o) => (200, page([])),
    'GET /universes/u1/weight-classes': (o) => (200, page([])),
    'POST /universes/u1/wrestlers': (o) => (201, {'id': 'new', ...(o.data as Map<String, dynamic>)}),
    'GET /universes/u1/brands/b1/impact': (o) => (200, {'shows': ['RAW'], 'episodes': 12, 'segments': 3}),
    'PUT /universes/u1/brands/b1': (o) => (200, {'id': 'b1', 'name': 'RAW', 'isActive': false}),
  });
}

Future<ProviderContainer> _open(WidgetTester tester, FakeServer server, String location) async {
  final overrides = await testOverrides(server, token: 'tk', prefs: {'universe-sigma:universe': 'u1'});
  await tester.pumpWidget(ProviderScope(retry: (_, _) => null, overrides: overrides, child: const UniverseApp()));
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(tester.element(find.byType(UniverseApp)));
  container.read(routerProvider).go(location);
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('lista genérica', () {
    testWidgets('mostra os registros, busca sem acento e limpa com texto sem resultado', (tester) async {
      await _open(tester, _server(), '/r/wrestlers');
      expect(find.text('Lutadores'), findsWidgets);
      expect(find.text('John Cena'), findsOneWidget);
      expect(find.text('Rhea Ripley'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'RHÊA');
      await tester.pumpAndSettle();
      expect(find.text('John Cena'), findsNothing);
      expect(find.text('Rhea Ripley'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('Nenhum resultado para os filtros.'), findsOneWidget);
    });

    testWidgets('lista vazia mostra o estado vazio', (tester) async {
      await _open(tester, _server(wrestlers: []), '/r/wrestlers');
      expect(find.text('Nada cadastrado ainda.'), findsOneWidget);
    });

    testWidgets('filtros: aplica o filtro de gênero', (tester) async {
      await _open(tester, _server(), '/r/wrestlers');
      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();
      expect(find.text('Filtros'), findsOneWidget);
      await tester.tap(find.text('Gênero').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Feminino').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();
      expect(find.text('John Cena'), findsNothing);
      expect(find.text('Rhea Ripley'), findsOneWidget);
    });

    testWidgets('desativar marca pede confirmação com o impacto e envia confirm:true', (tester) async {
      final server = _server();
      await _open(tester, server, '/r/brands');
      expect(find.text('RAW'), findsOneWidget);

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(find.text('Desativar brand'), findsOneWidget);
      expect(find.textContaining('12 episódio(s) e 3 segmento(s)'), findsOneWidget);
      expect(find.textContaining('RAW'), findsWidgets);

      await tester.tap(find.text('Desativar e apagar'));
      await tester.pumpAndSettle();
      expect(server.calls, contains('PUT /universes/u1/brands/b1'));
      expect(server.bodies['PUT /universes/u1/brands/b1'], {'isActive': false, 'confirm': true});
    });

    testWidgets('cancelar a desativação não envia nada', (tester) async {
      final server = _server();
      await _open(tester, server, '/r/brands');
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(server.calls.where((c) => c.startsWith('PUT')), isEmpty);
    });
  });

  group('formulário genérico', () {
    testWidgets('campos obrigatórios vazios bloqueiam o envio e mostram o erro', (tester) async {
      final server = _server();
      await _open(tester, server, '/r/wrestlers/new');
      expect(find.text('Novo(a) lutador'), findsOneWidget);
      await tester.tap(find.text('Salvar').first);
      await tester.pumpAndSettle();
      expect(find.text('Obrigatório'), findsNWidgets(2)); // nome e gênero
      expect(server.calls.where((c) => c.startsWith('POST')), isEmpty);
    });

    testWidgets('preenche, valida limites do número e envia só o que tem valor', (tester) async {
      final server = _server();
      await _open(tester, server, '/r/wrestlers/new');

      await tester.enterText(find.widgetWithText(TextField, 'Nome *'), 'Roman Reigns');
      await tester.tap(find.text('Gênero *'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Masculino').last);
      await tester.pumpAndSettle();

      // overall > 100 é inválido
      await tester.enterText(find.widgetWithText(TextField, 'Overall'), '150');
      await tester.tap(find.text('Salvar').first);
      await tester.pumpAndSettle();
      expect(find.text('Máximo 100'), findsOneWidget);
      expect(server.calls.where((c) => c.startsWith('POST')), isEmpty);

      await tester.enterText(find.widgetWithText(TextField, 'Overall'), '95');
      await tester.tap(find.text('Salvar').first);
      await tester.pumpAndSettle();

      final body = server.bodies['POST /universes/u1/wrestlers'] as Map;
      expect(body['name'], 'Roman Reigns');
      expect(body['gender'], 'M');
      expect(body['overall'], 95); // número, não texto
      expect(body['contractType'], 'FULL_TIME'); // padrão do campo
      expect(body['isActive'], true);
      expect(body.containsKey('alignmentId'), isFalse); // nulos não vão na criação
      expect(body.containsKey('imageUrl'), isFalse);
      // voltou para a lista
      expect(find.text('Novo(a) lutador'), findsNothing);
    });

    testWidgets('editar abre com os valores atuais', (tester) async {
      await _open(tester, _server(), '/r/wrestlers/w1/edit');
      expect(find.text('Editar lutador'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Nome *'), findsOneWidget);
      final name = tester.widget<TextField>(find.widgetWithText(TextField, 'Nome *'));
      expect(name.controller!.text, 'John Cena');
      final ovr = tester.widget<TextField>(find.widgetWithText(TextField, 'Overall'));
      expect(ovr.controller!.text, '90');
    });
  });
}
