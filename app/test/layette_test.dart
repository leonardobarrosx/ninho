import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ninho/data.dart';
import 'package:ninho/domain.dart';
import 'package:ninho/gifts.dart';
import 'package:ninho/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

Json row(Store s, String resource, String id) =>
    s.rows(resource).firstWhere((r) => r['id'] == id);

void main() {
  group('the demonstration does what the database triggers do', () {
    test('the main option sets the budget of the item', () async {
      final s = Store(demo: true);
      await s.save('goals', {'chosen_option_id': 'o2'}, id: 'g1');
      expect(row(s, 'goals', 'g1')['target_cents'], 112900);
      await s.save('goals', {'quantity': 2}, id: 'g1');
      expect(row(s, 'goals', 'g1')['target_cents'], 225800);
    });

    test('a new price keeps the old one and enters the history', () async {
      final s = Store(demo: true);
      final before = s.rows('goal_option_prices').length;
      await s.save('goal_options', {'price_cents': 130000}, id: 'o1');
      final o = row(s, 'goal_options', 'o1');
      expect(o['previous_price_cents'], 138990);
      expect(o['price_changed_at'], isNotNull);
      expect(s.rows('goal_option_prices').length, before + 1);
      expect(row(s, 'goals', 'g1')['target_cents'], 130000);
      // Editing the notes is not a price change.
      await s.save('goal_options', {'notes': 'Ver cor'}, id: 'o1');
      expect(s.rows('goal_option_prices').length, before + 1);
    });

    test('without the main option, the cheapest takes its place', () async {
      final s = Store(demo: true);
      await s.remove('goal_options', 'o1');
      expect(row(s, 'goals', 'g1')['chosen_option_id'], 'o2');
      expect(row(s, 'goals', 'g1')['target_cents'], 112900);
      expect(
        s.rows('goal_option_prices').where((h) => h['option_id'] == 'o1'),
        isEmpty,
      );
    });

    test('the first option of an item becomes its main one', () async {
      final s = Store(demo: true);
      final o = await s.save('goal_options', {
        'goal_id': 'g2',
        'title': 'Kit body',
        'price_cents': 3000,
      });
      expect(row(s, 'goals', 'g2')['chosen_option_id'], o!['id']);
      expect(row(s, 'goals', 'g2')['target_cents'], 3000 * 20);
    });

    test('an item takes five options at most', () async {
      final s = Store(demo: true);
      for (var i = 0; i < 2; i++) {
        await s.save('goal_options', {'goal_id': 'g1', 'title': 'Outra $i'});
      }
      await expectLater(
        s.save('goal_options', {'goal_id': 'g1', 'title': 'Sexta'}),
        throwsException,
      );
    });

    test('deleting an item deletes its options and prices', () async {
      final s = Store(demo: true);
      await s.remove('goals', 'g3');
      expect(
        s.rows('goal_options').where((o) => o['goal_id'] == 'g3'),
        isEmpty,
      );
      expect(
        s.rows('goal_option_prices').where((h) => h['option_id'] == 'o4'),
        isEmpty,
      );
    });
  });

  testWidgets('an item compares its options and switches the main one', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const NinhoApp());
    await tester.tap(find.text('Explorar demonstração'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enxoval').last);
    await tester.pumpAndSettle();
    expect(find.text('Enxoval com as opções escolhidas'), findsOneWidget);
    expect(find.text('2 preços mudaram nesta\u00a0semana'), findsOneWidget);

    final open = find.text('Opções e preços').first;
    await tester.ensureVisible(open);
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(find.text('Mais barata e mais\u00a0cara'), findsOneWidget);
    expect(find.text('Escolher a mais barata'), findsOneWidget);
    expect(find.textContaining('orçamento ${money(138990)}'), findsOneWidget);

    final choose = find.text('Tornar principal').first;
    await tester.ensureVisible(choose);
    await tester.tap(choose);
    await tester.pumpAndSettle();
    expect(find.textContaining('orçamento ${money(112900)}'), findsOneWidget);
    expect(find.text('Escolher a mais barata'), findsNothing);

    final history = find.text('Histórico').first;
    await tester.ensureVisible(history);
    await tester.tap(history);
    await tester.pumpAndSettle();
    expect(find.text('Histórico de\u00a0preço'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('Pix keys are written the way the BR Code expects', () {
    expect(pixKey('cpf', '123.456.789-09'), '12345678909');
    expect(pixKey('cnpj', '12.345.678/0001-95'), '12345678000195');
    expect(pixKey('phone', '(81) 99999-1234'), '+5581999991234');
    expect(pixKey('phone', '+55 81 99999-1234'), '+5581999991234');
    expect(pixKey('email', ' Ana@Exemplo.com '), 'ana@exemplo.com');
    expect(
      pixKey('random', '123E4567-E89B-12D3-A456-426614174000'),
      '123e4567-e89b-12d3-a456-426614174000',
    );
    expect(pixKey('cpf', '1234'), isNull);
    expect(pixKey('email', 'ana'), isNull);
    expect(pixKeyType('+5581999991234'), 'phone');
    expect(pixKeyType('12345678909'), 'cpf');
  });

  test('list addresses are short, plain and readable', () {
    expect(slugify('Enxoval de Maria & João!'), 'enxoval-de-maria-joao');
    expect(validSlug(slugify('Enxoval de Maria & João!')), isTrue);
    expect(slugify('x' * 60).length, 40);
    expect(validSlug('ab'), isFalse);
    expect(validSlug('ana--pedro'), isFalse);
    expect(joinNames(['Ana', 'Bia', 'Caio']), 'Ana, Bia e Caio');
  });

  testWidgets('the family confirms a Pix and it goes into the reserve', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const NinhoApp());
    await tester.tap(find.text('Explorar demonstração'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enxoval').last);
    await tester.pumpAndSettle();
    final banner = find.text('Lista de presentes com Pix');
    await tester.ensureVisible(banner);
    await tester.tap(banner);
    await tester.pumpAndSettle();
    expect(find.text('Presentes recebidos'), findsOneWidget);
    expect(find.text('Tia Rosa'), findsOneWidget);
    final confirm = find.text('Confirmar');
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.text('Confirmar'), findsNothing);
    expect(find.textContaining('${money(62000)} confirmados'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
