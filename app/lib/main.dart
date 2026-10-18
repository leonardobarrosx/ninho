import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'ads.dart';
import 'data.dart';
import 'screens.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (configured) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  }
  final theme = await savedTheme();
  runApp(NinhoApp(initialTheme: theme, ads: await AdMobAds.create()));
}

class NinhoApp extends StatefulWidget {
  final NinhoTheme initialTheme;
  final Ads ads;
  const NinhoApp({
    super.key,
    this.initialTheme = NinhoTheme.system,
    this.ads = const Ads(),
  });
  @override
  State<NinhoApp> createState() => _NinhoAppState();
}

class _NinhoAppState extends State<NinhoApp> {
  Store? store;
  StreamSubscription<AuthState>? subscription;
  bool recovery = false;
  // The launch waits behind the cover while the app open ad decides.
  late bool covering = widget.ads.coversLaunch;
  late NinhoTheme theme = widget.initialTheme;
  void setTheme(NinhoTheme value) {
    setState(() => theme = value);
    saveTheme(value);
  }

  @override
  void initState() {
    super.initState();
    widget.ads.start(blocked: () => recovery).whenComplete(() {
      if (mounted && covering) setState(() => covering = false);
    });
    if (configured) {
      if (Supabase.instance.client.auth.currentSession != null) {
        store = Store();
        store!.refresh();
      }
      subscription = Supabase.instance.client.auth.onAuthStateChange.listen((
        state,
      ) {
        if (!mounted) return;
        setState(() {
          if (state.event == AuthChangeEvent.passwordRecovery) {
            // Password recovery never waits for an ad, nor gets one.
            recovery = true;
            covering = false;
          }
          if (state.session == null) {
            store?.dispose();
            store = null;
          } else if (store == null || store!.demo) {
            store?.dispose();
            store = Store();
            store!.refresh();
          }
        });
      });
    }
  }

  @override
  void dispose() {
    subscription?.cancel();
    store?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ninho',
      debugShowCheckedModeBanner: false,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildTheme(Palette.light, Brightness.light),
      darkTheme: buildTheme(Palette.dark, Brightness.dark),
      themeMode: switch (theme) {
        NinhoTheme.system => ThemeMode.system,
        NinhoTheme.dark => ThemeMode.dark,
        _ => ThemeMode.light,
      },
      // The app builds under the cover, so it is ready when the ad closes.
      builder: (context, child) => Stack(
        children: [
          ExcludeSemantics(excluding: covering, child: child),
          if (covering) const Positioned.fill(child: LaunchCover()),
        ],
      ),
      home: recovery
          ? RecoveryScreen(onDone: () => setState(() => recovery = false))
          : store == null
          ? AuthScreen(
              theme: theme,
              onTheme: setTheme,
              onDemo: () {
                setState(() => store = Store(demo: true));
              },
            )
          : HomeScreen(
              key: ValueKey(store),
              store: store!,
              ads: widget.ads,
              theme: theme,
              onTheme: setTheme,
              onLogout: () async {
                if (store!.demo) {
                  setState(() {
                    store!.dispose();
                    store = null;
                  });
                } else {
                  await Supabase.instance.client.auth.signOut();
                }
              },
            ),
    );
  }
}

class AuthScreen extends StatefulWidget {
  final VoidCallback onDemo;
  final NinhoTheme theme;
  final ValueChanged<NinhoTheme> onTheme;

  /// Whether to offer sign-in, which needs a configured backend. Null follows
  /// the build configuration; tests pass true to see the form.
  final bool? signIn;
  const AuthScreen({
    super.key,
    required this.onDemo,
    required this.theme,
    required this.onTheme,
    this.signIn,
  });
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final email = TextEditingController(), password = TextEditingController();
  final key = GlobalKey<FormState>();
  bool signup = false, busy = false, hidden = true;
  String? message;
  // Whether [message] reports a failure, in red, rather than a next step.
  bool failed = false;
  bool get online => widget.signIn ?? configured;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  void say(String text, {bool failure = false}) => setState(() {
    message = text;
    failed = failure;
  });

