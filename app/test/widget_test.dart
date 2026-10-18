import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ninho/main.dart';
import 'package:ninho/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Opens the demonstration at phone size.
Future<void> openDemo(
  WidgetTester tester, {
  NinhoTheme theme = NinhoTheme.light,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(NinhoApp(initialTheme: theme));
  await tester.tap(find.text('Explorar demonstração'));
  await tester.pumpAndSettle();
}

/// On a phone, Família opens from the account menu.
Future<void> openFamily(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Conta e ajustes'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Família e conta'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final theme in [NinhoTheme.light, NinhoTheme.dark]) {
    testWidgets('demo navigates every tab at mobile width (${theme.name})', (
      tester,
    ) async {
      await openDemo(tester, theme: theme);
      expect(find.text('Saldo previsto'), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (final (tab, heading) in [
        ('Finanças', 'Finanças da família'),
        ('Bebê', 'Cada fase, registrada.'),
        ('Enxoval', 'Planos que ganham forma.'),
        ('Saúde', 'Cuidado também é organização.'),
      ]) {
        await tester.tap(find.text(tab).last);
        await tester.pumpAndSettle();
        expect(find.text(heading), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await openFamily(tester);
      expect(find.text('Pessoas nesta família'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      expect(find.text('Cuidado também é organização.'), findsOneWidget);
    });
  }

  testWidgets('the bottom bar keeps five tabs on a narrow phone', (
    tester,
  ) async {
    await openDemo(tester, size: const Size(360, 760));
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(find.text('Família'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('each tab keeps its own scroll position', (tester) async {
    await openDemo(tester);
    const overview = 'Seu próximo passo, mais claro.';
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    expect(find.text(overview).hitTestable(), findsNothing);
    await tester.tap(find.text('Finanças').last);
    await tester.pumpAndSettle();
    expect(find.text('Finanças da família').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Visão geral').last);
    await tester.pumpAndSettle();
    expect(
      find.text(overview).hitTestable(),
      findsNothing,
      reason: 'Visão geral comes back where it was left',
    );
  });

  testWidgets('the back button returns to the last tab, then to the start', (
    tester,
  ) async {
    await openDemo(tester);
    await tester.tap(find.text('Saúde').last);
    await tester.pumpAndSettle();
    await openFamily(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Cuidado também é organização.'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Seu próximo passo, mais claro.'), findsOneWidget);
  });

  testWidgets('the account menu switches the theme and remembers it', (
    tester,
  ) async {
    await openDemo(tester);
    await tester.tap(find.byTooltip('Conta e ajustes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tema escuro'));
    await tester.pumpAndSettle();
    final context = tester.element(find.text('Saldo previsto'));
    expect(Theme.of(context).brightness, Brightness.dark);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ninho.theme'), 'dark');
  });

  testWidgets('paying shows the state and offers an undo', (tester) async {
    final semantics = tester.ensureSemantics();
    await openDemo(tester);
    await tester.tap(find.text('Finanças').last);
    await tester.pumpAndSettle();
    expect(find.text('Pago'), findsOneWidget, reason: 'the rent is paid');
    final pay = find.bySemanticsLabel('Pagar Supermercado');
    await tester.ensureVisible(pay);
    await tester.pumpAndSettle();
    await tester.tap(pay);
    await tester.pumpAndSettle();
    expect(find.text('Pagamento registrado.'), findsOneWidget);
    expect(find.text('Pago'), findsNWidgets(2));
    expect(find.bySemanticsLabel('Pagar Supermercado'), findsNothing);
    await tester.tap(find.text('Desfazer'));
    await tester.pumpAndSettle();
    expect(find.text('Pagamento desfeito.'), findsOneWidget);
    expect(find.text('Pago'), findsOneWidget);
    expect(find.bySemanticsLabel('Pagar Supermercado'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('health lists pending events apart from completed ones', (
    tester,
  ) async {
    await openDemo(tester);
    await tester.tap(find.text('Saúde').last);
    await tester.pumpAndSettle();
    expect(find.text('Próximos'), findsOneWidget);
    expect(find.text('Realizados'), findsNothing);
    await tester.tap(find.text('Marcar como realizado'));
    await tester.pumpAndSettle();
    expect(find.text('Nenhum compromisso pendente.'), findsOneWidget);
    expect(find.text('Realizados'), findsOneWidget);
    expect(find.text('Reabrir'), findsOneWidget);
  });

  testWidgets('screen readers get items, headings and named buttons', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await openDemo(tester);
    // A summary card reads as one item: label, value and note.
    expect(
      find.bySemanticsLabel(RegExp(r'^Saldo previsto\nR\$\s[\d.]+,\d\d\n')),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(find.text('Contas que pedem atenção')),
      containsSemantics(isHeader: true),
    );
    expect(
      find.bySemanticsLabel(
        RegExp(r'^Moradia: R\$\s[\d.]+,\d\d, \d+% das despesas previstas$'),
      ),
      findsOneWidget,
    );
    // Badges are text, not checkboxes.
    expect(
      tester.getSemantics(find.text('DEMO')),
      containsSemantics(hasCheckedState: false),
    );
    await tester.tap(find.text('Finanças').last);
    await tester.pumpAndSettle();
    // An entry is one item that says what it is; its buttons name it.
    expect(
      find.bySemanticsLabel(RegExp(r'^Despesa\nSupermercado\n')),
      findsOneWidget,
    );
    expect(find.byTooltip('Opções de Supermercado'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('desktop dashboard shows navigation rail', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const NinhoApp());
    await tester.tap(find.text('Explorar demonstração'));
    await tester.pumpAndSettle();
    expect(find.text('Para onde vai o dinheiro'), findsOneWidget);
    expect(find.text('Família'), findsOneWidget, reason: 'in the sidebar');
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
