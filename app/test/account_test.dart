import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ninho/ads.dart';
import 'package:ninho/data.dart';
import 'package:ninho/main.dart';
import 'package:ninho/screens.dart';
import 'package:ninho/theme.dart';
import 'package:ninho/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the launch behind the cover until the test lets it go.
class CoverAds extends Ads {
  final done = Completer<void>();
  bool Function()? blocked;
  @override
  bool get coversLaunch => true;
  @override
  Future<void> start({required bool Function() blocked}) {
    this.blocked = blocked;
    return done.future;
  }
}

/// A demonstration store that behaves like a signed-in account.
class AccountStore extends Store {
  AccountStore({this.failure}) : super(demo: true);
  final Exception? failure;
  final passwords = <String>[];
  int get deletions => passwords.length;
  @override
  String? get email => 'ana@ninho.test';
  @override
  bool get canDeleteAccount => true;
  @override
  Future<void> deleteAccount(String password) async {
    passwords.add(password);
    if (failure != null) throw failure!;
  }
}

Future<void> openAccount(
  WidgetTester tester,
  Widget app, {
  bool demo = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
  if (demo) {
    await tester.tap(find.text('Explorar demonstração'));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('Família').last);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Excluir minha conta'));
  await tester.pumpAndSettle();
}

Widget home(Store store, NinhoTheme theme) => MaterialApp(
  locale: const Locale('pt', 'BR'),
  supportedLocales: const [Locale('pt', 'BR')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: theme == NinhoTheme.dark
      ? buildTheme(Palette.dark, Brightness.dark)
      : buildTheme(Palette.light, Brightness.light),
  home: HomeScreen(
    store: store,
    onLogout: () async {},
    theme: theme,
    onTheme: (_) {},
  ),
);

Finder button<T extends ButtonStyleButton>(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((w) => w is T),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the launch cover holds the app until the ad flow ends', (
    tester,
  ) async {
    final ads = CoverAds();
    await tester.pumpWidget(NinhoApp(ads: ads));
    await tester.pump();
    expect(find.byType(LaunchCover), findsOneWidget);
    expect(ads.blocked!(), isFalse);
    await tester.tap(find.text('Explorar demonstração'), warnIfMissed: false);
    await tester.pump();
    expect(find.text('Saldo previsto'), findsNothing, reason: 'taps wait');
    ads.done.complete();
    await tester.pumpAndSettle();
    expect(find.byType(LaunchCover), findsNothing);
    await tester.tap(find.text('Explorar demonstração'));
    await tester.pumpAndSettle();
    expect(find.text('Saldo previsto'), findsOneWidget);
  });

  for (final theme in [NinhoTheme.light, NinhoTheme.dark]) {
    testWidgets('the demonstration has no account to delete (${theme.name})', (
      tester,
    ) async {
      await openAccount(tester, NinhoApp(initialTheme: theme), demo: true);
      expect(find.text('Sua conta'), findsOneWidget);
      expect(find.textContaining('A demonstração não tem conta'), findsOne);
      final delete = tester.widget<OutlinedButton>(
        button<OutlinedButton>('Excluir minha conta'),
      );
      expect(delete.onPressed, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('deleting an account asks for the password (${theme.name})', (
      tester,
    ) async {
      final store = AccountStore();
      await openAccount(tester, home(store, theme));
      expect(find.textContaining('ana@ninho.test'), findsOneWidget);
      await tester.tap(button<OutlinedButton>('Excluir minha conta'));
      await tester.pumpAndSettle();
      expect(find.text('Excluir sua conta?'), findsOneWidget);
      FilledButton confirm() =>
          tester.widget<FilledButton>(button<FilledButton>('Excluir conta'));
      expect(confirm().onPressed, isNull);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.obscureText, isTrue);
      await tester.enterText(find.byType(TextField), 'senha-da-ana');
      await tester.pump();
      expect(confirm().onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.tap(button<FilledButton>('Excluir conta'));
      await tester.pumpAndSettle();
      expect(store.passwords, ['senha-da-ana']);
      expect(find.text('Conta excluída.'), findsOneWidget);
    });
  }

  testWidgets('cancelling keeps the account', (tester) async {
    final store = AccountStore();
    await openAccount(tester, home(store, NinhoTheme.light));
    await tester.tap(button<OutlinedButton>('Excluir minha conta'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'senha-da-ana');
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(store.deletions, 0);
  });

  testWidgets('a failed deletion says why and keeps the account', (
    tester,
  ) async {
    final store = AccountStore(failure: Exception('Senha incorreta.'));
    await openAccount(tester, home(store, NinhoTheme.dark));
    await tester.tap(button<OutlinedButton>('Excluir minha conta'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'senha-errada');
    await tester.pump();
    await tester.tap(button<FilledButton>('Excluir conta'));
    await tester.pumpAndSettle();
    expect(store.deletions, 1);
    expect(find.text('Senha incorreta.'), findsOneWidget);
    expect(find.text('Sua conta'), findsOneWidget);
  });
}
