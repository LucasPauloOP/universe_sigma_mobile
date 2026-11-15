import 'models.dart';

/// Chave de uma entrada da divisão: `w:<id>` (lutador) ou `t:<id>` (dupla/facção).
String entryKey(Entity e) => e['wrestlerId'] != null ? 'w:${e['wrestlerId']}' : 't:${e['teamId']}';

/// Corpo de `PUT card-divisions/:id/entries` a partir das chaves.
List<Map<String, String>> entriesBody(List<String> keys) => [
      for (final k in keys) k.startsWith('w:') ? {'wrestlerId': k.substring(2)} : {'teamId': k.substring(2)},
    ];

String entryName(Entity e) => (e.obj('wrestler')?['name'] ?? e.obj('team')?['name'] ?? '?') as String;

bool isChampion(Entity division, Entity entry) => division.list('champions').any((c) =>
    (c['wrestlerId'] != null && c['wrestlerId'] == entry['wrestlerId']) ||
    (c['teamId'] != null && c['teamId'] == entry['teamId']));

String championLabel(Entity division) => division.list('champions').map((c) => c['name']).join(' & ');

/// Marcas com divisões ativas, ordenadas por nome.
List<({String id, String name})> brandOptions(List<Entity> divisions) {
  final map = <String, String>{};
  for (final d in divisions.where((d) => d['isActive'] != false)) {
    for (final b in d.list('brands')) {
      map[b['brandId'] as String] = b.obj('brand')?['name'] as String? ?? '';
    }
  }
  return (map.entries.map((e) => (id: e.key, name: e.value)).toList())..sort((a, b) => a.name.compareTo(b.name));
}

/// Divisões da marca escolhida (as compartilhadas aparecem em todas as marcas delas).
List<Entity> visibleDivisions(List<Entity> divisions, String? brandId) => divisions
    .where((d) => d['isActive'] != false && d.list('brands').any((b) => b['brandId'] == brandId))
    .toList();

String genderLabel(Entity d) => switch (d['gender']) { 'M' => 'Masculino', 'W' => 'Feminino', _ => 'Inter-gênero' };

/// Lutadores e duplas que ainda não estão na divisão. Divisão de título de duplas lista as duplas primeiro.
({List<({String key, String name})> teams, List<({String key, String name})> wrestlers}) pickerOptions(
  Entity division,
  List<Entity> wrestlers,
  List<Entity> teams,
) {
  final used = division.list('entries').map(entryKey).toSet();
  List<({String key, String name})> free(List<Entity> l, String prefix) => [
        for (final x in l)
          if (!used.contains('$prefix:${x.id}')) (key: '$prefix:${x.id}', name: x['name'] as String? ?? ''),
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return (teams: free(teams, 't'), wrestlers: free(wrestlers, 'w'));
}

bool isTagDivision(Entity d) => d.obj('title')?['isTag'] == true;

/// Reordena as chaves (move [from] para [to], com `to` já ajustado).
List<String> moved(List<String> keys, int from, int to) {
  final l = [...keys];
  l.insert(to, l.removeAt(from));
  return l;
}

/// Sobe o lutador direto para a 1ª posição (próximo desafiante).
List<String> toTop(List<String> keys, String key) => [key, ...keys.where((k) => k != key)];

/// Valida o campeão escolhido: solo ≤ 1 lutador; tag = dupla OU 2 lutadores OU vago.
bool championValid({required bool isTag, required String? teamId, required List<String> wrestlerIds}) {
  if (!isTag) return wrestlerIds.length <= 1;
  return (teamId == null && wrestlerIds.isEmpty) || teamId != null || wrestlerIds.length == 2;
}

/// Corpo de `PUT card-divisions/:id/champion`.
Map<String, Object?> championBody(String mode, {String? teamId, List<String> wrestlerIds = const []}) => {
      'mode': mode,
      'holders': teamId != null ? [{'teamId': teamId}] : [for (final id in wrestlerIds) {'wrestlerId': id}],
    };

/// Entrada escalada: lutador na lista; dupla quando todos os integrantes estão
/// (facção: basta um).
bool isEntryScheduled(Entity entry, Set<String> scheduledWrestlerIds) {
  final wid = entry['wrestlerId'] as String?;
  if (wid != null) return scheduledWrestlerIds.contains(wid);
  final team = entry.obj('team');
  final members = [for (final m in (team?['members'] as List? ?? const [])) (m as Map)['wrestlerId'] as String];
  if (members.isEmpty) return false;
  return team?['kind'] == 'FACTION'
      ? members.any(scheduledWrestlerIds.contains)
      : members.every(scheduledWrestlerIds.contains);
}

/// Campeão escalado: lutador, ou dupla com todos os integrantes (facção: um basta).
bool isChampionScheduled(Map<String, dynamic> champion, Set<String> scheduledWrestlerIds) {
  final wid = champion['wrestlerId'] as String?;
  if (wid != null) return scheduledWrestlerIds.contains(wid);
  final members = [for (final m in (champion['members'] as List? ?? const [])) m as String];
  if (members.isEmpty) return false;
  return champion['kind'] == 'FACTION'
      ? members.any(scheduledWrestlerIds.contains)
      : members.every(scheduledWrestlerIds.contains);
}
