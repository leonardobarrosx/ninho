import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ninho/main.dart';
import 'package:ninho/screens.dart';
import 'package:ninho/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Headlines keep their last two words together with a no-break space.
const overview = 'Seu próximo passo, mais\u00a0claro.';
const health = 'Cuidado também é\u00a0organização.';

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
        ('Saúde', health),
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
      expect(find.text(health), findsOneWidget);
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
    expect(find.text(health), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(overview), findsOneWidget);
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

  testWidgets('money amounts use figures of equal width', (tester) async {
    await openDemo(tester);
    final amount = RegExp(r'^R\$\s[\d.]+,\d\d$');
    for (final tab in ['Visão geral', 'Finanças']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
      // Summary cards, category bars and entry rows.
      final amounts = tester.widgetList<Text>(
        find.byWidgetPredicate(
          (w) => w is Text && amount.hasMatch(w.data ?? ''),
        ),
      );
      expect(amounts, isNotEmpty);
      for (final text in amounts) {
        expect(
          text.style?.fontFeatures,
          contains(const FontFeature.tabularFigures()),
          reason: '${text.data} in $tab',
        );
      }
    }
  });

  testWidgets('Bebê shows the growth hint once until a line can be drawn', (
    tester,
  ) async {
    const hint = 'Registre ao menos duas medidas para ver a evolução.';
    await openDemo(tester);
    final store = tester.widget<HomeScreen>(find.byType(HomeScreen)).store;
    await tester.tap(find.text('Bebê').last);
    await tester.pumpAndSettle();
    expect(find.text(hint), findsOneWidget);
    expect(find.text('Peso e comprimento'), findsOneWidget);
    // Two weights and one length: the weight line, and the hint for length.
    await store.save('measurements', {
      'baby_id': 'b1',
      'measured_at': '2026-08-20',
      'weight_grams': 3250,
      'length_mm': 490,
    });
    await store.save('measurements', {
      'baby_id': 'b1',
      'measured_at': '2026-09-20',
      'weight_grams': 4120,
      'length_mm': null,
    });
    await tester.pumpAndSettle();
    expect(find.text(hint), findsOneWidget);
    expect(find.text('Comprimento'), findsOneWidget);
    expect(find.text('4,12 kg em 20/09/2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('icons on the mint tint keep 3:1 contrast', (tester) async {
    double contrast(Color a, Color b) {
      final (x, y) = (a.computeLuminance(), b.computeLuminance());
      return (max(x, y) + .05) / (min(x, y) + .05);
    }

    for (final p in [Palette.light, Palette.dark]) {
      // Entry rows and Saúde put the icon on the tint; the summary card puts
      // it on a faint ink circle over the tint.
      final circle = Color.alphaBlend(p.ink.withValues(alpha: .08), p.mintTint);
      expect(contrast(p.mintIcon, p.mintTint), greaterThanOrEqualTo(3));
      expect(contrast(p.mintIcon, circle), greaterThanOrEqualTo(3));
    }
    await openDemo(tester);
    await tester.tap(find.text('Finanças').last);
    await tester.pumpAndSettle();
    final income = find.byWidgetPredicate(
      (w) => w is Icon && w.semanticLabel == 'Receita',
    );
    expect(tester.widget<Icon>(income.first).color, Palette.light.mintIcon);
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
