import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:universe_sigma_mobile/app.dart';

import 'support/common_server.dart';
import 'support/fake_server.dart';

Future<void> _boot(WidgetTester tester, FakeServer server, {String? token, Map<String, Object> prefs = const {}}) async {
  final overrides = await testOverrides(server, token: token, prefs: prefs);
  await tester.pumpWidget(ProviderScope(retry: (_, _) => null, overrides: overrides, child: const UniverseApp()));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sem sessão guardada abre a tela de login', (tester) async {
    await _boot(tester, commonServer(loggedIn: false));
    expect(find.text('Entrar'), findsWidgets);
    expect(find.text('Criar conta'), findsOneWidget);
    expect(find.text('Esqueci a senha'), findsOneWidget);
  });

  testWidgets('login válido leva ao painel do universe selecionado', (tester) async {
    final server = commonServer(loggedIn: false);
    await _boot(tester, server);

    await tester.enterText(find.byType(TextFormField).at(0), 'a@b.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'senha-boa-123');
    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pumpAndSettle();

    expect(server.calls, contains('POST /auth/login'));
    // sem universe selecionado: vai escolher/usar o primeiro e mostrar o painel
    expect(find.text('Meu Universe'), findsWidgets);
    await tester.drag(find.byType(ListView).first, const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('Campeões atuais'), findsOneWidget);
    expect(find.text('John Cena'), findsOneWidget);
    expect(find.textContaining('World Heavyweight'), findsOneWidget);
  });

  testWidgets('login com validação: e-mail inválido não chama a API', (tester) async {
    final server = commonServer(loggedIn: false);
    await _boot(tester, server);
    await tester.enterText(find.byType(TextFormField).at(0), 'nao-e-email');
    await tester.enterText(find.byType(TextFormField).at(1), 'x');
    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pumpAndSettle();
    expect(find.text('E-mail inválido'), findsOneWidget);
    expect(server.calls, isNot(contains('POST /auth/login')));
  });

  testWidgets('sessão guardada restaura direto no painel', (tester) async {
    await _boot(tester, commonServer(), token: 'tk', prefs: {'universe-sigma:universe': 'u1'});
    expect(find.text('Meu Universe'), findsWidgets);
    expect(find.text('Lutadores'), findsOneWidget); // contador do painel
    await tester.drag(find.byType(ListView).first, const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('Campeões atuais'), findsOneWidget);
  });

  testWidgets('menu lateral lista os grupos e os recursos', (tester) async {
    await _boot(tester, commonServer(), token: 'tk', prefs: {'universe-sigma:universe': 'u1'});
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('Episódios'), findsWidgets);
    expect(find.text('Divisões (ranking)'), findsOneWidget);
    expect(find.text('Roster'), findsOneWidget);
    expect(find.text('Torneios'), findsWidgets);
    await tester.drag(find.byType(ListView).last, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('Sair'), findsOneWidget);
    expect(find.text('Importar planilha'), findsOneWidget);
  });
}
