/// Calendário do jogo e formatações. Porte de universe_sigma_frontend/core/format.ts
/// (mesmas regras do backend: services/timeline.js e bracket.js).
library;

import 'dart:math' as math;

import 'models.dart';

/// Datas da API são instantes UTC à meia-noite: exiba sempre só a parte da data.
String fmtDate(String? iso) {
  if (iso == null || iso.length < 10) return '';
  final p = iso.substring(0, 10).split('-');
  return '${p[2]}/${p[1]}/${p[0]}';
}

DateTime? isoToLocalDate(String? iso) {
  if (iso == null || iso.length < 10) return null;
  final p = iso.substring(0, 10).split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

String? localDateToIso(DateTime? d) {
  if (d == null) return null;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

const months = [
  'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
  'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
];

const weekdays = [
  'Domingo', 'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado',
];

String monthName(int? m) => (m == null || m < 1 || m > 12) ? '' : months[m - 1];

/// A temporada da WWE começa depois da WrestleMania (maio) e termina nela (abril).
const seasonMonths = [5, 6, 7, 8, 9, 10, 11, 12, 1, 2, 3, 4];

/// 0 = maio ... 11 = abril
int seasonMonthIndex(int month) => (month - 5 + 12) % 12;

/// Calendário do jogo: todo mês tem 4 semanas (segunda a domingo).
int gameWeek(int? week) => (week ?? 4).clamp(1, 4);

const gameWeekdays = [
  'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado', 'Domingo',
];

/// Campos de um episódio usados nas regras de calendário.
class EpisodeLike {
  const EpisodeLike({
    required this.month,
    this.week,
    this.night,
    this.kind,
    this.weekday,
    this.showName,
  });

  factory EpisodeLike.fromEntity(Entity e) {
    final show = e.obj('show');
    return EpisodeLike(
      month: (e['month'] as num).toInt(),
      week: (e['week'] as num?)?.toInt(),
      night: (e['night'] as num?)?.toInt(),
      kind: show?['kind'] as String?,
      weekday: (show?['weekday'] as num?)?.toInt(),
      showName: show?['name'] as String?,
    );
  }

  final int month;
  final int? week;
  final int? night;
  final String? kind;
  final int? weekday;
  final String? showName;
}

/// Coluna do episódio na semana (0 = segunda ... 6 = domingo): o dia do show; sem ele,
/// semanal = segunda e PLE = sábado. A Noite 2 de um PLE vai um dia depois.
int gameDayOffset(EpisodeLike e) {
  final weekday = e.weekday ?? (e.kind == 'WEEKLY' ? 1 : 6);
  final night = (e.night != null && e.night! > 1) ? e.night! - 1 : 0;
  return math.min((weekday + 6) % 7 + night, 6);
}

String gameDayName(EpisodeLike e) => gameWeekdays[gameDayOffset(e)];

/// Ordem de jogo: mês (maio→abril), semana, dia; shows semanais antes de PLE/especial.
int episodeOrderKey(EpisodeLike e) {
  final weekly = e.kind == 'WEEKLY';
  return seasonMonthIndex(e.month) * 100000 +
      gameWeek(e.week) * 1000 +
      gameDayOffset(e) * 10 +
      (weekly ? 0 : 5) +
      (e.night ?? 0);
}

int compareEpisodes(EpisodeLike a, EpisodeLike b) {
  final d = episodeOrderKey(a) - episodeOrderKey(b);
  return d != 0 ? d : (a.showName ?? '').compareTo(b.showName ?? '');
}

int compareEpisodeEntities(Entity a, Entity b) =>
    compareEpisodes(EpisodeLike.fromEntity(a), EpisodeLike.fromEntity(b));

/// Episódio de um mês anterior ao início do universe na temporada (vazio = maio).
bool beforeStart(int month, int? startMonth) =>
    seasonMonthIndex(month) < seasonMonthIndex(startMonth ?? 5);

/// Rótulo de um episódio: "RAW · Agosto · semana 1 · Noite 2".
String episodeText(Entity e) {
  final parts = <String>[
    e.obj('show')?['name'] as String? ?? 'Episódio',
    monthName((e['month'] as num?)?.toInt()),
    if (e['week'] != null) 'semana ${e['week']}',
    if (e['night'] != null) 'Noite ${e['night']}',
  ];
  return parts.where((s) => s.isNotEmpty).join(' · ');
}

// ───────────── Torneios (mesmas regras do backend: services/bracket.js) ─────────────

class RoundInfo {
  const RoundInfo({this.format, required this.size, this.firstRoundMatches});

  factory RoundInfo.fromTournament(Entity t) => RoundInfo(
        format: t['format'] as String?,
        size: (t['size'] as num?)?.toInt() ?? 2,
        firstRoundMatches: (t['firstRoundMatches'] as num?)?.toInt(),
      );

  final String? format;
  final int size;
  final int? firstRoundMatches;
}

bool _isPow2(int n) => n >= 1 && (n & (n - 1)) == 0;
int _log2(int n) => (math.log(n) / math.ln2).round();

/// Nº de rodadas da eliminatória.
int totalRounds(RoundInfo t) {
  if (t.firstRoundMatches != null && t.firstRoundMatches! > 0) {
    return _log2(t.firstRoundMatches!) + 1;
  }
  if (t.size > 1 && _isPow2(t.size)) return _log2(t.size);
  for (var per = 3; per <= 8; per++) {
    final m = t.size / per;
    if (m == m.floor() && _isPow2(m.floor())) return _log2(m.floor()) + 1;
  }
  return math.max(1, _log2(t.size));
}

/// "Final", "Semifinal", "Quartas de final"... para a rodada [round] de [total].
String roundName(int round, int total) {
  final left = total - round;
  return switch (left) {
    0 => 'Final',
    1 => 'Semifinal',
    2 => 'Quartas de final',
    _ => 'Rodada $round',
  };
}

/// Título da rodada (eliminatória) ou o nome do grupo.
String roundTitle(RoundInfo t, {required int round, String? groupName}) {
  if (t.format == 'ROUND_ROBIN') return groupName ?? 'Fase de grupos';
  return roundName(round, totalRounds(t));
}

/// Resultado de um episódio "realizado" reaberto: volta a planejado se tem card.
String reopenedStatus(int segments) => segments > 0 ? 'PLANNED' : 'UNPLANNED';
