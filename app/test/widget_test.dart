import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ninho/main.dart';

void main() {
  testWidgets('demo enters dashboard and navigates at mobile width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const NinhoApp());
    await tester.tap(find.text('Explorar demonstração'));
    await tester.pumpAndSettle();
    expect(find.text('Saldo previsto'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Finanças').last);
    await tester.pumpAndSettle();
    expect(find.text('Finanças da família'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Bebê').last);
    await tester.pumpAndSettle();
    expect(find.text('Cada fase, registrada.'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
    expect(tester.takeException(), isNull);
  });
}
