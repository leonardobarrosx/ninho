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
    final rows = <Row>[
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
    final rows = <Row>[
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
    final rows = <Row>[
      {
        'id': 'x',
        'kind': 'expense',
        'amount_cents': 20000,
        'recurrence': 'monthly',
        'start_date': '2026-10-14',
      },
    ];
    final paid = <Row>[
      {'entry_id': 'x', 'occurrence': '2026-10-14', 'amount_cents': 15000},
    ];
    final summary = MonthSummary(occurrences(rows, paid, DateTime(2026, 10)));
    expect(summary.realized, -15000);
    expect(summary.sum(false, paid: false), 0);
    expect(summary.balance, -15000);
  });
  test('end dates stop recurrence without dropping the final day', () {
    final rows = <Row>[
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
}
