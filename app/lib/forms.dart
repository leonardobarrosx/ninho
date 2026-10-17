import 'package:flutter/material.dart';
import 'domain.dart';
import 'theme.dart';

class FieldSpec {
  final String key, label, type;
  final Map<String, String>? options;
  final bool optional;
  final int min, max;
  const FieldSpec(
    this.key,
    this.label, {
    this.type = 'text',
    this.options,
    this.optional = false,
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
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(
                  labelText: 'Sua senha, para confirmar',
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
  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      final v = widget.initial[f.key];
      if (f.options != null) {
        selected[f.key] = v ?? (f.optional ? null : f.options!.keys.first);
      } else {
        controls[f.key] = TextEditingController(
          text: v == null
              ? ''
              : f.type == 'money'
              ? ((v as num) / 100).toStringAsFixed(2).replaceAll('.', ',')
              : v.toString(),
        );
      }
    }
  }

  @override
  void dispose() {
    for (final c in controls.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? validate(FieldSpec f, String? v) {
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
    if (f.type == 'date') {
      final date = DateTime.tryParse(v);
      if (date == null || iso(date) != v) return 'Selecione uma data válida';
    }
    if (f.type == 'text' && v.trim().length > (f.max < 120 ? f.max : 120)) {
      return 'Texto muito longo';
    }
    if (f.type == 'notes' && v.length > 2000) return 'Use até 2.000 caracteres';
    return null;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.help != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Text(
                    widget.help!,
                    style: TextStyle(color: Palette.of(context).muted),
                  ),
                ),
              for (final f in widget.fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: f.options != null
                      ? DropdownButtonFormField<String>(
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
                                child: Text(
                                  e.value,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (v) => selected[f.key] = v,
                          validator: (v) =>
                              !f.optional && (v == null || v.isEmpty)
                              ? 'Selecione uma opção'
                              : null,
                        )
                      : TextFormField(
                          controller: controls[f.key],
                          decoration: InputDecoration(
                            labelText: f.label,
                            suffixIcon: f.type == 'date'
                                ? const Icon(Icons.calendar_today_outlined)
                                : null,
                          ),
                          readOnly: f.type == 'date',
                          keyboardType: f.type == 'money'
                              ? const TextInputType.numberWithOptions(
                                  decimal: true,
                                )
                              : f.type == 'int'
                              ? TextInputType.number
                              : TextInputType.text,
                          maxLines: f.type == 'notes' ? 3 : 1,
                          validator: (v) => validate(f, v),
                          onTap: f.type == 'date'
                              ? () async {
                                  final now = DateTime.now();
                                  final chosen = await showDatePicker(
                                    context: context,
                                    initialDate:
                                        DateTime.tryParse(
                                          controls[f.key]!.text,
                                        ) ??
                                        now,
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime(2100),
                                  );
                                  if (chosen != null) {
                                    controls[f.key]!.text = iso(chosen);
                                  }
                                }
                              : null,
                        ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (!form.currentState!.validate()) return;
          final values = <String, dynamic>{};
          for (final f in widget.fields) {
            if (f.options != null) {
              values[f.key] = selected[f.key] == '' ? null : selected[f.key];
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
        },
        child: const Text('Salvar'),
      ),
    ],
  );
}
