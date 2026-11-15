import 'models.dart';

/// Total por lutador/dupla somando todos os títulos (aba "Por lutador").
class OverallStat {
  OverallStat(this.key, this.name);
  final String key;
  final String name;
  int reigns = 0;
  int days = 0;
  final List<({String title, int reigns, int days, bool current})> titles = [];
}

int _i(Object? v) => (v as num?)?.toInt() ?? 0;

/// Ranking geral: mais dias primeiro, depois mais reinados. `titles` é o `titles` de `GET stats/titles`.
List<OverallStat> overallOf(List<Entity> titles) {
  final map = <String, OverallStat>{};
  for (final t in titles) {
    for (final h in t.list('holders')) {
      final o = map.putIfAbsent(h['key'] as String, () => OverallStat(h['key'] as String, h['name'] as String));
      o.reigns += _i(h['reigns']);
      o.days += _i(h['days']);
      o.titles.add((
        title: t.obj('title')?['name'] as String? ?? '',
        reigns: _i(h['reigns']),
        days: _i(h['days']),
        current: h['isCurrent'] == true,
      ));
    }
  }
  return map.values.toList()
    ..sort((a, b) => b.days != a.days ? b.days - a.days : b.reigns - a.reigns);
}

class Highlight {
  const Highlight(this.label, this.value, this.detail);
  final String label;
  final String value;
  final String detail;
}

String _n(int n) {
  final s = n.toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write('.');
    out.write(s[i]);
  }
  return out.toString();
}

/// Número no padrão pt-BR (milhar com ponto).
String fmtInt(int n) => _n(n);

/// Destaques gerais: mais reinados, mais dias e quem é campeão há mais tempo.
List<Highlight> highlightsOf(List<Entity> titles) {
  final all = overallOf(titles);
  if (all.isEmpty) return const [];
  final mostReigns = ([...all]..sort((a, b) => b.reigns - a.reigns)).first;
  final mostDays = all.first;
  final reigning = [
    for (final t in titles)
      for (final h in t.list('holders').where((h) => h['isCurrent'] == true))
        (h: h, title: t.obj('title')?['name'] as String? ?? ''),
  ]..sort((a, b) => _i(b.h['days']) - _i(a.h['days']));
  return [
    Highlight('Mais reinados', mostReigns.name, '${mostReigns.reigns}x campeão'),
    Highlight('Mais dias com cinturões', mostDays.name, '${fmtInt(mostDays.days)} dias'),
    if (reigning.isNotEmpty)
      Highlight('Campeão há mais tempo', reigning.first.h['name'] as String,
          '${reigning.first.title} · ${fmtInt(_i(reigning.first.h['days']))} dias'),
  ];
}
