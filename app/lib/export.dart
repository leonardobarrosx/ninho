import 'dart:convert';
import 'dart:typed_data';
import 'package:share_plus/share_plus.dart';
import 'domain.dart';

/// Spreadsheets of the family's data, a Plus benefit. Each one is a CSV in the
/// format Excel and Google Sheets open in Portuguese: semicolons between
/// columns, commas in amounts and a byte order mark so accents come out right.
class Sheet {
  const Sheet(this.name, this.header, this.rows);
  final String name;
  final List<String> header;
  final List<List<Object?>> rows;

  String get csv => '﻿${[header, ...rows].map(_line).join('\r\n')}\r\n';
  Uint8List get bytes => Uint8List.fromList(utf8.encode(csv));

  static String _line(List<Object?> cells) => cells.map(_cell).join(';');

  static String _cell(Object? value) {
    var text = switch (value) {
      null => '',
      DateTime d => dayText(d),
      _ => '$value',
    };
    // A cell that starts like a formula is read as text, so a title such as
    // "=HYPERLINK(...)" can't run in the spreadsheet. A negative amount stays a
    // number.
    if (text.isNotEmpty &&
        '=+-@\t\r'.contains(text[0]) &&
        !RegExp(r'^-\d+(,\d+)?$').hasMatch(text)) {
      text = "'$text";
    }
    if (text.contains(RegExp('[;"\r\n]'))) {
      text = '"${text.replaceAll('"', '""')}"';
    }
    return text;
  }
}

/// An amount in cents as a spreadsheet number, such as 1234,50.
String amount(Object? cents) {
  if (cents is! num) return '';
  final c = cents.toInt();
  final sign = c < 0 ? '-' : '';
  final abs = c.abs();
  return '$sign${abs ~/ 100},${(abs % 100).toString().padLeft(2, '0')}';
}

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

int _byDate(Json a, Json b, String key) =>
    '${a[key] ?? ''}'.compareTo('${b[key] ?? ''}');

/// Income and expenses.
Sheet financeSheet(List<Json> entries) => Sheet(
  'ninho-financas.csv',
  [
    'Data',
    'Até',
    'Tipo',
    'Descrição',
    'Categoria',
    'Valor (R\$)',
    'Repete',
    'Observações',
  ],
  [
    for (final e in [...entries]..sort((a, b) => _byDate(a, b, 'start_date')))
      [
        _date(e['start_date']),
        _date(e['end_date']),
        e['kind'] == 'income' ? 'Receita' : 'Despesa',
        e['title'],
        e['category'],
        amount(e['amount_cents']),
        e['recurrence'] == 'monthly' ? 'Todo mês' : 'Uma vez',
        e['notes'],
      ],
  ],
);

/// The layette: one line per option of each item, or one line for an item
/// with no options, so the stores and prices compared stay side by side.
Sheet layetteSheet(List<Json> goals, List<Json> options) {
  final byGoal = <Object?, List<Json>>{};
  for (final o in options) {
    (byGoal[o['goal_id']] ??= []).add(o);
  }
  final sorted = [...goals]
    ..sort((a, b) {
      final order = number(a, 'sort_order').compareTo(number(b, 'sort_order'));
      return order != 0 ? order : _byDate(a, b, 'created_at');
    });
  return Sheet(
    'ninho-enxoval.csv',
    [
      'Item',
      'Categoria',
      'Prioridade',
      'Quantidade',
      'Já tem',
      'Meta (R\$)',
      'Guardado (R\$)',
      'Na lista de presentes',
      'Opção',
      'Escolhida',
      'Loja',
      'Preço (R\$)',
      'Preço sem desconto (R\$)',
      'Link',
    ],
    [
      for (final g in sorted)
        for (final o in byGoal[g['id']] ?? <Json?>[null])
          [
            g['title'],
            g['category'],
            priorityLabels[g['priority']] ?? '',
            g['quantity'],
            g['acquired'],
            amount(g['target_cents']),
            amount(g['saved_cents']),
            g['gift'] == false ? 'Não' : 'Sim',
            o?['title'],
            o == null ? '' : (o['id'] == g['chosen_option_id'] ? 'Sim' : 'Não'),
            o?['store'],
            amount(o?['price_cents']),
            amount(o?['list_price_cents']),
            o?['url'],
          ],
    ],
  );
}

/// Appointments, exams, medicines and vaccines.
Sheet healthSheet(List<Json> events, List<Json> babies) {
  final names = {for (final b in babies) b['id']: b['name']};
  return Sheet(
    'ninho-saude.csv',
    [
      'Data',
      'Tipo',
      'Descrição',
      'Bebê',
      'Profissional ou local',
      'Feito',
      'Observações',
    ],
    [
      for (final e in [...events]..sort((a, b) => _byDate(a, b, 'event_date')))
        [
          _date(e['event_date']),
          typeLabels[e['event_type']] ?? '',
          e['title'],
          names[e['baby_id']] ?? '',
          e['provider'],
          e['completed'] == true ? 'Sim' : 'Não',
          e['notes'],
        ],
    ],
  );
}

/// Opens the share sheet with the three spreadsheets, or downloads them where
/// sharing files is not possible, as in most desktop browsers.
Future<void> shareSheets(List<Sheet> sheets) => SharePlus.instance.share(
  ShareParams(
    subject: 'Planilhas do Ninho',
    files: [
      for (final s in sheets)
        XFile.fromData(s.bytes, mimeType: 'text/csv', name: s.name),
    ],
    fileNameOverrides: [for (final s in sheets) s.name],
  ),
);
