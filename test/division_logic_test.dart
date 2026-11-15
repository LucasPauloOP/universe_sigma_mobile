import 'package:flutter_test/flutter_test.dart';
import 'package:universe_sigma_mobile/core/division_logic.dart';
import 'package:universe_sigma_mobile/core/models.dart';

void main() {
  final division = <String, dynamic>{
    'id': 'd1',
    'gender': 'M',
    'isActive': true,
    'title': {'name': 'World', 'isTag': false},
    'brands': [{'brandId': 'b1', 'brand': {'name': 'RAW'}}],
    'champions': [{'wrestlerId': 'w1', 'name': 'Cena'}],
    'entries': [
      {'id': 'e1', 'wrestlerId': 'w1', 'wrestler': {'name': 'Cena'}},
      {'id': 'e2', 'wrestlerId': 'w2', 'wrestler': {'name': 'Punk'}},
      {'id': 'e3', 'teamId': 't1', 'team': {'name': 'Time'}},
    ],
  };

  test('chaves das entradas e corpo do PUT', () {
    final keys = division.list('entries').map(entryKey).toList();
    expect(keys, ['w:w1', 'w:w2', 't:t1']);
    expect(entriesBody(keys), [{'wrestlerId': 'w1'}, {'wrestlerId': 'w2'}, {'teamId': 't1'}]);
    expect(entryName(division.list('entries')[2]), 'Time');
  });

  test('campeão: quem está no topo e rótulo', () {
    final e = division.list('entries');
    expect(isChampion(division, e[0]), isTrue);
    expect(isChampion(division, e[1]), isFalse);
    expect(championLabel(division), 'Cena');
    expect(championLabel({...division, 'champions': []}), '');
  });

  test('reordenar e subir ao topo', () {
    final keys = ['a', 'b', 'c', 'd'];
    expect(moved(keys, 3, 0), ['d', 'a', 'b', 'c']);
    expect(moved(keys, 0, 2), ['b', 'c', 'a', 'd']);
    expect(toTop(keys, 'c'), ['c', 'a', 'b', 'd']);
    expect(keys, ['a', 'b', 'c', 'd']); // não muda a lista original
  });

  test('marcas e divisões visíveis (inativas e compartilhadas)', () {
    final shared = <String, dynamic>{
      'id': 'd2', 'isActive': true,
      'brands': [{'brandId': 'b1', 'brand': {'name': 'RAW'}}, {'brandId': 'b2', 'brand': {'name': 'SmackDown'}}],
    };
    final inactive = <String, dynamic>{
      'id': 'd3', 'isActive': false,
      'brands': [{'brandId': 'b3', 'brand': {'name': 'NXT'}}],
    };
    final all = [division, shared, inactive];
    expect(brandOptions(all).map((b) => b.name), ['RAW', 'SmackDown']); // NXT só tem divisão inativa
    expect(visibleDivisions(all, 'b1').map((d) => d.id), ['d1', 'd2']);
    expect(visibleDivisions(all, 'b2').map((d) => d.id), ['d2']);
    expect(visibleDivisions(all, 'b3'), isEmpty);
  });

  test('opções para adicionar: sem quem já está na divisão, ordenadas', () {
    final wrestlers = <Entity>[
      {'id': 'w1', 'name': 'Cena'}, {'id': 'w2', 'name': 'Punk'}, {'id': 'w3', 'name': 'Orton'}, {'id': 'w4', 'name': 'AJ'},
    ];
    final teams = <Entity>[{'id': 't1', 'name': 'Time'}, {'id': 't2', 'name': 'Outro'}];
    final o = pickerOptions(division, wrestlers, teams);
    expect(o.wrestlers.map((x) => x.name), ['AJ', 'Orton']);
    expect(o.teams.map((x) => x.key), ['t:t2']);
    expect(isTagDivision(division), isFalse);
    expect(isTagDivision({'title': {'isTag': true}}), isTrue);
  });

  test('validação do campeão', () {
    expect(championValid(isTag: false, teamId: null, wrestlerIds: []), isTrue); // vago
    expect(championValid(isTag: false, teamId: null, wrestlerIds: ['a']), isTrue);
    expect(championValid(isTag: false, teamId: null, wrestlerIds: ['a', 'b']), isFalse);
    expect(championValid(isTag: true, teamId: 't', wrestlerIds: []), isTrue);
    expect(championValid(isTag: true, teamId: null, wrestlerIds: ['a', 'b']), isTrue);
    expect(championValid(isTag: true, teamId: null, wrestlerIds: ['a']), isFalse);
    expect(championValid(isTag: true, teamId: null, wrestlerIds: []), isTrue);
  });

  test('corpo da troca de campeão', () {
    expect(championBody('fix', wrestlerIds: ['a']), {'mode': 'fix', 'holders': [{'wrestlerId': 'a'}]});
    expect(championBody('change', teamId: 't'), {'mode': 'change', 'holders': [{'teamId': 't'}]});
    expect(championBody('fix')['holders'], isEmpty);
  });
}
