/// Definições declarativas dos recursos (CRUD genérico). Porte de
/// universe_sigma_frontend/src/app/core/resources.ts — manter os dois alinhados.
library;

import '../core/format.dart';
import '../core/rivalry_logic.dart';
import '../core/models.dart';
import 'resource_def.dart';

// ───────────── opções ─────────────

final gender = opts({'M': 'Masculino', 'W': 'Feminino'});
final contract = opts({
  'FULL_TIME': 'Full time',
  'PART_TIME': 'Part time',
  'LEGEND': 'Lenda',
  'FREE_AGENT': 'Free agent',
  'MANAGER': 'Manager',
  'GM': 'GM',
  'CELEBRITY': 'Celebridade',
  'VARIANT': 'Variante',
});
final showKind = opts({'WEEKLY': 'Semanal', 'PLE': 'PLE / PPV', 'SPECIAL': 'Especial'});
final teamKind = opts({'TAG_TEAM': 'Dupla / Tag team', 'FACTION': 'Facção'});
final editStatus = opts({'COMPLETE': 'Completo', 'NEEDED': 'Precisa editar'});
final episodeStatus = opts({
  'UNPLANNED': 'Sem planejamento',
  'PLANNED': 'Planejado',
  'DONE': 'Realizado',
});
final tournamentFormat = opts({
  'SINGLE_ELIMINATION': 'Eliminatória simples',
  'ROUND_ROBIN': 'Pontos corridos (grupos)',
});
final tournamentStatus = opts({
  'PLANNED': 'Planejado',
  'ONGOING': 'Em andamento',
  'FINISHED': 'Finalizado',
});
/// Lado vencedor da rivalidade (A = 1, B = 2).
const rivalryWinnerOptions = [Option(1, 'Lado A'), Option(2, 'Lado B')];

const genderDivision = [
  Option('M', 'Masculino'),
  Option('W', 'Feminino'),
  Option('X', 'Inter-gênero'),
];
final segmentType = opts({'MATCH': 'Luta', 'PROMO': 'Promo', 'OTHER': 'Outro'});
final finishType = opts({
  'PINFALL': 'Pinfall',
  'SUBMISSION': 'Submission',
  'COUNTOUT': 'Count out',
  'DQ': 'Desqualificação',
  'OTHER': 'Outro',
});
final stakes = opts({'NONE': 'Nenhum', 'RANKING': 'Ranking', 'CONTENDER': 'Contender'});

final monthOptions = [for (var i = 0; i < 12; i++) Option(i + 1, months[i])];
final weekdayOptions = [for (var i = 0; i < 7; i++) Option(i, weekdays[i])];

// ───────────── helpers ─────────────

String _byName(Entity e) => (e['name'] as String?) ?? '';
String _join(Entity e, String key, String? Function(Entity) pick) =>
    e.list(key).map(pick).whereType<String>().join('|');

FieldDef _name({String label = 'Nome'}) =>
    FieldDef('name', label, FieldType.text, required: true);
const _description = FieldDef('description', 'Descrição', FieldType.textarea);
const _isActive = FieldDef('isActive', 'Ativo', FieldType.boolean, defaultValue: true);
const _image = FieldDef('imageUrl', 'Imagem', FieldType.image);
const _imageCol = ColumnDef('imageUrl', '', type: ColumnType.image);

FieldDef _dateField(String key, String label, {bool required = false, String? hint}) => FieldDef(
      key,
      label,
      FieldType.date,
      required: required,
      hint: hint,
      fromEntity: (e) => isoToLocalDate(e[key] as String?),
      toBody: (v) => localDateToIso(v as DateTime?),
    );

Resource _lookup(String key, String singular, String plural) => Resource(
      key: key,
      singular: singular,
      plural: plural,
      group: 'Roster',
      label: _byName,
      fields: [_name(), _description, _isActive],
      columns: const [
        ColumnDef('name', 'Nome'),
        ColumnDef('description', 'Descrição'),
        ColumnDef('isActive', 'Ativo', type: ColumnType.bool),
      ],
    );

String episodeLabel(Entity e) {
  final show = e.obj('show')?['name'] as String? ?? 'Episódio';
  final m = monthName((e['month'] as num?)?.toInt());
  final night = e['night'] != null ? ' · Noite ${e['night']}' : '';
  final title = e['title'] as String?;
  if (title != null && title.isNotEmpty) return '$title ($m)';
  return '$show — $m${e['week'] != null ? ' S${e['week']}' : ''}$night';
}

