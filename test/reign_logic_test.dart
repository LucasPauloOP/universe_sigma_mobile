import 'package:flutter_test/flutter_test.dart';
import 'package:universe_sigma_mobile/core/models.dart';
import 'package:universe_sigma_mobile/core/reign_logic.dart';

Entity holder(String key, String name, int reigns, int days, {bool current = false}) =>
    {'key': key, 'name': name, 'reigns': reigns, 'days': days, 'isCurrent': current};

void main() {
  final titles = <Entity>[
    {'title': {'name': 'World'}, 'holders': [holder('cena', 'Cena', 17, 1200, current: true), holder('punk', 'Punk', 3, 600)]},
    {'title': {'name': 'US'}, 'holders': [holder('cena', 'Cena', 5, 300), holder('orton', 'Orton', 2, 400, current: true)]},
  ];

  test('ranking geral soma os títulos e ordena por dias, depois reinados', () {
    final o = overallOf(titles);
    expect(o.map((x) => x.name), ['Cena', 'Punk', 'Orton']);
    expect(o.first.reigns, 22);
    expect(o.first.days, 1500);
    expect(o.first.titles.map((t) => t.title), ['World', 'US']);
    expect(o.first.titles.first.current, isTrue);
  });

  test('destaques: mais reinados, mais dias e campeão há mais tempo', () {
    final h = highlightsOf(titles);
    expect(h[0].value, 'Cena');
    expect(h[0].detail, '22x campeão');
    expect(h[1].detail, '1.500 dias');
    expect(h[2].value, 'Cena'); // 1200 dias, atual
    expect(h[2].detail, 'World · 1.200 dias');
    expect(highlightsOf(const []), isEmpty);
  });

  test('sem campeão atual não mostra o destaque de "há mais tempo"', () {
    final none = <Entity>[
      {'title': {'name': 'T'}, 'holders': [holder('a', 'A', 1, 10)]},
    ];
    expect(highlightsOf(none).length, 2);
  });

  test('formatação de milhar pt-BR', () {
    expect(fmtInt(0), '0');
    expect(fmtInt(999), '999');
    expect(fmtInt(1000), '1.000');
    expect(fmtInt(1234567), '1.234.567');
  });
}
