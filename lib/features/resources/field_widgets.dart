import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../shared/net_image.dart';
import '../../shared/ui.dart';

String _norm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[áàâãä]'), 'a')
    .replaceAll(RegExp('[éèêë]'), 'e')
    .replaceAll(RegExp('[íìîï]'), 'i')
    .replaceAll(RegExp('[óòôõö]'), 'o')
    .replaceAll(RegExp('[úùûü]'), 'u')
    .replaceAll('ç', 'c');

/// Opção de um seletor (valor + texto).
class Choice {
  const Choice(this.value, this.label);
  final Object value;
  final String label;
}

class _Frame extends StatelessWidget {
  const _Frame({required this.label, required this.child, this.error, this.hint, this.required = false, this.onTap, this.trailing});
  final String label;
  final Widget child;
  final String? error;
  final String? hint;
  final bool required;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: required ? '$label *' : label,
            errorText: error,
            helperText: hint,
            helperMaxLines: 3,
            suffixIcon: trailing,
          ),
          child: child,
        ),
      );
}

// ───────────────────────────────── seletor único ─────────────────────────────────

Future<({bool picked, Object? value})?> _pickOne(
  BuildContext context, {
  required String title,
  required List<Choice> choices,
  Object? current,
  required bool allowClear,
}) {
  return showModalBottomSheet<({bool picked, Object? value})>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _PickSheet(title: title, choices: choices, selected: {?current}, multi: false, allowClear: allowClear),
  );
}

class PickerField extends StatelessWidget {
  const PickerField({super.key, required this.label, required this.choices, required this.value, required this.onChanged, this.required = false, this.error, this.hint});

  final String label;
  final List<Choice> choices;
  final Object? value;
  final ValueChanged<Object?> onChanged;
  final bool required;
  final String? error;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final current = choices.where((c) => c.value == value).firstOrNull;
    return _Frame(
      label: label,
      required: required,
      error: error,
      hint: hint,
      trailing: const Icon(Icons.arrow_drop_down),
      onTap: () async {
        final r = await _pickOne(context, title: label, choices: choices, current: value, allowClear: !required);
        if (r != null && r.picked) onChanged(r.value);
      },
      child: Text(
        current?.label ?? (value != null ? '$value' : 'Selecione'),
        style: current == null ? TextStyle(color: Theme.of(context).hintColor) : null,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ───────────────────────────────── multi-seleção ─────────────────────────────────

class MultiPickerField extends StatelessWidget {
  const MultiPickerField({super.key, required this.label, required this.choices, required this.values, required this.onChanged, this.error, this.hint});

  final String label;
  final List<Choice> choices;
  final List<Object> values;
  final ValueChanged<List<Object>> onChanged;
  final String? error;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final byValue = {for (final c in choices) c.value: c.label};
    return _Frame(
      label: label,
      error: error,
      hint: hint,
      trailing: const Icon(Icons.arrow_drop_down),
      onTap: () async {
        final r = await showModalBottomSheet<Set<Object>>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (ctx) => _PickSheet(title: label, choices: choices, selected: values.toSet(), multi: true, allowClear: false),
        );
        if (r != null) onChanged(values.where(r.contains).followedBy(r.where((v) => !values.contains(v))).toList());
      },
      child: values.isEmpty
          ? Text('Selecione', style: TextStyle(color: Theme.of(context).hintColor))
          : Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final v in values)
                  Chip(
                    label: Text(byValue[v] ?? '$v'),
                    visualDensity: VisualDensity.compact,
                    onDeleted: () => onChanged(values.where((x) => x != v).toList()),
                  ),
              ],
            ),
    );
  }
}

class _PickSheet extends StatefulWidget {
  const _PickSheet({required this.title, required this.choices, required this.selected, required this.multi, required this.allowClear});
  final String title;
  final List<Choice> choices;
  final Set<Object> selected;
  final bool multi;
  final bool allowClear;

  @override
  State<_PickSheet> createState() => _PickSheetState();
}

