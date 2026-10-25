import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ninho/data.dart';
import 'package:ninho/domain.dart';
import 'package:ninho/main.dart';
import 'package:ninho/screens.dart';
import 'package:ninho/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Loads the bundled Nunito, so text takes its real width, as on a phone.
/// Otherwise tests draw every glyph as a square.
Future<void> loadNunito() async {
  final font = FontLoader('Nunito');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    font.addFont(rootBundle.load('assets/fonts/Nunito-$weight.ttf'));
  }
  await font.load();
}

/// The last line of [paragraph], or null when the text fits on one line.
String? lastLine(RenderParagraph paragraph) {
  final text = paragraph.text.toPlainText();
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  );
  if (boxes.map((b) => b.top.round()).toSet().length < 2) return null;
  final start = paragraph.getPositionForOffset(
    Offset(1, (boxes.last.top + boxes.last.bottom) / 2),
  );
  return text.substring(start.offset).trim();
}

/// Headlines and titles on screen whose last line holds a single word.
List<String> orphans(WidgetTester tester) => [
  for (final element in find.byType(RichText).evaluate())
    if (element.renderObject case final RenderParagraph paragraph
        when (paragraph.text.style?.fontSize ?? 0) >= 19)
      if (lastLine(paragraph) case final last?
          when !last.contains(RegExp(r'\s')))
        paragraph.text.toPlainText(),
];

Widget home(Store store) => MaterialApp(
  locale: const Locale('pt', 'BR'),
  supportedLocales: const [Locale('pt', 'BR')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: buildTheme(Palette.light, Brightness.light),
  home: HomeScreen(
    store: store,
    onLogout: () async {},
    theme: NinhoTheme.light,
    onTheme: (_) {},
  ),
);

const tabs = ['Visão geral', 'Finanças', 'Enxoval', 'Bebê', 'Saúde'];

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadNunito();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the bundled Nunito lines up money amounts', () {
    double width(int cents) {
      final painter = TextPainter(
        text: TextSpan(
          text: money(cents),
          style: const TextStyle(
            fontFamily: 'Nunito',
            fontSize: 28,
            fontWeight: FontWeight.w800,
            fontFeatures: tabularFigures,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    expect(
      {
        for (final c in [111111, 888888, 450783, 648730]) width(c),
      },
      {width(100000)},
    );
  });

  for (final width in [360.0, 375.0, 390.0, 412.0]) {
    testWidgets('headlines keep two words on the last line at $width px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final found = <String>[];
      void check(String page) =>
          found.addAll(orphans(tester).map((text) => '$page: $text'));

      await tester.pumpWidget(const NinhoApp(initialTheme: NinhoTheme.light));
      await tester.pumpAndSettle();
      check('Entrada');
      await tester.tap(find.text('Explorar demonstração'));
      await tester.pumpAndSettle();
      for (final tab in tabs) {
        await tester.tap(find.text(tab).last);
        await tester.pumpAndSettle();
        check(tab);
      }
      await tester.tap(find.byTooltip('Conta e ajustes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Família e conta'));
      await tester.pumpAndSettle();
      check('Família');

      // A new account without a family, then a family without records.
      await tester.pumpWidget(home(Store()));
      await tester.pumpAndSettle();
      check('Início');
      final empty = Store(demo: true);
      for (final resource in resources) {
        empty.data[resource] = [];
      }
      await tester.pumpWidget(home(empty));
      await tester.pumpAndSettle();
      for (final tab in tabs) {
        await tester.tap(find.text(tab).last);
        await tester.pumpAndSettle();
        check('$tab vazio');
      }
      expect(found, isEmpty);
    });
  }
}