  Future<void> submit({bool reset = false}) async {
    if (!online) return;
    if (reset) {
      if (!email.text.contains('@')) {
        say('Informe seu e-mail.', failure: true);
        return;
      }
    } else if (!key.currentState!.validate()) {
      return;
    }
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final auth = Supabase.instance.client.auth;
      if (reset) {
        await auth.resetPasswordForEmail(email.text.trim());
        if (mounted) {
          say(
            'Se houver uma conta, você receberá um e-mail para redefinir a senha.',
          );
        }
      } else if (signup) {
        await auth.signUp(email: email.text.trim(), password: password.text);
        // Lets the password manager offer to save the new account.
        TextInput.finishAutofillContext();
        if (mounted) {
          say(
            'Confira seu e-mail para confirmar o cadastro. Depois, entre com sua senha.',
          );
        }
      } else {
        await auth.signInWithPassword(
          email: email.text.trim(),
          password: password.text,
        );
        TextInput.finishAutofillContext();
      }
    } catch (e) {
      if (mounted) say(authError(e), failure: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const NinhoLogo(size: 64),
                  const Spacer(),
                  ThemeButton(value: widget.theme, onChanged: widget.onTheme),
                ],
              ),
              const SizedBox(height: 20),
              Semantics(
                header: true,
                child: Text(
                  'Ninho',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Palette.of(context).ink,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Mais clareza nas contas.\nMais espaço para viver essa fase.',
                style: TextStyle(fontSize: 23, height: 1.4),
              ),
              const SizedBox(height: 28),
              if (!online)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Explore a demonstração. O ambiente ainda precisa ser conectado para criar contas e salvar dados reais.',
                  ),
                ),
              if (online)
                // One autofill group, so the password manager fills and saves
                // the e-mail and the password together. Leaving for the
                // demonstration saves nothing.
                AutofillGroup(
                  onDisposeAction: AutofillContextAction.cancel,
                  child: Form(
                    key: key,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(
                            labelText: 'E-mail',
                          ),
                          validator: (v) => v != null && v.contains('@')
                              ? null
                              : 'Informe seu e-mail',
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: password,
                          obscureText: hidden,
                          textInputAction: TextInputAction.done,
                          autofillHints: [
                            signup
                                ? AutofillHints.newPassword
                                : AutofillHints.password,
                          ],
                          decoration: InputDecoration(
                            labelText: 'Senha',
                            suffixIcon: PasswordToggle(
                              hidden: hidden,
                              onPressed: () => setState(() => hidden = !hidden),
                            ),
                          ),
                          validator: (v) => v != null && v.length >= 8
                              ? null
                              : 'Use pelo menos 8 caracteres',
                          onFieldSubmitted: (_) {
                            if (!busy) submit();
                          },
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: busy ? null : submit,
                            child: Text(
                              busy
                                  ? 'Aguarde…'
                                  : signup
                                  ? 'Criar conta'
                                  : 'Entrar',
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => setState(() => signup = !signup),
                          child: Text(
                            signup ? 'Já tenho uma conta' : 'Criar minha conta',
                          ),
                        ),
                        TextButton(
                          onPressed: busy ? null : () => submit(reset: true),
                          child: const Text('Esqueci minha senha'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  // Read out as soon as it appears, like a failed sign-in.
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      message!,
                      style: failed
                          ? TextStyle(
                              color: Palette.of(context).danger,
                              fontWeight: FontWeight.w600,
                            )
                          : null,
                    ),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: busy ? null : widget.onDemo,
                  child: const Text('Explorar demonstração'),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Demonstração com dados fictícios. Alterações não são salvas.',
                style: TextStyle(
                  fontSize: 12,
                  color: Palette.of(context).muted,
                ),
              ),
              if (privacyPolicy case final page?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: PageLink('Política de privacidade', page),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class RecoveryScreen extends StatefulWidget {
  final VoidCallback onDone;
  const RecoveryScreen({super.key, required this.onDone});
  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  final password = TextEditingController();
  bool busy = false, hidden = true;
  String? error;
  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (password.text.length < 8) {
      setState(() => error = 'Use pelo menos 8 caracteres.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: password.text),
      );
      widget.onDone();
    } catch (e) {
      if (mounted) setState(() => error = authError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: const Text(
                  'Definir nova senha',
                  style: TextStyle(fontSize: 26),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: password,
                obscureText: hidden,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (!busy) save();
                },
                decoration: InputDecoration(
                  labelText: 'Nova senha (mínimo 8 caracteres)',
                  suffixIcon: PasswordToggle(
                    hidden: hidden,
                    onPressed: () => setState(() => hidden = !hidden),
                  ),
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Palette.of(context).danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: busy ? null : save,
                child: const Text('Salvar senha'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
