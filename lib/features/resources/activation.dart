import 'package:material_ui/material_ui.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/models.dart';
import '../../shared/ui.dart';

/// Recursos que podem ser desativados e o que acontece quando são.
const activatable = ['shows', 'brands'];

/// Desativar um show apaga os episódios dele; desativar uma brand desativa os shows
/// dela (e apaga os episódios). Pergunta antes. `null` = cancelou; senão o corpo extra
/// (`{confirm: true}` quando houve aviso). Porte de core/activation.ts do web.
Future<Map<String, Object?>?> confirmDeactivation(
  BuildContext context,
  ApiClient api,
  String key,
  Entity entity,
) async {
  final impact = await api.get('$key/${entity.id}/impact') as Map;
  final episodes = (impact['episodes'] as num?)?.toInt() ?? 0;
  final segments = (impact['segments'] as num?)?.toInt() ?? 0;
  final shows = (impact['shows'] as List? ?? const []).cast<String>();
  if (episodes == 0 && !(key == 'brands' && shows.isNotEmpty)) return {};

  final cards = '$episodes episódio(s)${segments > 0 ? ' e $segments segmento(s) já montados nos cards' : ''}';
  final name = entity['name'];
  final message = key == 'shows'
      ? 'Desativar "$name" vai APAGAR $cards. Isso não pode ser desfeito.'
      : 'Desativar a brand "$name" vai desativar ${shows.isNotEmpty ? 'os shows ${shows.join(', ')}' : 'seus shows'} e APAGAR $cards. Isso não pode ser desfeito.';
  if (!context.mounted) return null;
  final ok = await confirm(
    context,
    title: key == 'shows' ? 'Desativar show' : 'Desativar brand',
    message: message,
    confirmLabel: 'Desativar e apagar',
    danger: true,
  );
  return ok ? {'confirm': true} : null;
}

/// Liga/desliga direto da lista. Devolve true se algo mudou.
Future<bool> setActive(
  BuildContext context,
  ApiClient api,
  String key,
  Entity entity,
  bool active,
) async {
  try {
    Map<String, Object?>? extra = {};
    if (!active) extra = await confirmDeactivation(context, api, key, entity);
    if (extra == null) return false;
    await api.put('$key/${entity.id}', body: {'isActive': active, ...extra});
    return true;
  } on ApiException catch (e) {
    if (context.mounted) showError(context, e);
    return false;
  }
}
