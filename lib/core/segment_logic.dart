import 'format.dart';
import 'models.dart';
import 'segment_result.dart';

class SegParticipant {
  SegParticipant(this.wrestlerId, this.side, {this.isWinner = false});
  final String wrestlerId;
  int side;
  bool isWinner;
}

/// Estado editável de um segmento (porte do SegmentDialog do web).
class SegmentDraft {
  SegmentDraft({
    this.type = 'MATCH',
    this.matchTypeId,
    this.titleId,
    this.titleChanged = false,
    this.isMainEvent = false,
    this.finishType,
    this.isDone = false,
    this.isDraw = false,
    this.notes = '',
    this.stakes = 'NONE',
    this.cardDivisionId,
    this.tournamentMatchId,
    List<SegParticipant>? participants,
    int? sideCount,
  })  : participants = participants ?? [],
        sideCount = sideCount ?? 2;

  factory SegmentDraft.fromEntity(Entity s, {bool markDone = false}) {
    final parts = s.list('participants');
    return SegmentDraft(
      type: s['type'] as String? ?? 'MATCH',
      matchTypeId: s['matchTypeId'] as String?,
      titleId: s['titleId'] as String?,
      titleChanged: s['titleChanged'] == true,
      isMainEvent: s['isMainEvent'] == true,
      finishType: s['finishType'] as String?,
      isDone: markDone || s['isDone'] == true,
      isDraw: s['isDraw'] == true,
      notes: s['notes'] as String? ?? '',
      stakes: s['stakes'] as String? ?? 'NONE',
      cardDivisionId: s['cardDivisionId'] as String?,
      tournamentMatchId: s.obj('tournamentMatch')?['id'] as String?,
      participants: [
        for (final p in parts)
          SegParticipant(p['wrestlerId'] as String, (p['side'] as num).toInt(), isWinner: p['isWinner'] == true),
      ],
      sideCount: parts.isEmpty
          ? 2
          : parts.map((p) => (p['side'] as num).toInt()).reduce((a, b) => a > b ? a : b).clamp(2, 99),
    );
  }

  String type;
  String? matchTypeId;
  String? titleId;
  bool titleChanged;
  bool isMainEvent;
  String? finishType;
  bool isDone;
  bool isDraw;
  String notes;
  String stakes;
  String? cardDivisionId;
  String? tournamentMatchId;
  final List<SegParticipant> participants;
  int sideCount;

  bool get isMatch => type == 'MATCH';
  bool get hasTitle => titleId != null;
  bool get hasStakes => isMatch && stakes != 'NONE';
  bool get needsResult => isMatch && isDone;

  List<int> get sides => [for (var i = 1; i <= sideCount; i++) i];
  List<SegParticipant> onSide(int side) => participants.where((p) => p.side == side).toList();
  bool sideWins(int side) => onSide(side).isNotEmpty && onSide(side).every((p) => p.isWinner);

  /// O que falta para poder marcar como realizada (null = ok).
  String? get problem => resultProblem(
        type: type,
        isDone: isDone,
        isDraw: isDraw,
        finishType: finishType,
        participants: [for (final p in participants) ParticipantResult(side: p.side, isWinner: p.isWinner)],
      );

  /// Falta escolher a divisão afetada pelo ranking.
  bool get missingDivision => hasStakes && cardDivisionId == null;

  bool get canSave => problem == null && !missingDivision;

  /// Empate não tem vencedor: limpa as estrelas ao marcar.
  void setDraw(bool draw) {
    isDraw = draw;
    if (draw) {
      for (final p in participants) {
        p.isWinner = false;
      }
    }
  }

  void toggleWinner(String wrestlerId) {
    isDraw = false;
    for (final p in participants) {
      if (p.wrestlerId == wrestlerId) p.isWinner = !p.isWinner;
    }
  }

  /// Marca o lado inteiro como vencedor (times); de novo desfaz.
  void toggleSideWinner(int side) {
    final everyoneWins = sideWins(side);
    isDraw = false;
    for (final p in participants) {
      p.isWinner = p.side == side ? !everyoneWins : false;
    }
  }

