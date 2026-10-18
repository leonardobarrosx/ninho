import 'package:intl/intl.dart';

typedef Json = Map<String, dynamic>;
String money(num cents) =>
    NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(cents / 100);
String decimal(num value, {int digits = 3}) =>
    NumberFormat('#,##0.${'#' * digits}', 'pt_BR').format(value);
String dateText(String? value) => value == null || value.isEmpty
    ? 'Sem data'
    : dayText(DateTime.parse(value));
String dayText(DateTime date) => DateFormat('dd/MM/yyyy').format(date);
String iso(DateTime date) => DateFormat('yyyy-MM-dd').format(date);
int number(Json row, String key) => (row[key] as num? ?? 0).toInt();
int parseMoney(String input) {
  var s = input.replaceAll('R\$', '').replaceAll(' ', '').trim();
  if (s.contains(',')) {
    s = s.replaceAll('.', '').replaceAll(',', '.');
  }
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(s)) {
    throw const FormatException(
      'Use um valor positivo com até 2 casas decimais',
    );
  }
  final parts = s.split('.');
  final value =
      int.parse(parts.first) * 100 +
      (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
  if (value > 99999999999) throw const FormatException('Valor muito alto');
  return value;
}

class Occurrence {
  final Json entry;
  final DateTime date;
  final Json? settlement;
  Occurrence(this.entry, this.date, this.settlement);
  bool get paid => settlement != null;
  bool get income => entry['kind'] == 'income';
  int get amount => number(settlement ?? entry, 'amount_cents');
}

List<Occurrence> occurrences(
  List<Json> entries,
  List<Json> settlements,
  DateTime month,
) {
  final first = DateTime(month.year, month.month);
  final last = DateTime(month.year, month.month + 1, 0);
  final result = <Occurrence>[];
  for (final entry in entries) {
    final start = DateTime.parse(entry['start_date'] as String);
    final end = entry['end_date'] == null
        ? null
        : DateTime.parse(entry['end_date'] as String);
    final day = entry['recurrence'] == 'monthly'
        ? DateTime(month.year, month.month, start.day.clamp(1, last.day))
        : start;
    if (day.isBefore(first) ||
        day.isAfter(last) ||
        day.isBefore(start) ||
        (end != null && day.isAfter(end))) {
      continue;
    }
    Json? paid;
    for (final item in settlements) {
      if (item['entry_id'] == entry['id'] && item['occurrence'] == iso(day)) {
        paid = item;
        break;
      }
    }
    result.add(Occurrence(entry, day, paid));
  }
  result.sort((a, b) => a.date.compareTo(b.date));
  return result;
}

class MonthSummary {
  final List<Occurrence> items;
  MonthSummary(this.items);
  int sum(bool income, {bool? paid}) => items
      .where((e) => e.income == income && (paid == null || e.paid == paid))
      .fold(0, (s, e) => s + e.amount);
  int get balance => sum(true) - sum(false);
  int get realized => sum(true, paid: true) - sum(false, paid: true);
}

int remainingGoal(Json g) {
  final quantity = number(g, 'quantity');
  if (quantity <= 0) return 0;
  final remaining =
      number(g, 'target_cents') *
      (quantity - number(g, 'acquired')) ~/
      quantity;
  return (remaining - number(g, 'saved_cents')).clamp(0, 99999999999);
}

const priorityLabels = {
  'essential': 'Essencial',
  'comfort': 'Conforto',
  'optional': 'Opcional',
};
const typeLabels = {
  'appointment': 'Consulta',
  'exam': 'Exame',
  'medicine': 'Medicamento',
  'vaccine': 'Vacina',
  'other': 'Outro',
};
