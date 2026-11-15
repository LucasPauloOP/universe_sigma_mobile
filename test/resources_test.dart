import 'package:flutter_test/flutter_test.dart';
import 'package:universe_sigma_mobile/resources/resources.dart';

void main() {
  final wrestlers = resources['wrestlers']!;

  group('buildBody (mesmos casos do resources.spec.ts do web)', () {
    test('na criação omite campos nulos e mantém booleanos', () {
      final body = buildBody(wrestlers, {
        'name': 'John', 'gender': 'M', 'contractType': 'FULL_TIME', 'overall': '88',
        'brandIds': ['b1'], 'alignmentId': null, 'imageUrl': null, 'isActive': true,
      });
      expect(body['name'], 'John');
      expect(body['overall'], 88);
      expect(body['brandIds'], ['b1']);
      expect(body['isActive'], true);
      expect(body.containsKey('alignmentId'), isFalse);
      expect(body.containsKey('imageUrl'), isFalse);
    });

    test('na edição não reenvia a URL assinada da imagem se não mudou', () {
      final entity = {'id': '1', 'imageUrl': 'https://signed/url'};
      Map<String, Object?> run(Object? img) =>
          buildBody(wrestlers, {'name': 'A', 'gender': 'M', 'imageUrl': img}, original: entity);
      expect(run('https://signed/url').containsKey('imageUrl'), isFalse);
      expect(run('storage:u/x.png')['imageUrl'], 'storage:u/x.png');
      expect(run(null)['imageUrl'], isNull);
      expect(run(null).containsKey('imageUrl'), isTrue);
    });

    test('na edição envia null para limpar vínculos opcionais', () {
      final body = buildBody(wrestlers, {'name': 'A', 'gender': 'M', 'alignmentId': null},
          original: {'id': '1'});
      expect(body.containsKey('alignmentId'), isTrue);
      expect(body['alignmentId'], isNull);
    });

    test('reinado junta lutadores e duplas em holders', () {
      final body = buildBody(resources['title-reigns']!, {
        'titleId': 't', 'startDate': DateTime(2026, 1, 5), 'endDate': null,
        'wrestlerHolderIds': ['w1'], 'teamHolderIds': ['tm1'],
      });
      expect(body['startDate'], '2026-01-05');
      expect(body['holders'], [{'wrestlerId': 'w1'}, {'teamId': 'tm1'}]);
      expect(body.containsKey('wrestlerHolderIds'), isFalse);
    });

    test('esconde campos condicionais (show semanal não manda ppvMonth)', () {
      final body = buildBody(resources['shows']!,
          {'name': 'RAW', 'kind': 'WEEKLY', 'weekday': 1, 'ppvMonth': 3});
      expect(body['weekday'], 1);
      expect(body.containsKey('ppvMonth'), isFalse);
    });

    test('editar show semanal manda nights=1 (hiddenValue) e limpa o PLE', () {
      final body = buildBody(resources['shows']!,
          {'name': 'RAW', 'kind': 'WEEKLY', 'nights': 2}, original: {'id': 's'});
      expect(body['nights'], 1);
      expect(body['ppvMonth'], isNull);
      expect(body.containsKey('ppvMonth'), isTrue);
    });

    test('divisão inter-gênero (X) vai como null', () {
      final body = buildBody(resources['card-divisions']!, {'name': 'D', 'gender': 'X'});
      expect(body.containsKey('gender'), isFalse); // criação não manda null
      final edit = buildBody(resources['card-divisions']!, {'name': 'D', 'gender': 'X'},
          original: {'id': 'd', 'gender': 'M'});
      expect(edit['gender'], isNull);
    });
  });

  group('autofill do episódio ao escolher o show', () {
    final f = resources['episodes']!.fields.firstWhere((x) => x.key == 'showId');
    test('herda nome e imagem do show', () {
      final r = f.autofill!('s1', (k, id) => {'id': id, 'name': 'RAW', 'imageUrl': 'https://img'});
      expect(r, {'title': 'RAW', 'imageUrl': 'https://img'});
    });
    test('show sem imagem limpa a imagem sugerida', () {
      final r = f.autofill!('s1', (k, id) => {'id': id, 'name': 'NXT'});
      expect(r['imageUrl'], isNull);
    });
  });

  group('rótulos', () {
    test('episódio mostra título ou show/mês/semana/noite', () {
      final label = resources['episodes']!.label;
      expect(label({'show': {'name': 'RAW'}, 'month': 8, 'week': 2}), 'RAW — Agosto S2');
      expect(label({'show': {'name': 'WM'}, 'month': 4, 'night': 2}), 'WM — Abril · Noite 2');
      expect(label({'title': 'Especial', 'month': 1}), 'Especial (Janeiro)');
    });

    test('todos os recursos têm campos e colunas', () {
      for (final r in resources.values) {
        expect(r.fields, isNotEmpty, reason: r.key);
        expect(r.columns, isNotEmpty, reason: r.key);
        expect(groups, contains(r.group), reason: r.key);
      }
      expect(resources.length, 16);
    });
  });
}