  void addParticipant(int side, String wrestlerId) {
    if (participants.any((p) => p.wrestlerId == wrestlerId)) return;
    participants.add(SegParticipant(wrestlerId, side));
  }

  void removeParticipant(String wrestlerId) => participants.removeWhere((p) => p.wrestlerId == wrestlerId);

  void addSide() => sideCount++;

  void removeSide() {
    if (sideCount <= 1) return;
    participants.removeWhere((p) => p.side == sideCount);
    sideCount--;
  }

  /// Corpo do POST/PUT de `segments` (mesmas regras do `save()` do web).
  Map<String, Object?> toBody(String episodeId) => {
        'episodeId': episodeId,
        'type': type,
        'matchTypeId': isMatch ? matchTypeId : null,
        'titleId': isMatch ? titleId : null,
        'titleChanged': isMatch && hasTitle ? titleChanged : false,
        'isMainEvent': isMainEvent,
        'finishType': isMatch ? finishType : null,
        'stakes': isMatch && cardDivisionId != null ? stakes : 'NONE',
        'cardDivisionId': isMatch && stakes != 'NONE' ? cardDivisionId : null,
        'tournamentMatchId': isMatch ? tournamentMatchId : null,
        'isDone': isDone,
        'isDraw': isMatch && isDraw,
        'notes': notes.trim().isEmpty ? null : notes.trim(),
        'participants': [
          for (final p in participants) {'wrestlerId': p.wrestlerId, 'side': p.side, 'isWinner': p.isWinner},
        ],
      };

  /// Escolheu a luta do torneio: preenche os lados com os inscritos (se ainda não há
  /// participantes) e sugere o tipo de luta. [matchTypes] são os `match-types` do universe.
  void pickTournamentMatch(Entity? m, List<Entity> matchTypes) {
    tournamentMatchId = m?.id ?? tournamentMatchId;
    if (m == null || participants.isNotEmpty) return;
    List<String> wrestlers(Entity? e) {
      if (e == null) return const [];
      final w = e['wrestlerId'] as String?;
      if (w != null) return [w];
      return (e.obj('team')?['members'] as List? ?? const []).map((x) => (x as Map)['wrestlerId'] as String).toList();
    }

    final sides = <Entity?>[
      m.obj('entrantA'),
      m.obj('entrantB'),
      for (final x in m.list('extras')) x.obj('entrant'),
    ];
    final used = <String>{};
    for (var i = 0; i < sides.length; i++) {
      for (final w in wrestlers(sides[i])) {
        if (used.add(w)) participants.add(SegParticipant(w, i + 1));
      }
    }
    sideCount = sides.length < 2 ? 2 : sides.length;
    if (matchTypeId == null) {
      final n = sides.where((e) => e != null).length;
      final multi = sides.any((e) => wrestlers(e).length > 1);
      Entity? type;
      final preset = m['matchTypeId'] as String?;
      if (preset != null) {
        type = matchTypes.where((t) => t.id == preset).firstOrNull;
      } else {
        final name = n == 3 ? 'Triple Threat' : n == 4 ? 'Fatal 4-Way' : n > 4 ? 'Battle Royal' : multi ? 'Tag Team' : 'Singles';
        type = matchTypes.where((t) => t['name'] == name).firstOrNull;
      }
      if (type != null) matchTypeId = type.id;
    }
  }
}

/// Rótulo de uma luta de torneio na lista de escolha.
String tournamentMatchLabel(Entity m) {
  String entrant(Entity? e) => e == null ? 'a definir' : (e.obj('wrestler')?['name'] ?? e.obj('team')?['name'] ?? '?') as String;
  final t = m.obj('tournament') ?? const {};
  final round = roundTitle(
    RoundInfo(format: t['format'] as String?, size: (t['size'] as num?)?.toInt() ?? 2, firstRoundMatches: (t['firstRoundMatches'] as num?)?.toInt()),
    round: (m['round'] as num).toInt(),
    groupName: m['groupName'] as String?,
  );
  final slot = t['format'] == 'ROUND_ROBIN' ? '' : ' · Luta ${m['slot']}';
  return '${t['name']} — $round$slot: ${entrant(m.obj('entrantA'))} x ${entrant(m.obj('entrantB'))}';
}
