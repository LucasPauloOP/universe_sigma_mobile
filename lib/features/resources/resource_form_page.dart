import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/api_exception.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../resources/resource_def.dart';
import '../../resources/resources.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui.dart';
import 'activation.dart';
import 'field_widgets.dart';

/// Formulário genérico dirigido por [Resource] (criar e editar). Equivale ao ResourceForm do web.
class ResourceFormPage extends ConsumerStatefulWidget {
  const ResourceFormPage({super.key, required this.resourceKey, this.id});
  final String resourceKey;
  final String? id;

  @override
  ConsumerState<ResourceFormPage> createState() => _ResourceFormPageState();
}

class _ResourceFormPageState extends ConsumerState<ResourceFormPage> {
  late final Resource res = resources[widget.resourceKey]!;
  Entity? _entity;
  bool _loading = true;
  bool _busy = false;
  final _values = <String, Object?>{};
  final _controllers = <String, TextEditingController>{};
  final _errors = <String, String>{};
  final _lastAutofill = <String, Map<String, Object?>>{};

  bool get _editing => widget.id != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      if (_editing) {
        final list = await ref.read(itemsProvider(res.key).future);
        _entity = list.where((e) => e.id == widget.id).firstOrNull ??
            Map<String, dynamic>.from(await ref.read(apiProvider).get('${res.key}/${widget.id}') as Map);
      }
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    }
    for (final f in res.fields) {
      Object? v = _entity != null
          ? (f.fromEntity != null ? f.fromEntity!(_entity!) : _entity![f.key])
          : (f.defaultValue ?? (f.type == FieldType.refMulti ? <Object>[] : null));
      if (f.type == FieldType.refMulti) v = List<Object>.from((v as List?) ?? const []);
      if ((f.type == FieldType.text || f.type == FieldType.textarea)) v ??= '';
      _values[f.key] = v;
      if (f.type == FieldType.text || f.type == FieldType.textarea || f.type == FieldType.number) {
        _controllers[f.key] = TextEditingController(text: v == null ? '' : '$v');
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  bool _isEmpty(Object? v) => v == null || v == '' || (v is List && v.isEmpty);

  void _set(FieldDef f, Object? v) {
    setState(() {
      _values[f.key] = v;
      _errors.remove(f.key);
    });
    if (f.autofill != null && !_editing) _applyAutofill(f, v as String?, force: false);
  }

  Entity? _find(String key, String id) =>
      ref.read(itemsProvider(key)).value?.where((e) => e.id == id).firstOrNull;

  /// Criação: só preenche campos vazios ou ainda com a sugestão anterior.
  /// Edição (botão "importar"): sobrescreve.
  void _applyAutofill(FieldDef f, String? id, {required bool force}) {
    final last = _lastAutofill[f.key] ?? const {};
    final next = f.autofill!(id, _find);
    setState(() {
      next.forEach((key, value) {
        if (!_values.containsKey(key)) return;
        if (force || _isEmpty(_values[key]) || _values[key] == last[key]) {
          _values[key] = value;
          final c = _controllers[key];
          if (c != null) c.text = value == null ? '' : '$value';
        }
      });
      _lastAutofill[f.key] = next;
    });
  }

  bool _visible(FieldDef f) => f.showIf == null || f.showIf!(_values);

  bool _validate() {
    _errors.clear();
    for (final f in res.fields.where(_visible)) {
      final v = _values[f.key];
      if (f.required && _isEmpty(v)) {
        _errors[f.key] = 'Obrigatório';
        continue;
      }
      if (f.type == FieldType.number && !_isEmpty(v)) {
        final n = num.tryParse('$v'.replaceAll(',', '.'));
        if (n == null) {
          _errors[f.key] = 'Número inválido';
        } else if (f.min != null && n < f.min!) {
          _errors[f.key] = 'Mínimo ${f.min}';
        } else if (f.max != null && n > f.max!) {
          _errors[f.key] = 'Máximo ${f.max}';
        }
      }
    }
    setState(() {});
    return _errors.isEmpty;
  }

  Future<void> _save() async {
    if (!_validate()) {
      showInfo(context, 'Corrija os campos destacados.');
      return;
    }
    setState(() => _busy = true);
    try {
      final api = ref.read(apiProvider);
      final values = {
        for (final e in _values.entries)
          e.key: e.value is String && _controllers[e.key] != null && res.fields.firstWhere((f) => f.key == e.key).type == FieldType.number
              ? (e.value as String).replaceAll(',', '.')
              : e.value,
      };
      final body = buildBody(res, values, original: _entity);
      // show/brand sendo desativado: avisa o que será apagado antes de salvar
      if (_entity != null && activatable.contains(res.key) && _entity!['isActive'] != false && body['isActive'] == false) {
        final extra = await confirmDeactivation(context, api, res.key, _entity!);
        if (extra == null) return;
        body.addAll(extra);
      }
      if (_entity != null) {
        await api.put('${res.key}/${_entity!.id}', body: body);
      } else {
        await api.post(res.key, body: body);
      }
      invalidateItems(ref, [res.key, if (res.key == 'brands') 'shows']);
      if (mounted) context.pop(true);
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Choice> _choicesFor(FieldDef f) {
    if (f.type == FieldType.select) {
      return [for (final o in f.options ?? const <Option>[]) Choice(o.value, o.label)];
    }
    final target = resources[f.ref];
    final items = ref.watch(itemsProvider(f.ref!)).value ?? const <Entity>[];
    final out = [
      for (final e in items)
        if (f.refWhere == null || f.refWhere!(e)) Choice(e.id, target?.label(e) ?? (e['name'] as String? ?? '')),
    ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return out;
  }

  Widget _field(FieldDef f) {
    final err = _errors[f.key];
    switch (f.type) {
      case FieldType.text:
      case FieldType.textarea:
      case FieldType.number:
        return TextField(
          controller: _controllers[f.key],
          maxLines: f.type == FieldType.textarea ? 4 : 1,
          keyboardType: f.type == FieldType.number
              ? const TextInputType.numberWithOptions(decimal: false)
              : (f.type == FieldType.textarea ? TextInputType.multiline : TextInputType.text),
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: f.required ? '${f.label} *' : f.label, errorText: err, helperText: f.hint, helperMaxLines: 3),
          onChanged: (t) {
            _values[f.key] = t;
            if (err != null) setState(() => _errors.remove(f.key));
          },
        );
      case FieldType.boolean:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(f.label),
          subtitle: f.hint != null ? Text(f.hint!) : null,
          value: _values[f.key] == true,
          onChanged: (v) => _set(f, v),
        );
      case FieldType.select:
      case FieldType.ref:
        return PickerField(
          label: f.label,
          choices: _choicesFor(f),
          value: _values[f.key],
          required: f.required,
          error: err,
          hint: f.hint,
          onChanged: (v) => _set(f, v),
        );
      case FieldType.refMulti:
        return MultiPickerField(
          label: f.label,
          choices: _choicesFor(f),
          values: (_values[f.key] as List).cast<Object>(),
          error: err,
          hint: f.hint,
          onChanged: (v) => _set(f, v),
        );
      case FieldType.date:
        return DateField(
          label: f.label,
          value: _values[f.key] as DateTime?,
          required: f.required,
          error: err,
          hint: f.hint,
          onChanged: (v) => _set(f, v),
        );
      case FieldType.image:
        return ImageFieldWidget(label: f.label, value: _values[f.key] as String?, onChanged: (v) => _set(f, v));
      case FieldType.color:
        return ColorFieldWidget(label: f.label, value: _values[f.key] as String?, onChanged: (v) => _set(f, v), error: err);
    }
  }

  /// Edição: oferece importar os dados quando o ref foi trocado.
  bool _canImport(FieldDef f) {
    if (!_editing || f.autofill == null || _entity == null) return false;
    final v = _values[f.key];
    return v != null && v != _entity![f.key];
  }

  @override
  Widget build(BuildContext context) {
    final title = '${_editing ? 'Editar' : 'Novo(a)'} ${res.singular.toLowerCase()}';
    return AppPage(
      title: title,
      showBack: true,
      actions: [
        TextButton(onPressed: _busy || _loading ? null : _save, child: const Text('Salvar')),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final f in res.fields.where(_visible)) ...[
                  _field(f),
                  if (_canImport(f))
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _applyAutofill(f, _values[f.key] as String?, force: true),
                        icon: const Icon(Icons.download),
                        label: Text(f.autofillLabel ?? 'Importar dados'),
                      ),
                    ),
                  const SizedBox(height: 14),
                ],
                const SizedBox(height: 8),
                BusyButton(label: 'Salvar', icon: Icons.save, onPressed: _busy ? null : _save),
                const SizedBox(height: 48),
              ],
            ),
    );
  }
}