String _dayOf(Entity e) => gameDayName(EpisodeLike.fromEntity(e));

List<Option> _intOptions(Iterable<int> values, String Function(int) label) =>
    [for (final v in values) Option(v, label(v))];

// ───────────── recursos ─────────────

final Map<String, Resource> resources = {
  'wrestlers': Resource(
    key: 'wrestlers',
    singular: 'Lutador',
    plural: 'Lutadores',
    group: 'Roster',
    label: _byName,
    filters: const ['gender', 'contractType', 'isActive', 'isInjured', 'inTagDivision', 'editStatus', 'alignmentId', 'divisionId', 'weightClassId'],
    rowActions: const [RowAction(RowActionKind.wrestlerRecord, 'Retrospecto', 'chart')],
    columns: [
      _imageCol,
      const ColumnDef('name', 'Nome'),
      ColumnDef('gender', 'Gênero', render: (e, _) => labelOfOption(gender, e['gender'])),
      ColumnDef('contractType', 'Contrato', render: (e, _) => labelOfOption(contract, e['contractType'])),
      const ColumnDef('overall', 'OVR'),
      ColumnDef('brands', 'Brands', type: ColumnType.chips, render: (e, _) => _join(e, 'brands', (b) => b.obj('brand')?['name'] as String?)),
      ColumnDef('alignmentId', 'Alinhamento', render: (e, _) => e.obj('alignment')?['name'] as String? ?? ''),
      const ColumnDef('isInjured', 'Lesionado', type: ColumnType.bool),
      const ColumnDef('isActive', 'Ativo', type: ColumnType.bool),
    ],
    fields: [
      _name(),
      FieldDef('gender', 'Gênero', FieldType.select, required: true, options: gender),
      FieldDef('contractType', 'Contrato', FieldType.select, options: contract, defaultValue: 'FULL_TIME'),
      const FieldDef('overall', 'Overall', FieldType.number, min: 0, max: 100),
      FieldDef('brandIds', 'Brands', FieldType.refMulti, ref: 'brands', defaultValue: const <String>[], fromEntity: (e) => e.list('brands').map((b) => b['brandId']).toList()),
      const FieldDef('alignmentId', 'Alinhamento', FieldType.ref, ref: 'alignments'),
      const FieldDef('divisionId', 'Categoria', FieldType.ref, ref: 'divisions'),
      const FieldDef('weightClassId', 'Categoria de peso', FieldType.ref, ref: 'weight-classes'),
      FieldDef('editStatus', 'Edição', FieldType.select, options: editStatus, defaultValue: 'COMPLETE'),
      const FieldDef('finisher', 'Finisher', FieldType.text),
      const FieldDef('signature', 'Signature', FieldType.text),
      const FieldDef('hometown', 'Cidade natal', FieldType.text),
      const FieldDef('hasContract', 'Contrato ativo', FieldType.boolean, defaultValue: false),
      const FieldDef('isActive', 'Ativo no universe', FieldType.boolean, defaultValue: true),
      const FieldDef('isInjured', 'Lesionado', FieldType.boolean, defaultValue: false),
      const FieldDef('inTagDivision', 'Divisão de tag', FieldType.boolean, defaultValue: false),
      const FieldDef('isCustomCharacter', 'Personagem criado (CAW)', FieldType.boolean, defaultValue: false),
      _image,
      const FieldDef('notes', 'Notas', FieldType.textarea),
    ],
  ),
  'teams': Resource(
    key: 'teams',
    singular: 'Dupla / Facção',
    plural: 'Duplas e Facções',
    group: 'Roster',
    label: _byName,
    filters: const ['kind', 'factionId'],
    columns: [
      _imageCol,
      const ColumnDef('name', 'Nome'),
      ColumnDef('kind', 'Tipo', render: (e, _) => labelOfOption(teamKind, e['kind'])),
      ColumnDef('faction', 'Facção', render: (e, _) => e.obj('faction')?['name'] as String? ?? ''),
      ColumnDef('subTeams', 'Duplas da facção', type: ColumnType.chips, render: (e, _) => _join(e, 'subTeams', (t) => t['name'] as String?)),
      ColumnDef('members', 'Integrantes', type: ColumnType.chips, render: (e, _) => _join(e, 'members', (m) => m.obj('wrestler')?['name'] as String?)),
    ],
    fields: [
      _name(),
      FieldDef('kind', 'Tipo', FieldType.select, options: teamKind, defaultValue: 'TAG_TEAM'),
      FieldDef('factionId', 'Facção', FieldType.ref, ref: 'teams', refWhere: (t) => t['kind'] == 'FACTION', hint: 'Opcional: a dupla faz parte de uma facção (ex.: Creed Brothers em American Made).', showIf: (v) => v['kind'] != 'FACTION'),
      FieldDef('memberIds', 'Integrantes', FieldType.refMulti, ref: 'wrestlers', defaultValue: const <String>[], fromEntity: (e) => e.list('members').map((m) => m['wrestlerId']).toList()),
      _image,
    ],
  ),
  'brands': Resource(
    key: 'brands',
    singular: 'Brand',
    plural: 'Brands',
    group: 'Roster',
    label: _byName,
    columns: const [
      _imageCol,
      ColumnDef('name', 'Nome'),
      ColumnDef('gm', 'GM'),
      ColumnDef('color', 'Cor'),
      ColumnDef('isActive', 'Ativa', type: ColumnType.switchy),
    ],
    fields: [
      _name(),
      const FieldDef('gm', 'GM', FieldType.text),
      const FieldDef('color', 'Cor', FieldType.color),
      const FieldDef('isActive', 'Brand ativa', FieldType.boolean, defaultValue: true, hint: 'Desativar também desativa os shows dela e apaga os episódios'),
      _description,
      _image,
    ],
  ),
  'rivalries': Resource(
    key: 'rivalries',
    singular: 'Rivalidade',
    plural: 'Rivalidades',
    group: 'Shows',
    label: _byName,
    filters: const ['isActive'],
    columns: [
      const ColumnDef('name', 'Rivalidade'),
      ColumnDef('status', 'Situação', render: (e, _) => e['isActive'] == true ? 'Em andamento' : 'Encerrada'),
      ColumnDef('sides', 'Lados', render: (e, _) => rivalryVs(e)),
      ColumnDef('winner', 'Ganhador', render: (e, _) => rivalryWinner(e)),
      ColumnDef('startDate', 'Início', render: (e, _) => fmtDate(e['startDate'] as String?)),
      ColumnDef('endDate', 'Fim', render: (e, _) => fmtDate(e['endDate'] as String?)),
      const ColumnDef('isActive', 'Ativa', type: ColumnType.bool),
    ],
    fields: [
      _name(),
      FieldDef('sideAWrestlerIds', 'Lado A: lutadores', FieldType.refMulti, ref: 'wrestlers', defaultValue: const <String>[], fromEntity: (e) => rivalryIds(e, 1, 'wrestlerId')),
      FieldDef('sideATeamIds', 'Lado A: duplas e facções', FieldType.refMulti, ref: 'teams', defaultValue: const <String>[], fromEntity: (e) => rivalryIds(e, 1, 'teamId')),
      FieldDef('sideBWrestlerIds', 'Lado B: lutadores', FieldType.refMulti, ref: 'wrestlers', defaultValue: const <String>[], fromEntity: (e) => rivalryIds(e, 2, 'wrestlerId')),
      FieldDef('sideBTeamIds', 'Lado B: duplas e facções', FieldType.refMulti, ref: 'teams', defaultValue: const <String>[], fromEntity: (e) => rivalryIds(e, 2, 'teamId')),
      const FieldDef('winnerSide', 'Ganhador', FieldType.select, options: rivalryWinnerOptions, hint: 'Preenchido sozinho quando a luta que encerra a rivalidade é finalizada com vencedor'),
      _dateField('startDate', 'Início'),
      _dateField('endDate', 'Fim'),
      const FieldDef('isActive', 'Ativa', FieldType.boolean, defaultValue: true),
      _description,
    ],
  ),
  'card-divisions': Resource(
    key: 'card-divisions',
    singular: 'Divisão',
    plural: 'Cadastro de divisões',
    group: 'Roster',
    filters: const ['titleId', 'isActive'],
    label: (e) {
      final brands = e.list('brands').map((b) => b.obj('brand')?['name']).whereType<String>().toList();
      final where = brands.length == 1 ? '${brands.first} — ' : '';
      return '$where${e['name']}${brands.length > 1 ? ' (todos os shows)' : ''}';
    },
    columns: [
      ColumnDef('brands', 'Brands', type: ColumnType.chips, render: (e, _) => _join(e, 'brands', (b) => b.obj('brand')?['name'] as String?)),
      const ColumnDef('name', 'Divisão'),
      ColumnDef('gender', 'Gênero', render: (e, _) => labelOfOption(genderDivision, e['gender'] ?? 'X')),
      ColumnDef('titleId', 'Título', render: (e, _) => e.obj('title')?['name'] as String? ?? '—'),
      ColumnDef('entries', 'Colocados', render: (e, _) => '${e.list('entries').length}'),
      const ColumnDef('isActive', 'Ativa', type: ColumnType.bool),
    ],
    fields: [
      _name(label: 'Nome (ex.: Main Card Masculino, Lendas Feminino)'),
      FieldDef('gender', 'Gênero', FieldType.select, required: true, defaultValue: 'M', options: genderDivision, fromEntity: (e) => e['gender'] ?? 'X', toBody: (v) => v == 'X' ? null : v, hint: 'Inter-gênero mistura lutadores e lutadoras na mesma divisão.'),
      FieldDef('brandIds', 'Brands (shows) da divisão', FieldType.refMulti, ref: 'brands', defaultValue: const <String>[], fromEntity: (e) => e.list('brands').map((b) => b['brandId']).toList(), hint: 'Uma divisão pode valer para mais de um show (ex.: Tag Team feminino, Managers).'),
      const FieldDef('titleId', 'Título que a divisão disputa', FieldType.ref, ref: 'titles', hint: 'O campeão deste título fica acima do ranking'),
      const FieldDef('order', 'Ordem de exibição', FieldType.number, min: 0, defaultValue: 0),
      const FieldDef('isActive', 'Divisão ativa', FieldType.boolean, defaultValue: true),
    ],
  ),
  'alignments': _lookup('alignments', 'Alinhamento', 'Alinhamentos'),
  'divisions': _lookup('divisions', 'Categoria', 'Categorias'),
  'weight-classes': _lookup('weight-classes', 'Categoria de peso', 'Categorias de peso'),
  'titles': Resource(
    key: 'titles',
    singular: 'Título',
    plural: 'Títulos',
    group: 'Títulos',
    label: _byName,
    filters: const ['brandId', 'gender', 'isTag', 'isActive'],
    rowActions: const [RowAction(RowActionKind.titleHistory, 'Histórico de reinados', 'history')],
    columns: [
      _imageCol,
      const ColumnDef('name', 'Nome'),
      ColumnDef('brandId', 'Brand', render: (e, _) => e.obj('brand')?['name'] as String? ?? ''),
      ColumnDef('gender', 'Gênero', render: (e, _) => e['gender'] != null ? labelOfOption(gender, e['gender']) : ''),
      const ColumnDef('isTag', 'Tag', type: ColumnType.bool),
      const ColumnDef('isActive', 'Ativo', type: ColumnType.bool),
    ],
    fields: [
      _name(),
      const FieldDef('brandId', 'Brand', FieldType.ref, ref: 'brands'),
      FieldDef('gender', 'Gênero', FieldType.select, options: gender),
      const FieldDef('isTag', 'Título de duplas', FieldType.boolean, defaultValue: false),
      _isActive,
      _image,
    ],
  ),
  'title-reigns': Resource(
    key: 'title-reigns',
    singular: 'Reinado',
    plural: 'Reinados',
    group: 'Títulos',
    filters: const ['titleId'],
    label: (e) => '${e.obj('title')?['name'] ?? 'Título'} — ${fmtDate(e['startDate'] as String?)}',
    columns: [
      ColumnDef('titleId', 'Título', render: (e, _) => e.obj('title')?['name'] as String? ?? ''),
      ColumnDef('holders', 'Campeões', type: ColumnType.chips, render: (e, _) => _join(e, 'holders', (h) => (h.obj('wrestler')?['name'] ?? h.obj('team')?['name']) as String?)),
      ColumnDef('startDate', 'Início', render: (e, _) => fmtDate(e['startDate'] as String?)),
      ColumnDef('endDate', 'Fim', render: (e, _) => e['endDate'] != null ? fmtDate(e['endDate'] as String?) : 'Atual'),
    ],
    fields: [
      const FieldDef('titleId', 'Título', FieldType.ref, ref: 'titles', required: true),
      _dateField('startDate', 'Início', required: true),
      _dateField('endDate', 'Fim (vazio = campeão atual)'),
      FieldDef('wrestlerHolderIds', 'Lutadores campeões', FieldType.refMulti, ref: 'wrestlers', defaultValue: const <String>[], fromEntity: (e) => e.list('holders').where((h) => h['wrestlerId'] != null).map((h) => h['wrestlerId']).toList()),
      FieldDef('teamHolderIds', 'Duplas campeãs', FieldType.refMulti, ref: 'teams', defaultValue: const <String>[], fromEntity: (e) => e.list('holders').where((h) => h['teamId'] != null).map((h) => h['teamId']).toList()),
    ],
  ),
  'title-baselines': Resource(
    key: 'title-baselines',
    singular: 'Histórico de reinados',
    plural: 'Histórico anterior',
    group: 'Títulos',
    toolbar: Toolbar.importHistory,
    filters: const ['titleId'],
    label: (e) => '${e.obj('wrestler')?['name'] ?? e.obj('team')?['name'] ?? '?'} — ${e.obj('title')?['name'] ?? ''}',
    columns: [
      ColumnDef('titleId', 'Título', render: (e, _) => e.obj('title')?['name'] as String? ?? ''),
      ColumnDef('holder', 'Campeão', render: (e, _) => (e.obj('wrestler')?['name'] ?? e.obj('team')?['name'] ?? '') as String),
      const ColumnDef('reigns', 'Reinados'),
      const ColumnDef('days', 'Dias'),
      const ColumnDef('note', 'Nota'),
    ],
    fields: const [
      FieldDef('titleId', 'Título', FieldType.ref, ref: 'titles', required: true),
      FieldDef('wrestlerId', 'Lutador', FieldType.ref, ref: 'wrestlers', hint: 'Informe o lutador OU a dupla'),
      FieldDef('teamId', 'Dupla / facção', FieldType.ref, ref: 'teams'),
      FieldDef('reigns', 'Vezes campeão (antes do universe)', FieldType.number, required: true, min: 0, defaultValue: 0),
      FieldDef('days', 'Total de dias com o cinturão', FieldType.number, required: true, min: 0, defaultValue: 0),
      FieldDef('note', 'Nota', FieldType.text),
    ],
  ),
  'seasons': Resource(
    key: 'seasons',
    singular: 'Temporada',
    plural: 'Temporadas',
    group: 'Shows',
    label: (e) => (e['name'] as String?)?.isNotEmpty == true ? e['name'] as String : 'Temporada ${e['number']}',
    columns: [
      const ColumnDef('number', 'Nº'),
      const ColumnDef('name', 'Nome'),
      ColumnDef('startMonth', 'Universe começa em', render: (e, _) => monthName((e['startMonth'] as num?)?.toInt() ?? 5)),
      ColumnDef('startDate', 'Início', render: (e, _) => fmtDate(e['startDate'] as String?)),
    ],
    fields: [
      const FieldDef('number', 'Número', FieldType.number, required: true, min: 1),
      const FieldDef('name', 'Nome', FieldType.text),
      FieldDef(
        'startMonth',
        'Em que mês o universe começa nesta temporada?',
        FieldType.select,
        required: true,
        defaultValue: 5,
        options: [for (final m in seasonMonths) Option(m, months[m - 1])],
        hint: 'A temporada vai de maio a abril. Os episódios dos meses anteriores ao escolhido ficam de fora e o próximo episódio a jogar é calculado a partir dele.',
      ),
      _dateField('startDate', 'Início'),
    ],
  ),
  'shows': Resource(
    key: 'shows',
    singular: 'Show',
    plural: 'Shows',
    group: 'Shows',
    label: _byName,
    filters: const ['brandId', 'kind'],
    columns: [
      _imageCol,
      const ColumnDef('name', 'Nome'),
      ColumnDef('kind', 'Tipo', render: (e, _) => labelOfOption(showKind, e['kind'])),
      ColumnDef('brandId', 'Brand', render: (e, _) => e.obj('brand')?['name'] as String? ?? ''),
      ColumnDef('weekday', 'Dia', render: (e, _) => e['weekday'] == null ? '' : weekdays[(e['weekday'] as num).toInt()]),
      ColumnDef('ppvMonth', 'Mês do PLE', render: (e, _) => e['ppvMonth'] != null ? '${monthName((e['ppvMonth'] as num).toInt())}${e['ppvWeek'] != null ? ' · semana ${e['ppvWeek']}' : ''}' : ''),
      ColumnDef('nights', 'Noites', render: (e, _) => e['kind'] != 'WEEKLY' && ((e['nights'] as num?) ?? 1) > 1 ? '${e['nights']} noites' : ''),
      const ColumnDef('isActive', 'Ativo', type: ColumnType.switchy),
    ],
    fields: [
      _name(),
      FieldDef('kind', 'Tipo', FieldType.select, required: true, options: showKind, defaultValue: 'WEEKLY'),
      const FieldDef('brandId', 'Brand', FieldType.ref, ref: 'brands'),
      FieldDef('weekday', 'Dia da semana em que acontece', FieldType.select, options: weekdayOptions, hint: 'Define a data dos episódios: semana 2 = a 2ª ocorrência desse dia no mês. Vazio: semanal = segunda, PLE = sábado.'),
      FieldDef('ppvMonth', 'Mês do PLE', FieldType.select, options: monthOptions, showIf: (v) => v['kind'] != 'WEEKLY'),
      FieldDef('ppvWeek', 'Semana do PLE', FieldType.select, options: _intOptions([1, 2, 3, 4], (n) => 'Semana $n'), showIf: (v) => v['kind'] != 'WEEKLY'),
      FieldDef('nights', 'Noites', FieldType.select, required: true, defaultValue: 1, hiddenValue: 1, options: const [Option(1, '1 noite'), Option(2, '2 noites (Noite 1 e Noite 2)')], showIf: (v) => v['kind'] != 'WEEKLY', hint: 'Cada noite vira um episódio com o seu próprio card (use “Gerar episódios”).'),
      const FieldDef('isActive', 'Show ativo', FieldType.boolean, defaultValue: true, hint: 'Desativar apaga todos os episódios do show'),
      _image,
    ],
  ),
  'episodes': Resource(
    key: 'episodes',
    singular: 'Episódio',
    plural: 'Episódios',
    group: 'Shows',
    label: episodeLabel,
    filters: const ['showId', 'seasonId', 'month', 'status'],
    toolbar: Toolbar.generateEpisodes,
    rowActions: const [RowAction(RowActionKind.episodeCard, 'Abrir card', 'list')],
    columns: [
      ColumnDef('showId', 'Show', render: (e, _) => e.obj('show')?['name'] as String? ?? ''),
      const ColumnDef('title', 'Título'),
      ColumnDef('seasonId', 'Temporada', render: (e, n) => n('seasons', e['seasonId'] as String?)),
      ColumnDef('month', 'Mês', render: (e, _) => monthName((e['month'] as num?)?.toInt())),
      const ColumnDef('week', 'Semana'),
      ColumnDef('night', 'Noite', render: (e, _) => e['night'] != null ? 'Noite ${e['night']}' : ''),
      ColumnDef('day', 'Dia', render: (e, _) => _dayOf(e)),
      ColumnDef('status', 'Status', render: (e, _) => labelOfOption(episodeStatus, e['status'])),
    ],
    fields: [
      FieldDef(
        'showId',
        'Show',
        FieldType.ref,
        ref: 'shows',
        required: true,
        autofillLabel: 'Importar título e imagem do show',
        autofill: (id, find) {
          final show = id != null ? find('shows', id) : null;
          return {'title': show?['name'] ?? '', 'imageUrl': show?['imageUrl']};
        },
      ),
      const FieldDef('seasonId', 'Temporada', FieldType.ref, ref: 'seasons', required: true),
      const FieldDef('title', 'Título', FieldType.text),
      FieldDef('month', 'Mês', FieldType.select, required: true, options: monthOptions),
      const FieldDef('week', 'Semana do mês (1 a 4)', FieldType.number, min: 1, max: 4, hint: 'Ex.: semana 2 de agosto. Não precisa de data exata.'),
      const FieldDef('night', 'Noite (só PLE em duas noites)', FieldType.select, options: [Option(1, 'Noite 1'), Option(2, 'Noite 2')]),
      _dateField('airDate', 'Data (opcional)', hint: 'Normalmente deixe vazio: o dia vem do dia da semana do show e da semana do mês (todo mês tem 4 semanas).'),
      FieldDef('status', 'Status', FieldType.select, options: episodeStatus, defaultValue: 'UNPLANNED'),
      _image,
      const FieldDef('notes', 'Notas', FieldType.textarea),
    ],
  ),
  'match-types': const Resource(
    key: 'match-types',
    singular: 'Tipo de luta',
    plural: 'Tipos de luta',
    group: 'Shows',
    label: _byName,
    columns: [ColumnDef('name', 'Nome')],
    fields: [FieldDef('name', 'Nome', FieldType.text, required: true)],
  ),
  'tournaments': Resource(
    key: 'tournaments',
    singular: 'Torneio',
    plural: 'Torneios',
    group: 'Torneios',
    label: _byName,
    filters: const ['seasonId', 'status', 'format'],
    rowActions: const [RowAction(RowActionKind.tournamentBracket, 'Abrir chave', 'sitemap')],
    columns: [
      _imageCol,
      const ColumnDef('name', 'Nome'),
      ColumnDef('format', 'Formato', render: (e, _) => labelOfOption(tournamentFormat, e['format'])),
      const ColumnDef('size', 'Vagas'),
      const ColumnDef('isTag', 'Duplas', type: ColumnType.bool),
      ColumnDef('status', 'Status', render: (e, _) => labelOfOption(tournamentStatus, e['status'])),
      ColumnDef('entrants', 'Inscritos', render: (e, _) => '${e.obj('_count')?['entrants'] ?? 0}'),
    ],
    fields: [
      _name(),
      FieldDef('format', 'Formato', FieldType.select, options: tournamentFormat, defaultValue: 'SINGLE_ELIMINATION'),
      const FieldDef('size', 'Vagas (inscritos previstos)', FieldType.number, required: true, min: 2, max: 64, defaultValue: 8),
      FieldDef('firstRoundMatches', 'Lutas na 1ª rodada', FieldType.number, min: 1, max: 32, showIf: (v) => v['format'] != 'ROUND_ROBIN', hint: 'Potência de 2 (1, 2, 4, 8...). Ex.: 2 = duas semifinais e a final. Vazio = deduzido das vagas.'),
      FieldDef('firstRoundPerMatch', 'Competidores por luta (1ª rodada)', FieldType.number, min: 2, max: 8, showIf: (v) => v['format'] != 'ROUND_ROBIN', hint: '3 = triple threat, 4 = fatal 4-way. As rodadas seguintes são 1 contra 1 (o vencedor de cada luta avança).'),
      const FieldDef('seasonId', 'Temporada', FieldType.ref, ref: 'seasons'),
      FieldDef('status', 'Status', FieldType.select, options: tournamentStatus, defaultValue: 'PLANNED'),
      const FieldDef('isTag', 'Torneio de duplas', FieldType.boolean, defaultValue: false),
      _dateField('startDate', 'Início'),
      _dateField('endDate', 'Fim'),
      _image,
      const FieldDef('notes', 'Notas', FieldType.textarea),
    ],
  ),
};

