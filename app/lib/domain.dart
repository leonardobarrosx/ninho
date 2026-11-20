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

/// A whole number field that may be empty, such as a price not found yet.
int? maybe(Json row, String key) => (row[key] as num?)?.toInt();

/// The first web link in [text], so a link shared from a store's app along
/// with its sales pitch still works. A link without http gets https. Null
/// when there is no usable link.
String? normalizeLink(String text) {
  final found = RegExp(r'https?://\S+', caseSensitive: false).firstMatch(text);
  var link = (found?.group(0) ?? text.trim()).replaceAll(
    RegExp(r'[).,;]+$'),
    '',
  );
  if (link.isEmpty || link.contains(RegExp(r'\s'))) return null;
  if (!link.toLowerCase().startsWith('http')) link = 'https://$link';
  final uri = Uri.tryParse(link);
  if (uri == null ||
      !uri.host.contains('.') ||
      uri.userInfo.isNotEmpty ||
      link.length > 2000) {
    return null;
  }
  return link;
}

/// The options of a layette item: the main one first, then the cheapest.
/// Options without a price go last.
List<Json> optionsOf(Json goal, List<Json> options) {
  final list = options.where((o) => o['goal_id'] == goal['id']).toList();
  int rank(Json o) => o['id'] == goal['chosen_option_id'] ? 0 : 1;
  list.sort((a, b) {
    final main = rank(a).compareTo(rank(b));
    if (main != 0) return main;
    // Without a price, an option sorts as if it cost more than any other.
    const unpriced = 1 << 50;
    return (maybe(a, 'price_cents') ?? unpriced).compareTo(
      maybe(b, 'price_cents') ?? unpriced,
    );
  });
  return list;
}

/// The discount a store shows, in percent: the list price against the price.
int? discountPercent(Json option) {
  final price = maybe(option, 'price_cents');
  final list = maybe(option, 'list_price_cents');
  if (price == null || list == null || list <= price || list == 0) return null;
  final percent = ((list - price) * 100 / list).round();
  return percent == 0 ? null : percent;
}

/// A change of price or discount found in the last [days] days.
class PriceAlert {
  final int previous, current;
  final int? previousList, currentList;
  final DateTime at;
  const PriceAlert(
    this.previous,
    this.current,
    this.previousList,
    this.currentList,
    this.at,
  );
  int get delta => current - previous;
  String get text => delta < 0
      ? 'Baixou ${money(-delta)}'
      : delta > 0
      ? 'Subiu ${money(delta)}'
      : currentList == null
      ? 'Desconto acabou'
      : 'Desconto mudou';
}

PriceAlert? priceAlert(Json option, DateTime now, {int days = 7}) {
  final at = DateTime.tryParse(option['price_changed_at'] as String? ?? '');
  final previous = maybe(option, 'previous_price_cents');
  final current = maybe(option, 'price_cents');
  if (at == null || previous == null || current == null) return null;
  if (now.difference(at.toLocal()).inDays >= days) return null;
  return PriceAlert(
    previous,
    current,
    maybe(option, 'previous_list_price_cents'),
    maybe(option, 'list_price_cents'),
    at.toLocal(),
  );
}

/// What the layette costs: with the options chosen, and with the cheapest or
/// the priciest option of each item. Items without priced options count
/// their budget in all three.
class LayetteTotals {
  final int chosen, cheapest, priciest, compared;
  const LayetteTotals(this.chosen, this.cheapest, this.priciest, this.compared);
}

LayetteTotals layetteTotals(List<Json> goals, List<Json> options) {
  var chosen = 0, cheapest = 0, priciest = 0, compared = 0;
  for (final g in goals) {
    final quantity = number(g, 'quantity');
    final prices = [
      for (final o in options)
        if (o['goal_id'] == g['id'] && o['price_cents'] != null)
          number(o, 'price_cents'),
    ];
    final budget = number(g, 'target_cents');
    chosen += budget;
    if (prices.isEmpty) {
      cheapest += budget;
      priciest += budget;
      continue;
    }
    if (prices.length > 1) compared++;
    prices.sort();
    cheapest += prices.first * quantity;
    priciest += prices.last * quantity;
  }
  return LayetteTotals(chosen, cheapest, priciest, compared);
}

/// The layette items in the family's order.
List<Json> inOrder(List<Json> goals) {
  // Dart's sort is not stable, so equal positions keep the loaded order.
  final indexed = goals.indexed.toList()
    ..sort((a, b) {
      final order = number(
        a.$2,
        'sort_order',
      ).compareTo(number(b.$2, 'sort_order'));
      return order != 0 ? order : a.$1.compareTo(b.$1);
    });
  return [for (final (_, g) in indexed) g];
}
