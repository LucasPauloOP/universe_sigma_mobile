import 'package:flutter_test/flutter_test.dart';
import 'package:universe_sigma_mobile/core/rivalry_logic.dart';

void main() {
  final rivalry = <String, dynamic>{
    'winnerSide': 2,
    'members': [
      {'side': 1, 'wrestlerId': 'w1', 'wrestler': {'name': 'Cena'}},
      {'side': 2, 'teamId': 't1', 'team': {'name': 'Usos'}},
      {'side': 2, 'wrestlerId': 'w2', 'wrestler': {'name': 'Solo'}},
    ],
  };

  test('envolvidos por lado e texto "A vs B"', () {
    expect(rivalrySides(rivalry), [['Cena'], ['Usos', 'Solo']]);
    expect(rivalryVs(rivalry), 'Cena vs Usos & Solo');
  });

  test('ganhador é o lado vencedor; sem lado, vazio', () {
    expect(rivalryWinner(rivalry), 'Usos & Solo');
    expect(rivalryWinner({...rivalry, 'winnerSide': null}), '');
  });

  test('ids por lado para o formulário', () {
    expect(rivalryIds(rivalry, 1, 'wrestlerId'), ['w1']);
    expect(rivalryIds(rivalry, 2, 'teamId'), ['t1']);
    expect(rivalryIds(rivalry, 2, 'wrestlerId'), ['w2']);
  });

  test('rótulo na luta: começa, encerra ou só ligada', () {
    final r = {'name': 'Cena vs Orton'};
    expect(rivalryLabel({'rivalry': r, 'startsRivalry': true}), 'Começa rivalidade: Cena vs Orton');
    expect(rivalryLabel({'rivalry': r, 'endsRivalry': true}), 'Encerra rivalidade: Cena vs Orton');
    expect(rivalryLabel({'rivalry': r}), 'Rivalidade: Cena vs Orton');
    expect(rivalryLabel({'rivalry': null}), '');
  });
}
