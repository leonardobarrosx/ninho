import 'package:flutter/material.dart';
import 'domain.dart';
import 'theme.dart';
import 'widgets.dart';

class FieldSpec {
  final String key, label, type;
  final Map<String, String>? options;
  final bool optional;
  // Shows the options side by side instead of in a dropdown. For required
  // fields with two or three short options.
  final bool segmented;
  final int min, max;
  const FieldSpec(
    this.key,
    this.label, {
    this.type = 'text',
    this.options,
    this.optional = false,
    this.segmented = false,
    this.min = 0,
    this.max = 99999999999,
  });
}

/// Confirms an account deletion with the account password, which pops as the
/// result. A slip of the finger cannot erase a family's records, and neither
/// can someone holding an unlocked phone.
class DeleteAccountDialog extends StatefulWidget {
  const DeleteAccountDialog({super.key});
  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  final password = TextEditingController();
  bool hidden = true;
  bool get confirmed => password.text.isNotEmpty;
  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return AlertDialog(
      title: const Text('Excluir sua conta?'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Seu acesso e seu e-mail saem do Ninho na hora. Isto não pode ser desfeito.',
              ),
              const SizedBox(height: 12),
              Text(
                '• Famílias em que só você participa são apagadas, com todos os registros.\n'
                '• Famílias com outras pessoas continuam com elas. Se você criou alguma, quem entrou primeiro passa a administrá-la.',
                style: TextStyle(color: p.muted, height: 1.5),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: password,
                autofocus: true,
                obscureText: hidden,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: 'Sua senha, para confirmar',
                  suffixIcon: PasswordToggle(
                    hidden: hidden,
                    onPressed: () => setState(() => hidden = !hidden),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: confirmed
              ? () => Navigator.pop(context, password.text)
              : null,
          style: FilledButton.styleFrom(
            backgroundColor: p.danger,
            foregroundColor: p.background,
          ),
          child: const Text('Excluir conta'),
        ),
      ],
    );
  }
}

Future<Json?> editForm(
  BuildContext context,
  String title,
  List<FieldSpec> fields, {
  Json initial = const {},
  String? help,
}) => showDialog<Json>(
  context: context,
  // A tap beside the form must not throw away what was typed.
  barrierDismissible: false,
  builder: (_) =>
      EditDialog(title: title, fields: fields, initial: initial, help: help),
);

