import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ninho/domain.dart';
import 'package:ninho/forms.dart';
import 'package:ninho/theme.dart';

const entry = [
  FieldSpec(
    'kind',
    'Tipo',
    options: {'income': 'Receita', 'expense': 'Despesa'},
    segmented: true,
  ),
  FieldSpec('title', 'Descrição'),
  FieldSpec('start_date', 'Data', type: 'date'),
  FieldSpec('end_date', 'Última data (opcional)', type: 'date', optional: true),
];

/// Opens a form from a button and collects what it returns.
Future<List<Json?>> openForm(
  WidgetTester tester, {
  List<FieldSpec> fields = entry,
  Json initial = const {},
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final results = <Json?>[];
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildTheme(Palette.light, Brightness.light),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async => results.add(
                await editForm(context, 'Lançamento', fields, initial: initial),
              ),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  testWidgets('dates show day first, save in ISO and can be cleared', (
    tester,
  ) async {
    final results = await openForm(
      tester,
      initial: {
        'kind': 'expense',
        'title': 'Aluguel',
        'start_date': '2026-10-17',
        'end_date': '2026-12-31',
      },
    );
    // A long form takes the whole phone screen.
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('17/10/2026'), findsOneWidget);
    expect(find.text('31/12/2026'), findsOneWidget);
    await tester.tap(find.byTooltip('Limpar data'));
    await tester.pump();
    expect(find.text('31/12/2026'), findsNothing);
    await tester.tap(find.text('Receita'));
    await tester.pump();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(results, [
      {
        'kind': 'income',
        'title': 'Aluguel',
        'start_date': '2026-10-17',
        'end_date': null,
      },
    ]);
  });

  testWidgets('a required date has to be picked', (tester) async {
    final results = await openForm(tester, initial: {'title': 'Aluguel'});
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Selecione uma data'), findsOneWidget);
    expect(results, isEmpty);
  });

  testWidgets('the back button asks before discarding changes', (tester) async {
    final results = await openForm(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Descrição'), 'Luz');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Descartar alterações?'), findsOneWidget);
    await tester.tap(find.text('Continuar editando'));
    await tester.pumpAndSettle();
    expect(find.text('Luz'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();
    expect(find.text('Luz'), findsNothing);
    expect(results, [null]);
  });

  testWidgets('the back button closes an untouched form at once', (
    tester,
  ) async {
    final results = await openForm(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Descartar alterações?'), findsNothing);
    expect(results, [null]);
  });

  testWidgets('cancelling discards without asking', (tester) async {
    final results = await openForm(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Descrição'), 'Luz');
    await tester.pump();
    await tester.tap(find.byTooltip('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Descartar alterações?'), findsNothing);
    expect(results, [null]);
  });

  testWidgets('a tap beside a short form keeps it open', (tester) async {
    final results = await openForm(
      tester,
      fields: const [FieldSpec('p_name', 'Nome da família')],
      size: const Size(1200, 800),
    );
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(results, isEmpty);
  });

  testWidgets('the keyboard moves to the next field', (tester) async {
    await openForm(
      tester,
      fields: const [
        FieldSpec('title', 'Descrição'),
        FieldSpec('amount', 'Valor', type: 'money'),
        FieldSpec('notes', 'Observações', type: 'notes', optional: true),
      ],
    );
    TextField field(String label) =>
        tester.widget<TextField>(find.widgetWithText(TextField, label));
    expect(field('Descrição').textInputAction, TextInputAction.next);
    expect(field('Valor').textInputAction, TextInputAction.done);
    expect(field('Observações').textInputAction, TextInputAction.newline);
    expect(field('Observações').keyboardType, TextInputType.multiline);
  });
}
