import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ninho/main.dart';
import 'package:ninho/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final theme in [NinhoTheme.light, NinhoTheme.dark]) {
    testWidgets('demo navigates every tab at mobile width (${theme.name})', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(NinhoApp(initialTheme: theme));
      await tester.tap(find.text('Explorar demonstração'));
      await tester.pumpAndSettle();
      expect(find.text('Saldo previsto'), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (final (tab, heading) in [
        ('Finanças', 'Finanças da família'),
        ('Bebê', 'Cada fase, registrada.'),
        ('Enxoval', 'Planos que ganham forma.'),
        ('Saúde', 'Cuidado também é organização.'),
        ('Família', 'Pessoas nesta família'),
      ]) {
        await tester.tap(find.text(tab).last);
        await tester.pumpAndSettle();
        expect(find.text(heading), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  }
  testWidgets('desktop dashboard shows navigation rail', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const NinhoApp());
    await tester.tap(find.text('Explorar demonstração'));
    await tester.pumpAndSettle();
    expect(find.text('Para onde vai o dinheiro'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('theme picker switches to dark and remembers it', (tester) async {
    await tester.pumpWidget(const NinhoApp());
    await tester.tap(find.byTooltip('Tema'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Escuro'));
    await tester.pumpAndSettle();
    final context = tester.element(find.text('Explorar demonstração'));
    expect(Theme.of(context).brightness, Brightness.dark);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ninho.theme'), 'dark');
    expect(await savedTheme(), NinhoTheme.dark);
  });
}
