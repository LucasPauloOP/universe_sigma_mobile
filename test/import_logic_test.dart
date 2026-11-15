import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:universe_sigma_mobile/core/import_logic.dart';

void main() {
  test('opções padrão iguais às do web', () {
    final o = defaultImportOptions();
    expect(o['createMissing'], isTrue);
    expect(o['replaceRosters'], isTrue);
    expect(o['activateWrestlers'], isTrue);
    expect(o['deactivateOthers'], isFalse);
    expect(o['importDivisions'], isTrue);
    expect(o['importPles'], isTrue);
    expect(o['deactivateUnlistedPles'], isFalse);
    expect(importOptions.length, 7);
    expect(jsonDecode(optionsJson(o))['importPles'], isTrue);
  });

  test('confirmação perigosa quando troca rosters ou desativa PLEs', () {
    expect(needsDangerConfirm(defaultImportOptions()), isTrue); // replaceRosters ligado
    final o = {...defaultImportOptions(), 'replaceRosters': false};
    expect(needsDangerConfirm(o), isFalse);
    expect(needsDangerConfirm({...o, 'deactivateUnlistedPles': true}), isTrue);
  });

  test('resumo da prévia', () {
    final report = {
      'brands': [
        {'brand': 'RAW', 'add': 5, 'remove': 2},
        {'brand': 'SD', 'add': 3, 'remove': 1},
      ],
      'newWrestlers': [{'name': 'A'}, {'name': 'B'}],
      'newTeams': [{'name': 'T'}],
      'ples': {
        'create': [{'name': 'X'}],
        'update': [{'id': '1'}, {'id': '2'}],
        'unlisted': [{'id': '9'}],
      },
    };
    expect(importSummary(report, defaultImportOptions()),
        '8 lutadores entram e 3 saem dos rosters das brands; 2 lutadores e 1 duplas serão criados; 3 PLEs criados/ajustados.');
    expect(importSummary(report, {...defaultImportOptions(), 'deactivateUnlistedPles': true}),
        contains('1 PLEs desativados (episódios apagados)'));
    expect(importSummary({'brands': []}, defaultImportOptions()), '0 lutadores entram e 0 saem dos rosters das brands.');
  });

  test('rótulo de contrato', () {
    expect(contractLabel('LEGEND'), 'Lenda');
    expect(contractLabel('MANAGER'), 'Manager');
    expect(contractLabel('FULL_TIME'), '');
    expect(contractLabel(null), '');
  });
}
