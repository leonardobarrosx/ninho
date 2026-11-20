import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ninho/export.dart';

void main() {
  test('amounts use a comma and keep the cents', () {
    expect(amount(123450), '1234,50');
    expect(amount(5), '0,05');
    expect(amount(-990), '-9,90');
    expect(amount(null), '');
  });

  test('cells are quoted when needed and formulas stay text', () {
    final csv = const Sheet(
      'x.csv',
      ['A', 'B'],
      [
        ['Berço; branco', 'Diz "oi"'],
        ['=HYPERLINK("x")', '-1+2'],
        ['-12,50', '@x'],
      ],
    ).csv;
    expect(csv.startsWith('﻿'), isTrue);
    expect(csv.substring(1).split('\r\n'), [
      'A;B',
      '"Berço; branco";"Diz ""oi"""',
      '"\'=HYPERLINK(""x"")";\'-1+2',
      "-12,50;'@x",
      '',
    ]);
    expect(utf8.decode(const Sheet('x', ['ç'], []).bytes), '﻿ç\r\n');
  });

  test(
    'the layette has one line per option, and items without options too',
    () {
      final sheet = layetteSheet(
        [
          {
            'id': 'g2',
            'title': 'Carrinho',
            'priority': 'comfort',
            'sort_order': 2,
            'quantity': 1,
            'acquired': 0,
            'target_cents': 150000,
            'chosen_option_id': 'o2',
          },
          {
            'id': 'g1',
            'title': 'Fralda',
            'priority': 'essential',
            'sort_order': 1,
            'quantity': 10,
            'acquired': 2,
            'target_cents': 50000,
            'gift': false,
          },
        ],
        [
          {
            'id': 'o1',
            'goal_id': 'g2',
            'title': 'Modelo A',
            'store': 'Loja 1',
            'price_cents': 159990,
          },
          {
            'id': 'o2',
            'goal_id': 'g2',
            'title': 'Modelo B',
            'store': 'Loja 2',
            'price_cents': 149900,
            'list_price_cents': 169900,
            'url': 'https://loja.test/b',
          },
        ],
      );
      expect(sheet.rows.map((r) => [r[0], r[8], r[9]]), [
        ['Fralda', null, ''],
        ['Carrinho', 'Modelo A', 'Não'],
        ['Carrinho', 'Modelo B', 'Sim'],
      ]);
      expect(sheet.rows[0][7], 'Não');
      expect(sheet.rows[2].sublist(10), [
        'Loja 2',
        '1499,00',
        '1699,00',
        'https://loja.test/b',
      ]);
    },
  );

  test('finances and health read in date order with labels', () {
    final money = financeSheet([
      {
        'title': 'Salário',
        'kind': 'income',
        'amount_cents': 500000,
        'start_date': '2026-11-05',
        'recurrence': 'monthly',
        'category': 'Renda',
      },
      {
        'title': 'Berço',
        'kind': 'expense',
        'amount_cents': 89990,
        'start_date': '2026-10-01',
        'recurrence': 'once',
        'category': 'Enxoval',
      },
    ]);
    expect(
      Sheet('', [], money.rows).csv.substring(1).split('\r\n')[1],
      '01/10/2026;;Despesa;Berço;Enxoval;899,90;Uma vez;',
    );
    final health = healthSheet(
      [
        {
          'title': 'BCG',
          'event_type': 'vaccine',
          'event_date': '2026-12-01',
          'baby_id': 'b1',
          'completed': true,
        },
      ],
      [
        {'id': 'b1', 'name': 'Alice'},
      ],
    );
    expect(health.rows.single.sublist(0, 6).skip(1), [
      'Vacina',
      'BCG',
      'Alice',
      null,
      'Sim',
    ]);
  });
}