class EditDialog extends StatefulWidget {
  final String title;
  final List<FieldSpec> fields;
  final Json initial;
  final String? help;
  const EditDialog({
    super.key,
    required this.title,
    required this.fields,
    required this.initial,
    this.help,
  });
  @override
  State<EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<EditDialog> {
  final form = GlobalKey<FormState>();
  final Map<String, TextEditingController> controls = {};
  final Json selected = {};
  // Date fields show the day first and keep the date here; it is saved in
  // ISO format.
  final Map<String, DateTime?> dates = {};
  // Whether anything changed. Then the back button asks before discarding.
  bool dirty = false;
  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      final v = widget.initial[f.key];
      if (f.options != null) {
        selected[f.key] = v ?? (f.optional ? null : f.options!.keys.first);
        continue;
      }
      if (f.type == 'date') {
        final date = v == null ? null : DateTime.tryParse(v as String);
        dates[f.key] = date;
        controls[f.key] = TextEditingController(
          text: date == null ? '' : dayText(date),
        );
        continue;
      }
      controls[f.key] = TextEditingController(
        text: v == null
            ? ''
            : f.type == 'money'
            ? ((v as num) / 100).toStringAsFixed(2).replaceAll('.', ',')
            : v.toString(),
      );
    }
  }

  @override
  void dispose() {
    for (final c in controls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void changed() {
    if (!dirty) setState(() => dirty = true);
  }

  String? validate(FieldSpec f, String? v) {
    if (f.type == 'date') {
      return dates[f.key] == null && !f.optional ? 'Selecione uma data' : null;
    }
    if (v == null || v.trim().isEmpty) {
      return f.optional ? null : 'Preencha este campo';
    }
    if (f.type == 'money' || f.type == 'int') {
      try {
        final n = f.type == 'money' ? parseMoney(v) : int.parse(v);
        if (n < f.min || n > f.max) return 'Valor fora do intervalo permitido';
      } catch (_) {
        return f.type == 'money'
            ? 'Exemplo: 1.250,90'
            : 'Informe um número inteiro';
      }
    }
    if (f.type == 'text' && v.trim().length > (f.max < 120 ? f.max : 120)) {
      return 'Texto muito longo';
    }
    if (f.type == 'notes' && v.length > 2000) return 'Use até 2.000 caracteres';
    return null;
  }

  Future<void> pickDate(FieldSpec f) async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: dates[f.key] ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (chosen == null || !mounted) return;
    setState(() {
      dates[f.key] = chosen;
      controls[f.key]!.text = dayText(chosen);
      dirty = true;
    });
  }

  void clearDate(FieldSpec f) => setState(() {
    dates[f.key] = null;
    controls[f.key]!.clear();
    dirty = true;
  });

  void save() {
    if (!form.currentState!.validate()) return;
    final values = <String, dynamic>{};
    for (final f in widget.fields) {
      if (f.options != null) {
        values[f.key] = selected[f.key] == '' ? null : selected[f.key];
        continue;
      }
      if (f.type == 'date') {
        values[f.key] = dates[f.key] == null ? null : iso(dates[f.key]!);
        continue;
      }
      final text = controls[f.key]!.text.trim();
      values[f.key] = text.isEmpty && f.optional
          ? (f.type == 'notes' || f.type == 'text' ? '' : null)
          : f.type == 'money'
          ? parseMoney(text)
          : f.type == 'int'
          ? int.parse(text)
          : text;
    }
    Navigator.pop(context, values);
  }

  /// The back button or Esc, after a change: discarding takes a second
  /// answer. Cancelar and the close button discard at once.
  Future<void> leave() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Descartar alterações?'),
        content: const Text('O que você preencheu será perdido.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Continuar editando'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.pop(context);
  }

  Widget field(FieldSpec f, {required bool last}) {
    final p = Palette.of(context);
    if (f.options != null && f.segmented) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(f.label, style: TextStyle(color: p.muted)),
          ),
          SegmentedButton<String>(
            segments: [
              for (final e in f.options!.entries)
                ButtonSegment(value: e.key, label: Text(e.value)),
            ],
            selected: {selected[f.key] as String},
            showSelectedIcon: false,
            expandedInsets: EdgeInsets.zero,
            onSelectionChanged: (v) => setState(() {
              selected[f.key] = v.first;
              dirty = true;
            }),
          ),
        ],
      );
    }
    if (f.options != null) {
      return DropdownButtonFormField<String>(
        value: selected[f.key] as String?,
        isExpanded: true,
        decoration: InputDecoration(labelText: f.label),
        items: [
          if (f.optional)
            const DropdownMenuItem<String>(
              value: '',
              child: Text('Não vincular'),
            ),
          for (final e in f.options!.entries)
            DropdownMenuItem(
              value: e.key,
              child: Text(e.value, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) {
          selected[f.key] = v;
          changed();
        },
        validator: (v) => !f.optional && (v == null || v.isEmpty)
            ? 'Selecione uma opção'
            : null,
      );
    }
    final date = f.type == 'date';
    return TextFormField(
      controller: controls[f.key],
      decoration: InputDecoration(
        labelText: f.label,
        suffixIcon: !date
            ? null
            : f.optional && dates[f.key] != null
            ? IconButton(
                tooltip: 'Limpar data',
                onPressed: () => clearDate(f),
                icon: const Icon(Icons.close),
              )
            : const Icon(Icons.calendar_today_outlined),
      ),
      readOnly: date,
      keyboardType: f.type == 'money'
          ? const TextInputType.numberWithOptions(decimal: true)
          : f.type == 'int'
          ? TextInputType.number
          : f.type == 'notes'
          ? TextInputType.multiline
          : TextInputType.text,
      // The keyboard's action key moves to the next field, and closes the
      // keyboard on the last one. Notes take line breaks.
      textInputAction: f.type == 'notes'
          ? TextInputAction.newline
          : last
          ? TextInputAction.done
          : TextInputAction.next,
      maxLines: f.type == 'notes' ? 3 : 1,
      validator: (v) => validate(f, v),
      onChanged: (_) => changed(),
      onTap: date ? () => pickDate(f) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final last = widget.fields.lastIndexWhere(
      (f) => f.options == null && f.type != 'date' && f.type != 'notes',
    );
    final body = Form(
      key: form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.help != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Text(widget.help!, style: TextStyle(color: p.muted)),
            ),
          for (final (i, f) in widget.fields.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: field(f, last: i == last),
            ),
        ],
      ),
    );
    // On a phone, a form with more than three fields takes the whole screen.
    final full =
        MediaQuery.sizeOf(context).width < 600 && widget.fields.length > 3;
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) leave();
      },
      child: full
          ? Dialog.fullscreen(
              backgroundColor: p.background,
              child: Scaffold(
                appBar: AppBar(
                  leading: IconButton(
                    tooltip: 'Cancelar',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                  title: Text(widget.title),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: TextButton(
                        onPressed: save,
                        child: const Text('Salvar'),
                      ),
                    ),
                  ],
                ),
                body: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  child: body,
                ),
              ),
            )
          : AlertDialog(
              title: Text(widget.title),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(child: body),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                FilledButton(onPressed: save, child: const Text('Salvar')),
              ],
            ),
    );
  }
}