class _PickSheetState extends State<_PickSheet> {
  late final Set<Object> _sel = {...widget.selected};
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _norm(_q.trim());
    final list = widget.choices.where((c) => q.isEmpty || _norm(c.label).contains(q)).toList();
    final height = MediaQuery.of(context).size.height * 0.75;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: height,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(child: Text(widget.title, style: Theme.of(context).textTheme.titleMedium)),
              if (widget.allowClear)
                TextButton(onPressed: () => Navigator.pop(context, (picked: true, value: null)), child: const Text('Limpar')),
              if (widget.multi)
                FilledButton(onPressed: () => Navigator.pop(context, _sel), child: Text('OK (${_sel.length})')),
            ]),
          ),
          if (widget.choices.length > 8)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                autofocus: false,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar', isDense: true),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
          Expanded(
            child: list.isEmpty
                ? const EmptyState('Nada encontrado.')
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (ctx, i) {
                      final c = list[i];
                      final on = _sel.contains(c.value);
                      return widget.multi
                          ? CheckboxListTile(
                              value: on,
                              title: Text(c.label),
                              dense: true,
                              onChanged: (v) => setState(() => v == true ? _sel.add(c.value) : _sel.remove(c.value)),
                            )
                          : ListTile(
                              title: Text(c.label),
                              dense: true,
                              selected: on,
                              trailing: on ? const Icon(Icons.check) : null,
                              onTap: () => Navigator.pop(context, (picked: true, value: c.value)),
                            );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

// ───────────────────────────────────── data ─────────────────────────────────────

class DateField extends StatelessWidget {
  const DateField({super.key, required this.label, required this.value, required this.onChanged, this.required = false, this.error, this.hint});
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool required;
  final String? error;
  final String? hint;

  @override
  Widget build(BuildContext context) => _Frame(
        label: label,
        required: required,
        error: error,
        hint: hint,
        trailing: value != null && !required
            ? IconButton(icon: const Icon(Icons.clear), onPressed: () => onChanged(null))
            : const Icon(Icons.calendar_today),
        onTap: () async {
          final now = DateTime.now();
          final d = await showDatePicker(
            context: context,
            initialDate: value ?? now,
            firstDate: DateTime(1950),
            lastDate: DateTime(now.year + 30),
            locale: const Locale('pt', 'BR'),
          );
          if (d != null) onChanged(d);
        },
        child: Text(value == null ? 'Selecione' : fmtDate(localDateToIso(value)),
            style: value == null ? TextStyle(color: Theme.of(context).hintColor) : null),
      );
}

// ───────────────────────────────────── cor ─────────────────────────────────────

const _palette = [
  '#ef4444', '#f97316', '#eab308', '#22c55e', '#10b981', '#06b6d4',
  '#3b82f6', '#6366f1', '#a855f7', '#ec4899', '#64748b', '#111827',
];

Color? parseHex(String? hex) {
  if (hex == null) return null;
  final h = hex.replaceFirst('#', '');
  if (h.length != 6 && h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  if (v == null) return null;
  return Color(h.length == 6 ? 0xFF000000 | v : v);
}

class ColorFieldWidget extends StatelessWidget {
  const ColorFieldWidget({super.key, required this.label, required this.value, required this.onChanged, this.error});
  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String? error;

  @override
  Widget build(BuildContext context) => _Frame(
        label: label,
        error: error,
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in _palette)
            GestureDetector(
              onTap: () => onChanged(c),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: parseHex(c),
                  shape: BoxShape.circle,
                  border: Border.all(
                    width: value?.toLowerCase() == c ? 3 : 1,
                    color: value?.toLowerCase() == c ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
            ),
          if (value != null) TextButton(onPressed: () => onChanged(null), child: const Text('Limpar')),
        ]),
      );
}

// ───────────────────────────────────── imagem ─────────────────────────────────────

/// Escolhe/envia imagem. O valor do formulário é o `imageUrl` a salvar ("storage:...")
/// ou a URL assinada atual (inalterada) ao editar.
class ImageFieldWidget extends ConsumerStatefulWidget {
  const ImageFieldWidget({super.key, required this.label, required this.value, required this.onChanged});
  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  ConsumerState<ImageFieldWidget> createState() => _ImageFieldWidgetState();
}

class _ImageFieldWidgetState extends ConsumerState<ImageFieldWidget> {
  bool _busy = false;
  String? _uploadedPreview; // URL assinada da imagem recém-enviada

  String? get _preview {
    final v = widget.value;
    if (v == null) return null;
    return v.startsWith('storage:') ? _uploadedPreview : v;
  }

  Future<void> _pick(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    if (file == null) return;
    setState(() => _busy = true);
    try {
      final up = await ref.read(apiProvider).uploadImage(file.path);
      _uploadedPreview = up.url;
      widget.onChanged(up.imageUrl);
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _Frame(
        label: widget.label,
        hint: 'JPEG, PNG, WebP ou GIF até 5 MB',
        child: Row(children: [
          NetImage(_preview, size: 72, radius: 12),
          const SizedBox(width: 16),
          Expanded(
            child: Wrap(spacing: 8, runSpacing: 4, children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                icon: _busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.photo_library_outlined),
                label: const Text('Galeria'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _pick(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Câmera'),
              ),
              if (widget.value != null)
                TextButton(
                  onPressed: () {
                    _uploadedPreview = null;
                    widget.onChanged(null);
                  },
                  child: const Text('Remover'),
                ),
            ]),
          ),
        ]),
      );
}
