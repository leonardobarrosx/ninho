import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum NinhoTheme { system, light, dark }

const themeLabels = {
  NinhoTheme.system: 'Automático',
  NinhoTheme.light: 'Claro',
  NinhoTheme.dark: 'Escuro',
};

/// Figures of equal width, so amounts line up in lists, cards and bars, and
/// so do the numbers of a chart axis.
const tabularFigures = [FontFeature.tabularFigures()];

// Text colors keep WCAG AA contrast on their backgrounds, including ink on
// the brand orange. Accents are for icons, bars and lines, not body text.
// Icons on the mint tint use mintIcon, which keeps 3:1 there.
@immutable
class Palette extends ThemeExtension<Palette> {
  final Color background, surface, surfaceAlt, border, ink, muted;
  final Color brand, onBrand, brandText, brandTint, danger;
  final Color mint, sky, indigo, sunny;
  final Color mintTint, skyTint, indigoTint, sunnyTint, mintIcon;
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
    required this.mintIcon,
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
    mintIcon: Color(0xff247f59),
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
    mintIcon: Color(0xff8fdfbd),
  );

  static Palette of(BuildContext context) =>
      Theme.of(context).extension<Palette>() ?? light;

  List<Color> get accents => [brand, mint, sky, indigo, sunny];

  /// Expense category colors as (accent, tint, icon on the tint), from the
  /// largest category. Mint is left out because it marks money coming in.
  /// The brand orange is too faint on its tint for an icon, so its icons use
  /// the brand text color. Smaller categories share the neutral last one.
  List<(Color, Color, Color)> get categories => [
    (brand, brandTint, brandText),
    (sky, skyTint, sky),
    (indigo, indigoTint, indigo),
    (sunny, sunnyTint, sunny),
    (muted, surfaceAlt, muted),
  ];

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
      mintIcon: c(mintIcon, other.mintIcon),
    );
  }
}

ThemeData buildTheme(Palette p, Brightness brightness) {
  // Button, chip and snack bar text styles replace the default style instead
  // of adding to it, so they name the font too.
  const font = 'Nunito';
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
    fontFamily: font,
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
        textStyle: const TextStyle(
          fontFamily: font,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        side: BorderSide(color: p.border, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontFamily: font,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.brandText,
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontFamily: font,
          fontWeight: FontWeight.w600,
        ),
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
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        foregroundColor: p.ink,
        selectedForegroundColor: p.ink,
        selectedBackgroundColor: p.brandTint,
        side: BorderSide(color: p.border),
        textStyle: const TextStyle(
          fontFamily: font,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.surface,
      selectedColor: p.brandTint,
      side: BorderSide(color: p.border),
      shape: const StadiumBorder(),
      labelStyle: TextStyle(
        fontFamily: font,
        color: p.ink,
        fontWeight: FontWeight.w600,
      ),
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
      contentTextStyle: TextStyle(fontFamily: font, color: p.background),
      actionTextColor: p.brandTint,
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

/// The Ninho mark, proposal A ("Abraço"): a nest that embraces the egg, in
/// cream on an orange disc. It is drawn in code from the designer's vectors in
/// branding/, so it stays sharp at any size and needs no image assets.
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

  // The egg and the two arms of the nest, copied from
  // branding/ninho-A-simbolo-color.svg (a 256 × 256 box).
  static final _mark = [
    'M128 27C101 27 79 71 79 105C79 134 99 149 128 149C157 149 177 134 177 105C177 71 155 27 128 27Z',
    'M68 76C34 89 17 113 17 145C17 192 58 222 117 224C138 225 155 223 174 218C171 190 151 177 116 166C83 156 59 144 48 123C45 117 50 113 54 119C60 128 65 133 73 137C64 120 61 98 68 76Z',
    'M187 76C220 90 239 113 239 145C239 174 219 201 184 215C181 190 167 174 146 163C171 155 189 135 190 111C191 98 189 87 187 76Z',
  ].fold(Path(), (all, data) => all..addPath(_svgPath(data), Offset.zero));

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 256);
    canvas.drawCircle(
      const Offset(128, 128),
      128,
      Paint()..color = Palette.light.brand,
    );
    // The same placement as the app icon (branding/app-icon.svg).
    canvas.translate(26, 26);
    canvas.scale(.8);
    canvas.drawPath(_mark, Paint()..color = const Color(0xfffff6ea));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Reads the absolute moveto, curveto and closepath commands of the logo paths.
Path _svgPath(String data) {
  final path = Path();
  final tokens = RegExp(
    r'[A-Za-z]|-?\d+(?:\.\d+)?',
  ).allMatches(data).map((m) => m[0]!).toList();
  var i = 0;
  double next() => double.parse(tokens[i++]);
  var command = 'M';
  while (i < tokens.length) {
    if (RegExp('[A-Za-z]').hasMatch(tokens[i])) command = tokens[i++];
    switch (command) {
      case 'M':
        path.moveTo(next(), next());
      case 'C':
        path.cubicTo(next(), next(), next(), next(), next(), next());
      case 'Z':
        path.close();
        command = ''; // closepath takes no numbers
      default:
        throw FormatException('Unsupported path command', command);
    }
  }
  return path;
}
