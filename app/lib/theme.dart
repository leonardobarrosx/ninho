import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum NinhoTheme { system, light, dark }

const themeLabels = {
  NinhoTheme.system: 'Automático',
  NinhoTheme.light: 'Claro',
  NinhoTheme.dark: 'Escuro',
};

// Text colors keep WCAG AA contrast on their backgrounds, including ink on
// the brand orange. Accents are for icons, bars and lines, not body text.
@immutable
class Palette extends ThemeExtension<Palette> {
  final Color background, surface, surfaceAlt, border, ink, muted;
  final Color brand, onBrand, brandText, brandTint, danger;
  final Color mint, sky, indigo, sunny;
  final Color mintTint, skyTint, indigoTint, sunnyTint;
  const Palette({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.ink,
    required this.muted,
    required this.brand,
    required this.onBrand,
    required this.brandText,
    required this.brandTint,
    required this.danger,
    required this.mint,
    required this.sky,
    required this.indigo,
    required this.sunny,
    required this.mintTint,
    required this.skyTint,
    required this.indigoTint,
    required this.sunnyTint,
  });

  static const light = Palette(
    background: Color(0xfffff2ea),
    surface: Color(0xfffffdfb),
    surfaceAlt: Color(0xffffe7db),
    border: Color(0xfff7d9cb),
    ink: Color(0xff3a3248),
    muted: Color(0xff6b6178),
    brand: Color(0xffff8a5c),
    onBrand: Color(0xff3a3248),
    brandText: Color(0xffc2410c),
    brandTint: Color(0xffffdccb),
    danger: Color(0xffb3261e),
    mint: Color(0xff2f9a6e),
    sky: Color(0xff5b8fe6),
    indigo: Color(0xff7a7fe0),
    sunny: Color(0xffb8820c),
    mintTint: Color(0xffd2f2e3),
    skyTint: Color(0xffdce7fd),
    indigoTint: Color(0xffe4e1fb),
    sunnyTint: Color(0xffffedbf),
  );

  static const dark = Palette(
    background: Color(0xff221e2d),
    surface: Color(0xff2d2839),
    surfaceAlt: Color(0xff3a3448),
    border: Color(0xff463f56),
    ink: Color(0xfff7f0ea),
    muted: Color(0xffc2b9cc),
    brand: Color(0xffffa07e),
    onBrand: Color(0xff221e2d),
    brandText: Color(0xffffb396),
    brandTint: Color(0xff4a3230),
    danger: Color(0xffff9e9e),
    mint: Color(0xff8fdfbd),
    sky: Color(0xffa3c2f8),
    indigo: Color(0xffbab5f5),
    sunny: Color(0xfff6d486),
    mintTint: Color(0xff233b35),
    skyTint: Color(0xff283450),
    indigoTint: Color(0xff332e55),
    sunnyTint: Color(0xff3f3727),
  );

  static Palette of(BuildContext context) =>
      Theme.of(context).extension<Palette>() ?? light;

  List<Color> get accents => [brand, mint, sky, indigo, sunny];

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(Palette? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return Palette(
      background: c(background, other.background),
      surface: c(surface, other.surface),
      surfaceAlt: c(surfaceAlt, other.surfaceAlt),
      border: c(border, other.border),
      ink: c(ink, other.ink),
      muted: c(muted, other.muted),
      brand: c(brand, other.brand),
      onBrand: c(onBrand, other.onBrand),
      brandText: c(brandText, other.brandText),
      brandTint: c(brandTint, other.brandTint),
      danger: c(danger, other.danger),
      mint: c(mint, other.mint),
      sky: c(sky, other.sky),
      indigo: c(indigo, other.indigo),
      sunny: c(sunny, other.sunny),
      mintTint: c(mintTint, other.mintTint),
      skyTint: c(skyTint, other.skyTint),
      indigoTint: c(indigoTint, other.indigoTint),
      sunnyTint: c(sunnyTint, other.sunnyTint),
    );
  }
}

