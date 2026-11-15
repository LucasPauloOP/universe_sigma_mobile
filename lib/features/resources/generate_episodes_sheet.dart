import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/api_exception.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../resources/resources.dart';
import '../../shared/ui.dart';
import 'field_widgets.dart';

/// Gera os episódios que faltam (`POST episodes/generate`). Devolve quantos foram criados.
class GenerateEpisodesSheet extends ConsumerStatefulWidget {
  const GenerateEpisodesSheet({super.key});

  static Future<int?> show(BuildContext context) => showModalBottomSheet<int>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const GenerateEpisodesSheet(),
      );

  @override
  ConsumerState<GenerateEpisodesSheet> createState() => _State();
}

class _State extends ConsumerState<GenerateEpisodesSheet> {
  String? _seasonId;
  List<Object> _showIds = [];
  List<Object> _months = [];
  int _weeks = 4;

  Future<void> _run() async {
    if (_seasonId == null) return showInfo(context, 'Escolha a temporada.');
    try {
      final res = await ref.read(apiProvider).post('episodes/generate', body: {
        'seasonId': _seasonId,
        'weeks': _weeks,
        if (_showIds.isNotEmpty) 'showIds': _showIds,
        if (_months.isNotEmpty) 'months': _months,
      });
      invalidateItems(ref, ['episodes']);
      if (mounted) Navigator.pop(context, (res['created'] as num).toInt());
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final seasons = ref.watch(itemsProvider('seasons')).value ?? const <Entity>[];
    final shows = ref.watch(itemsProvider('shows')).value ?? const <Entity>[];
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Gerar episódios', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Cria os episódios que faltam (sem duplicar os existentes): shows semanais por semana e PLEs no mês configurado.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          PickerField(
            label: 'Temporada',
            required: true,
            value: _seasonId,
            choices: [for (final s in seasons) Choice(s.id, resources['seasons']!.label(s))],
            onChanged: (v) => setState(() => _seasonId = v as String?),
          ),
          const SizedBox(height: 14),
          MultiPickerField(
            label: 'Shows (vazio = todos)',
            values: _showIds,
            choices: [for (final s in shows) Choice(s.id, s['name'] as String)],
            onChanged: (v) => setState(() => _showIds = v),
          ),
          const SizedBox(height: 14),
          MultiPickerField(
            label: 'Meses (vazio = do mês de início até abril)',
            values: _months,
            choices: [for (final o in monthOptions) Choice(o.value, o.label)],
            onChanged: (v) => setState(() => _months = v),
          ),
          const SizedBox(height: 14),
          Row(children: [
            const Expanded(child: Text('Semanas por mês (shows semanais)')),
            IconButton(onPressed: _weeks > 1 ? () => setState(() => _weeks--) : null, icon: const Icon(Icons.remove)),
            Text('$_weeks'),
            IconButton(onPressed: _weeks < 4 ? () => setState(() => _weeks++) : null, icon: const Icon(Icons.add)),
          ]),
          const SizedBox(height: 8),
          BusyButton(label: 'Gerar', icon: Icons.bolt, onPressed: _run),
        ]),
      ),
    );
  }
}
