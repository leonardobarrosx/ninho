import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ninho/data.dart';
import 'package:ninho/main.dart';
import 'package:ninho/theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('Supabase Auth errors read in Portuguese', () {
    String message(String code) =>
        authError(AuthException('English text', code: code));
    expect(message('invalid_credentials'), 'E-mail ou senha incorretos.');
    expect(message('email_not_confirmed'), contains('Confirme seu e-mail'));
    expect(message('user_already_exists'), contains('Já existe uma conta'));
    expect(message('over_email_send_rate_limit'), contains('Aguarde'));
    expect(message('same_password'), 'Use uma senha diferente da atual.');
    expect(
      message('a_code_from_the_future'),
      'Não foi possível concluir. Tente novamente.',
    );
    for (final offline in [AuthRetryableFetchException(), Exception('x')]) {
      expect(authError(offline), 'Não foi possível conectar. Tente novamente.');
    }
  });

  testWidgets('the sign-in form fills, shows the password and reports errors', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: buildTheme(Palette.light, Brightness.light),
        home: AuthScreen(
          onDemo: () {},
          theme: NinhoTheme.light,
          onTheme: (_) {},
          signIn: true,
        ),
      ),
    );
    // The password manager fills and saves e-mail and password together.
    expect(find.byType(AutofillGroup), findsOneWidget);
    TextField field(String label) =>
        tester.widget<TextField>(find.widgetWithText(TextField, label));
    expect(field('E-mail').textInputAction, TextInputAction.next);
    expect(field('Senha').obscureText, isTrue);
    await tester.tap(find.byTooltip('Mostrar senha'));
    await tester.pump();
    expect(field('Senha').obscureText, isFalse);
    expect(find.byTooltip('Ocultar senha'), findsOneWidget);
    // A failure is red and read out as soon as it appears.
    await tester.tap(find.text('Esqueci minha senha'));
    await tester.pump();
    final failure = find.text('Informe seu e-mail.');
    expect(tester.widget<Text>(failure).style?.color, Palette.light.danger);
    expect(tester.getSemantics(failure), containsSemantics(isLiveRegion: true));
    semantics.dispose();
  });
}
