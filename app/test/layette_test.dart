import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ninho/data.dart';
import 'package:ninho/domain.dart';
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
    expect(find.text('2 preços mudaram nesta semana'), findsOneWidget);

    final open = find.text('Opções e preços').first;
    await tester.ensureVisible(open);
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(find.text('Mais barata e mais cara'), findsOneWidget);
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
    expect(find.text('Histórico de preço'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
