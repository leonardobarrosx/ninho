import 'package:flutter_test/flutter_test.dart';
import 'package:ninho/domain.dart';

void main() {
  test('BRL uses exact cents and rejects excess precision', () {
    expect(parseMoney('1.234,56'), 123456);
    expect(parseMoney('0,01'), 1);
    expect(parseMoney('12.30'), 1230);
    expect(() => parseMoney('1,234'), throwsFormatException);
    expect(() => parseMoney('-10'), throwsFormatException);
  });
  test('monthly day 31 clamps to February including leap years', () {
    final rows = <Json>[
      {
        'id': 'x',
        'kind': 'expense',
        'amount_cents': 10000,
        'recurrence': 'monthly',
        'start_date': '2024-01-31',
      },
    ];
    expect(
      iso(occurrences(rows, [], DateTime(2024, 2)).single.date),
      '2024-02-29',
    );
    expect(
      iso(occurrences(rows, [], DateTime(2025, 2)).single.date),
      '2025-02-28',
    );
    expect(occurrences(rows, [], DateTime(2023, 12)), isEmpty);
  });
  test('once entries only belong to their month', () {
    final rows = <Json>[
      {
        'id': 'x',
        'kind': 'income',
        'amount_cents': 20000,
        'recurrence': 'once',
        'start_date': '2026-10-14',
      },
    ];
    expect(occurrences(rows, [], DateTime(2026, 11)), isEmpty);
    expect(occurrences(rows, [], DateTime(2026, 10)).length, 1);
  });
  test('settlement keeps historical paid amount', () {
    final rows = <Json>[
      {
        'id': 'x',
        'kind': 'expense',
        'amount_cents': 20000,
        'recurrence': 'monthly',
        'start_date': '2026-10-14',
      },
    ];
    final paid = <Json>[
      {'entry_id': 'x', 'occurrence': '2026-10-14', 'amount_cents': 15000},
    ];
    final summary = MonthSummary(occurrences(rows, paid, DateTime(2026, 10)));
    expect(summary.realized, -15000);
    expect(summary.sum(false, paid: false), 0);
    expect(summary.balance, -15000);
  });
  test('end dates stop recurrence without dropping the final day', () {
    final rows = <Json>[
      {
        'id': 'x',
        'kind': 'expense',
        'amount_cents': 100,
        'recurrence': 'monthly',
        'start_date': '2026-10-14',
        'end_date': '2026-11-14',
      },
    ];
    expect(occurrences(rows, [], DateTime(2026, 11)).length, 1);
    expect(occurrences(rows, [], DateTime(2026, 12)), isEmpty);
  });
  test('gifted units reduce remaining target without spending', () {
    expect(
      remainingGoal({
        'target_cents': 100000,
        'saved_cents': 20000,
        'quantity': 10,
        'acquired': 3,
      }),
      50000,
    );
    expect(
      remainingGoal({
        'target_cents': 100000,
        'saved_cents': 20000,
        'quantity': 10,
        'acquired': 10,
      }),
      0,
    );
  });
  test('measurements use the pt-BR decimal separator', () {
    expect(decimal(3255 / 1000), '3,255');
    expect(decimal(49), '49');
    expect(decimal(1234.5), '1.234,5');
    expect(decimal(3.27, digits: 1), '3,3');
  });
  test('a store link is found in shared text and gets https', () {
    expect(
      normalizeLink('Olha este berço! https://loja.test/berco?id=1. Gostou?'),
      'https://loja.test/berco?id=1',
    );
    expect(normalizeLink('loja.test/p/2'), 'https://loja.test/p/2');
    expect(normalizeLink('http://loja.test/x'), 'http://loja.test/x');
    for (final bad in ['', 'berço', 'https://user:pw@loja.test/x', 'a b.c']) {
      expect(normalizeLink(bad), isNull, reason: bad);
    }
  });
  test('options list the main one, then the cheapest, unpriced last', () {
    final goal = {'id': 'g', 'chosen_option_id': 'c'};
    final options = <Json>[
      {'id': 'x', 'goal_id': 'g', 'price_cents': null},
      {'id': 'b', 'goal_id': 'g', 'price_cents': 900},
      {'id': 'c', 'goal_id': 'g', 'price_cents': 1500},
      {'id': 'a', 'goal_id': 'g', 'price_cents': 500},
      {'id': 'o', 'goal_id': 'other', 'price_cents': 1},
    ];
    expect(optionsOf(goal, options).map((o) => o['id']), ['c', 'a', 'b', 'x']);
  });
  test('a discount needs a list price above the price', () {
    expect(
      discountPercent({'price_cents': 8000, 'list_price_cents': 10000}),
      20,
    );
    expect(
      discountPercent({'price_cents': 8000, 'list_price_cents': 7000}),
      isNull,
    );
    expect(discountPercent({'price_cents': 8000}), isNull);
  });
  test('price alerts last a week and say what changed', () {
    final now = DateTime(2026, 11, 20, 12);
    Json option(int previous, int price, {int? list, int days = 1}) => {
      'previous_price_cents': previous,
      'price_cents': price,
      'list_price_cents': list,
      'previous_list_price_cents': 12000,
      'price_changed_at': now
          .subtract(Duration(days: days))
          .toUtc()
          .toIso8601String(),
    };
    expect(priceAlert(option(10000, 9000), now)!.text, 'Baixou ${money(1000)}');
    expect(priceAlert(option(9000, 10000), now)!.text, 'Subiu ${money(1000)}');
    expect(priceAlert(option(9000, 9000), now)!.text, 'Desconto acabou');
    expect(
      priceAlert(option(9000, 9000, list: 11000), now)!.text,
      'Desconto mudou',
    );
    expect(priceAlert(option(10000, 9000, days: 8), now), isNull);
    expect(priceAlert({'price_cents': 9000}, now), isNull);
  });
  test('layette totals compare chosen, cheapest and priciest options', () {
    final goals = <Json>[
      {'id': 'a', 'quantity': 2, 'target_cents': 3000},
      {'id': 'b', 'quantity': 1, 'target_cents': 5000},
    ];
    final options = <Json>[
      {'goal_id': 'a', 'price_cents': 1500},
      {'goal_id': 'a', 'price_cents': 1000},
      {'goal_id': 'a', 'price_cents': 2500},
      {'goal_id': 'a', 'price_cents': null},
    ];
    final t = layetteTotals(goals, options);
    expect(
      (t.chosen, t.cheapest, t.priciest, t.compared),
      (8000, 7000, 10000, 1),
    );
  });
  test('layette items follow the family order, then the loaded order', () {
    final goals = <Json>[
      {'id': 'a', 'sort_order': 2},
      {'id': 'b'},
      {'id': 'c', 'sort_order': 1},
      {'id': 'd', 'sort_order': 0},
    ];
    expect(inOrder(goals).map((g) => g['id']), ['b', 'd', 'c', 'a']);
  });
}
