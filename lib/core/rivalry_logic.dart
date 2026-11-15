import 'models.dart';

String _unit(Entity m) => (m.obj('wrestler')?['name'] ?? m.obj('team')?['name'] ?? '?') as String;

/// Envolvidos por lado (A, B...): nomes de cada lado, na ordem dos lados.
List<List<String>> rivalrySides(Entity r) {
  final members = r.list('members');
  final sides = {for (final m in members) (m['side'] as num).toInt()}.toList()..sort();
  return [
    for (final s in sides) [for (final m in members) if ((m['side'] as num).toInt() == s) _unit(m)],
  ];
}

/// "Cena vs Usos & Solo"
String rivalryVs(Entity r) => rivalrySides(r).map((s) => s.join(' & ')).join(' vs ');

/// Nomes do lado vencedor ('' se não há ganhador).
String rivalryWinner(Entity r) {
  final side = (r['winnerSide'] as num?)?.toInt();
  if (side == null) return '';
  return r.list('members').where((m) => (m['side'] as num).toInt() == side).map(_unit).join(' & ');
}

/// Ids (lutador ou time) de um lado, para o formulário.
List<String> rivalryIds(Entity r, int side, String key) => [
      for (final m in r.list('members'))
        if ((m['side'] as num).toInt() == side && m[key] != null) m[key] as String,
    ];

/// Rótulo da rivalidade numa luta do card: começa / encerra / só ligada.
String rivalryLabel(Entity segment) {
  final r = segment.obj('rivalry');
  if (r == null) return '';
  final name = r['name'] as String? ?? '';
  if (segment['startsRivalry'] == true) return 'Começa rivalidade: $name';
  if (segment['endsRivalry'] == true) return 'Encerra rivalidade: $name';
  return 'Rivalidade: $name';
}
