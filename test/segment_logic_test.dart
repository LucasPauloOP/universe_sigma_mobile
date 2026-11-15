import 'package:flutter_test/flutter_test.dart';
import 'package:universe_sigma_mobile/core/models.dart';
import 'package:universe_sigma_mobile/core/segment_logic.dart';

void main() {
  SegmentDraft singles() => SegmentDraft(participants: [SegParticipant('a', 1), SegParticipant('b', 2)]);

  group('resultado e vencedor', () {
    test('realizada sem vencedor/como terminou é problema; com os dois, ok', () {
      final d = singles()..isDone = true;
      expect(d.problem, contains('vencedor'));
      d.toggleWinner('a');
      expect(d.problem, contains('terminou'));
      d.finishType = 'PINFALL';
      expect(d.problem, isNull);
      expect(d.canSave, isTrue);
    });

    test('promo realizada não exige resultado', () {
      final d = SegmentDraft(type: 'PROMO', isDone: true);
      expect(d.problem, isNull);
    });

    test('empate limpa as estrelas e marcar vencedor desfaz o empate', () {
      final d = singles()..isDone = true;
      d.toggleWinner('a');
      d.setDraw(true);
      expect(d.participants.any((p) => p.isWinner), isFalse);
      expect(d.problem, isNull); // empate dispensa vencedor e finishType
      d.toggleWinner('b');
      expect(d.isDraw, isFalse);
      expect(d.participants.firstWhere((p) => p.wrestlerId == 'b').isWinner, isTrue);
    });

    test('lado inteiro vence (times) e de novo desfaz', () {
      final d = SegmentDraft(participants: [
        SegParticipant('a', 1), SegParticipant('b', 1), SegParticipant('c', 2), SegParticipant('d', 2),
      ]);
      d.toggleSideWinner(1);
      expect(d.sideWins(1), isTrue);
      expect(d.sideWins(2), isFalse);
      d.toggleSideWinner(2); // troca o vencedor
      expect(d.sideWins(1), isFalse);
      expect(d.sideWins(2), isTrue);
      d.toggleSideWinner(2);
      expect(d.participants.any((p) => p.isWinner), isFalse);
    });
  });

  group('lados e participantes', () {
    test('lutador não entra duas vezes; remover lado apaga quem estava nele', () {
      final d = singles();
      d.addParticipant(1, 'a');
      expect(d.participants.length, 2);
      d.addSide();
      d.addParticipant(3, 'c');
      expect(d.sideCount, 3);
      d.removeSide();
      expect(d.sideCount, 2);
      expect(d.participants.map((p) => p.wrestlerId), ['a', 'b']);
    });

    test('estado lido da API: quantidade de lados vem do maior lado', () {
      final d = SegmentDraft.fromEntity({
        'type': 'MATCH',
        'participants': [
          {'wrestlerId': 'a', 'side': 1, 'isWinner': true},
          {'wrestlerId': 'b', 'side': 4},
        ],
      });
      expect(d.sideCount, 4);
      expect(d.participants.first.isWinner, isTrue);
      expect(SegmentDraft.fromEntity({'type': 'PROMO'}).sideCount, 2);
    });
  });

  group('corpo do request (igual ao web)', () {
    test('luta comum', () {
      final d = singles()
        ..matchTypeId = 'mt'
        ..finishType = 'PINFALL'
        ..notes = '  main  ';
      d.toggleWinner('a');
      final b = d.toBody('ep1');
      expect(b['episodeId'], 'ep1');
      expect(b['notes'], 'main');
      expect(b['stakes'], 'NONE');
      expect(b['cardDivisionId'], isNull);
      expect(b['participants'], [
        {'wrestlerId': 'a', 'side': 1, 'isWinner': true},
        {'wrestlerId': 'b', 'side': 2, 'isWinner': false},
      ]);
    });

    test('título só vale em luta; troca de campeão exige título', () {
      final d = singles()..titleChanged = true;
      expect(d.toBody('e')['titleChanged'], isFalse); // sem título
      d.titleId = 't';
      expect(d.toBody('e')['titleChanged'], isTrue);
      d.type = 'PROMO';
      final promo = d.toBody('e');
      expect(promo['titleId'], isNull);
      expect(promo['titleChanged'], isFalse);
      expect(promo['matchTypeId'], isNull);
      expect(promo['isDraw'], isFalse);
    });

    test('ranking: divisão obrigatória quando há o que está em jogo', () {
      final d = singles()..stakes = 'RANKING';
      expect(d.missingDivision, isTrue);
      expect(d.canSave, isFalse);
      expect(d.toBody('e')['stakes'], 'NONE'); // sem divisão não manda stakes
      d.cardDivisionId = 'div';
      expect(d.missingDivision, isFalse);
      final b = d.toBody('e');
      expect(b['stakes'], 'RANKING');
      expect(b['cardDivisionId'], 'div');
    });
  });

  group('luta de torneio', () {
    final matchTypes = <Entity>[
      {'id': 'mt1', 'name': 'Singles'},
      {'id': 'mt3', 'name': 'Triple Threat'},
      {'id': 'mtt', 'name': 'Tag Team'},
    ];
    Entity w(String id) => {'wrestlerId': id, 'wrestler': {'name': id}};

    test('preenche os lados com os inscritos e sugere Singles', () {
      final d = SegmentDraft();
      d.pickTournamentMatch({'id': 'm1', 'entrantA': w('a'), 'entrantB': w('b'), 'extras': []}, matchTypes);
      expect(d.tournamentMatchId, 'm1');
      expect(d.participants.map((p) => '${p.wrestlerId}:${p.side}'), ['a:1', 'b:2']);
      expect(d.matchTypeId, 'mt1');
    });

    test('triple threat usa extras e sugere o tipo', () {
      final d = SegmentDraft();
      d.pickTournamentMatch({
        'id': 'm2',
        'entrantA': w('a'),
        'entrantB': w('b'),
        'extras': [{'entrant': w('c')}],
      }, matchTypes);
      expect(d.sideCount, 3);
      expect(d.participants.length, 3);
      expect(d.matchTypeId, 'mt3');
    });

    test('dupla vira um lado com os integrantes e sugere Tag Team', () {
      final d = SegmentDraft();
      d.pickTournamentMatch({
        'id': 'm3',
        'entrantA': {'wrestlerId': null, 'team': {'name': 'T1', 'members': [{'wrestlerId': 'a'}, {'wrestlerId': 'b'}]}},
        'entrantB': {'wrestlerId': null, 'team': {'name': 'T2', 'members': [{'wrestlerId': 'c'}, {'wrestlerId': 'd'}]}},
        'extras': [],
      }, matchTypes);
      expect(d.participants.where((p) => p.side == 1).length, 2);
      expect(d.matchTypeId, 'mtt');
    });

    test('não sobrescreve participantes já escolhidos nem o tipo de luta', () {
      final d = SegmentDraft(participants: [SegParticipant('x', 1)], matchTypeId: 'mt1');
      d.pickTournamentMatch({'id': 'm1', 'entrantA': w('a'), 'entrantB': w('b'), 'extras': []}, matchTypes);
      expect(d.participants.single.wrestlerId, 'x');
      expect(d.matchTypeId, 'mt1');
    });

    test('rótulo da luta', () {
      expect(
        tournamentMatchLabel({
          'round': 1, 'slot': 2, 'entrantA': {'wrestler': {'name': 'Cena'}}, 'entrantB': null,
          'tournament': {'name': 'KOTR', 'format': 'SINGLE_ELIMINATION', 'size': 8},
        }),
        'KOTR — Quartas de final · Luta 2: Cena x a definir',
      );
    });
  });
}
