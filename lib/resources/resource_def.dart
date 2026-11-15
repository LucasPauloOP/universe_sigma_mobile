import '../core/models.dart';

enum FieldType { text, textarea, number, boolean, select, ref, refMulti, date, image, color }

class Option {
  const Option(this.value, this.label);
  final Object value;
  final String label;
}

List<Option> opts(Map<String, String> m) =>
    m.entries.map((e) => Option(e.key, e.value)).toList();

String labelOfOption(List<Option> list, Object? v) {
  for (final o in list) {
    if (o.value == v) return o.label;
  }
  return v?.toString() ?? '';
}

/// Sugere valores para outros campos ao escolher um ref (criação) ou ao pedir
/// "importar dados" (edição). Ver `autofill` do web.
typedef Autofill = Map<String, Object?> Function(
  String? id,
  Entity? Function(String key, String id) find,
);

class FieldDef {
  const FieldDef(
    this.key,
    this.label,
    this.type, {
    this.required = false,
    this.options,
    this.ref,
    this.min,
    this.max,
    this.defaultValue,
    this.hint,
    this.fromEntity,
    this.toBody,
    this.refWhere,
    this.showIf,
    this.hiddenValue,
    this.autofill,
    this.autofillLabel,
  });

  final String key;
  final String label;
  final FieldType type;
  final bool required;
  final List<Option>? options;
  final String? ref;
  final num? min;
  final num? max;
  final Object? defaultValue;
  final String? hint;

  /// valor do formulário a partir do registro (ex.: brands -> brandIds)
  final Object? Function(Entity e)? fromEntity;

  /// valor do formulário -> corpo do request
  final Object? Function(Object? v)? toBody;

  /// ref/refMulti: só lista os registros que passam no filtro (ex.: só facções)
  final bool Function(Entity e)? refWhere;

  /// só aparece quando retorna true (recebe os valores atuais)
  final bool Function(Map<String, Object?> values)? showIf;

  /// Valor enviado ao editar quando o campo está escondido (padrão: null).
  final Object? hiddenValue;
  final Autofill? autofill;
  final String? autofillLabel;
}

enum ColumnType { text, bool, image, chips, switchy }

class ColumnDef {
  const ColumnDef(this.key, this.label, {this.type = ColumnType.text, this.render});
  final String key;
  final String label;
  final ColumnType type;

  /// Texto da célula. `name(ref, id)` resolve nomes de referências.
  final String Function(Entity e, String Function(String ref, String? id) name)? render;
}

enum RowActionKind { wrestlerRecord, titleHistory, episodeCard, tournamentBracket }

class RowAction {
  const RowAction(this.kind, this.label, this.icon);
  final RowActionKind kind;
  final String label;
  final String icon; // nome simbólico; a UI mapeia para IconData
}

enum Toolbar { generateEpisodes, importHistory }

class Resource {
  const Resource({
    required this.key,
    required this.singular,
    required this.plural,
    required this.group,
    required this.fields,
    required this.columns,
    required this.label,
    this.filters = const [],
    this.rowActions = const [],
    this.toolbar,
  });

  final String key;
  final String singular;
  final String plural;
  final String group;
  final List<FieldDef> fields;
  final List<ColumnDef> columns;
  final String Function(Entity e) label;
  final List<String> filters;
  final List<RowAction> rowActions;
  final Toolbar? toolbar;
}