ThemeData buildTheme(Palette p, Brightness brightness) {
  final scheme =
      ColorScheme.fromSeed(seedColor: p.brand, brightness: brightness).copyWith(
        primary: p.brand,
        onPrimary: p.onBrand,
        primaryContainer: p.brandTint,
        onPrimaryContainer: p.ink,
        secondary: p.indigo,
        secondaryContainer: p.indigoTint,
        onSecondaryContainer: p.ink,
        tertiary: p.mint,
        tertiaryContainer: p.mintTint,
        onTertiaryContainer: p.ink,
        surface: p.surface,
        onSurface: p.ink,
        onSurfaceVariant: p.muted,
        surfaceContainerHighest: p.surfaceAlt,
        outline: p.border,
        outlineVariant: p.border,
        error: p.danger,
      );
  OutlineInputBorder field(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: color, width: width),
      );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.background,
    fontFamily: 'Roboto',
    extensions: [p],
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      foregroundColor: p.ink,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: p.surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: p.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      border: field(p.border),
      enabledBorder: field(p.border),
      focusedBorder: field(p.brand, 2),
      labelStyle: TextStyle(color: p.muted),
      contentPadding: const EdgeInsets.all(16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.brand,
        foregroundColor: p.onBrand,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        side: BorderSide(color: p.border, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.brandText,
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      indicatorColor: p.brandTint,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.ink),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.surface,
      selectedColor: p.brandTint,
      side: BorderSide(color: p.border),
      shape: const StadiumBorder(),
      labelStyle: TextStyle(color: p.ink, fontWeight: FontWeight.w600),
      checkmarkColor: p.ink,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.ink,
      contentTextStyle: TextStyle(color: p.background),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.brand,
      linearTrackColor: p.surfaceAlt,
    ),
    listTileTheme: ListTileThemeData(
      textColor: p.ink,
      iconColor: p.muted,
      selectedColor: p.ink,
      selectedTileColor: p.brandTint,
    ),
    dividerTheme: DividerThemeData(color: p.border),
  );
}

const _themeKey = 'ninho.theme';

Future<NinhoTheme> savedTheme() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_themeKey);
    return NinhoTheme.values.asNameMap()[name] ?? NinhoTheme.system;
  } catch (_) {
    return NinhoTheme.system;
  }
}

Future<void> saveTheme(NinhoTheme theme) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, theme.name);
  } catch (_) {
    // The theme still applies for this session without local storage.
  }
}

class ThemeButton extends StatelessWidget {
  final NinhoTheme value;
  final ValueChanged<NinhoTheme> onChanged;
  const ThemeButton({super.key, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => PopupMenuButton<NinhoTheme>(
    tooltip: 'Tema',
    icon: const Icon(Icons.palette_outlined, size: 21),
    onSelected: onChanged,
    itemBuilder: (_) => [
      for (final t in NinhoTheme.values)
        CheckedPopupMenuItem(
          value: t,
          checked: t == value,
          child: Text(themeLabels[t]!),
        ),
    ],
  );
}

/// The Ninho mark: a smiling egg in an orange nest, drawn in code so it stays
/// sharp at any size and needs no image assets.
class NinhoLogo extends StatelessWidget {
  final double size;
  const NinhoLogo({super.key, this.size = 40});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Ninho',
    child: SizedBox.square(
      dimension: size,
      child: const CustomPaint(painter: _LogoPainter()),
    ),
  );
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100);
    const navy = Color(0xff3a3248);
    final fill = Paint();
    canvas.drawCircle(
      const Offset(50, 50),
      50,
      fill..color = Palette.light.brand,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(50, 44), width: 42, height: 52),
      fill..color = const Color(0xfffff6ea),
    );
    for (final x in [37.0, 63.0]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, 47), width: 8, height: 5),
        fill..color = const Color(0xffffb3a1),
      );
    }
    for (final x in [43.0, 57.0]) {
      canvas.drawCircle(Offset(x, 40), 2.8, fill..color = navy);
    }
    final line = Paint()
      ..color = navy
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(45, 46)
        ..quadraticBezierTo(50, 51, 55, 46),
      line,
    );
    canvas.drawPath(
      Path()
        ..moveTo(15, 55)
        ..quadraticBezierTo(50, 67, 85, 55)
        ..quadraticBezierTo(81, 85, 50, 85)
        ..quadraticBezierTo(19, 85, 15, 55)
        ..close(),
      fill..color = navy,
    );
    line
      ..color = const Color(0xff5e5470)
      ..strokeWidth = 3;
    canvas.drawPath(
      Path()
        ..moveTo(25, 66)
        ..quadraticBezierTo(50, 75, 75, 66)
        ..moveTo(32, 76)
        ..quadraticBezierTo(50, 82, 68, 76),
      line,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
