/// Uma luta só pode ser marcada como realizada com resultado: vencedor (ou lado
/// vencedor) e como terminou, ou empate. Mesma regra do backend (segmentResult.js).
class ParticipantResult {
  const ParticipantResult({required this.side, required this.isWinner});
  final int side;
  final bool isWinner;
}

String? resultProblem({
  required String? type,
  required bool isDone,
  required bool isDraw,
  required String? finishType,
  required List<ParticipantResult> participants,
}) {
  if (!isDone || type != 'MATCH') return null;
  if (participants.isEmpty) {
    return 'Informe os participantes para marcar como realizada.';
  }
  final winners = participants.where((p) => p.isWinner).toList();
  if (isDraw) {
    return winners.isNotEmpty ? 'Uma luta empatada não pode ter vencedor.' : null;
  }
  if (winners.isEmpty) {
    return 'Marque o vencedor (ou o lado vencedor), ou marque empate.';
  }
  if (winners.map((p) => p.side).toSet().length > 1) {
    return 'Os vencedores precisam ser do mesmo lado.';
  }
  if (finishType == null || finishType.isEmpty) {
    return 'Informe como a luta terminou.';
  }
  return null;
}