const groups = ['Roster', 'Títulos', 'Shows', 'Torneios'];

/// Corpo do request a partir dos valores do formulário (porte do `buildBody` do web).
Map<String, Object?> buildBody(
  Resource res,
  Map<String, Object?> values, {
  Entity? original,
}) {
  final body = <String, Object?>{};
  for (final f in res.fields) {
    if (f.showIf != null && !f.showIf!(values)) {
      // campo escondido: limpa o valor ao editar
      if (original != null) body[f.key] = f.hiddenValue;
      continue;
    }
    var v = values[f.key];
    // imageUrl vem da API como URL assinada temporária: só reenvia se mudou.
    if (f.type == FieldType.image && original != null && v == original[f.key]) continue;
    if (f.toBody != null) v = f.toBody!(v);
    if (v == '' ) v = null;
    if (f.type == FieldType.number && v != null) v = v is num ? v : num.parse('$v');
    // criação: não manda nulos (deixa o default do backend agir)
    if (original == null && v == null) continue;
    body[f.key] = v;
  }
  // titleReign: junta lutadores e duplas em `holders`
  if (res.key == 'title-reigns') {
    body['holders'] = [
      for (final id in (values['wrestlerHolderIds'] as List? ?? const [])) {'wrestlerId': id},
      for (final id in (values['teamHolderIds'] as List? ?? const [])) {'teamId': id},
    ];
    body.remove('wrestlerHolderIds');
    body.remove('teamHolderIds');
  }
  return body;
}
