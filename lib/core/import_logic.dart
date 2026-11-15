import 'dart:convert';

import 'models.dart';

class ImportOption {
  const ImportOption(this.key, this.label, this.hint, {this.defaultValue = true, this.danger = false});
  final String key;
  final String label;
  final String hint;
  final bool defaultValue;
  final bool danger;
}

/// Opções da importação (mesmas do web; padrão igual).
const importOptions = [
  ImportOption('createMissing', 'Criar o que a planilha cita e o universe não tem', 'Lutadores e duplas novos (gênero deduzido pela coluna; confira a lista antes de importar).'),
  ImportOption('replaceRosters', 'Trocar o roster de cada brand pelo da planilha', 'Quem está no roster da brand mas não na planilha sai dessa brand (o lutador continua existindo).', danger: true),
  ImportOption('activateWrestlers', 'Ativar no universe quem está nos rosters da planilha', ''),
  ImportOption('deactivateOthers', 'Desativar quem não está em nenhum roster da planilha', 'Só quem pertence às brands da planilha.', defaultValue: false),
  ImportOption('importDivisions', 'Preencher as divisões (colocações)', 'A fila de cada divisão passa a ser a da planilha, na mesma ordem. Cria as divisões padrão que faltarem.'),
  ImportOption('importPles', 'Cadastrar e ajustar os PLEs (mês e semana)', 'PLEs que já existem têm só o mês/semana ajustados; os que faltam são criados.'),
  ImportOption('deactivateUnlistedPles', 'Desativar PLEs que não estão na planilha', 'Atenção: apaga os episódios desses PLEs.', defaultValue: false, danger: true),
];

Map<String, bool> defaultImportOptions() => {for (final o in importOptions) o.key: o.defaultValue};

/// Valor do campo multipart `options`.
String optionsJson(Map<String, bool> options) => jsonEncode(options);

/// Pede confirmação "perigosa" quando alguma opção que apaga/troca dados está ligada.
bool needsDangerConfirm(Map<String, bool> options) =>
    options['deactivateUnlistedPles'] == true || options['replaceRosters'] == true;

/// Resumo mostrado na confirmação, a partir da prévia (`report`).
String importSummary(Entity report, Map<String, bool> options) {
  int sum(String key) => report.list('brands').fold<int>(0, (n, b) => n + ((b[key] as num?)?.toInt() ?? 0));
  final parts = <String>[
    '${sum('add')} lutadores entram e ${sum('remove')} saem dos rosters das brands',
  ];
  final newW = report.list('newWrestlers').length;
  final newT = report.list('newTeams').length;
  if (newW > 0 || newT > 0) parts.add('$newW lutadores e $newT duplas serão criados');
  final ples = report.obj('ples') ?? const {};
  final changed = ((ples['create'] as List?)?.length ?? 0) + ((ples['update'] as List?)?.length ?? 0);
  if (changed > 0) parts.add('$changed PLEs criados/ajustados');
  final unlisted = (ples['unlisted'] as List?)?.length ?? 0;
  if (options['deactivateUnlistedPles'] == true && unlisted > 0) {
    parts.add('$unlisted PLEs desativados (episódios apagados)');
  }
  return '${parts.join('; ')}.';
}

String contractLabel(String? t) => t == 'LEGEND' ? 'Lenda' : t == 'MANAGER' ? 'Manager' : '';
