import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'domain.dart';
import 'theme.dart';

/// How long an animation lasts, or no time at all when the person turned
/// animations off in the system settings.
Duration motion(BuildContext context, int milliseconds) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

/// Shown over the app while a launch waits for the app open ad. It continues
/// the Android launch screen: the same background and a 144 dp logo in the
/// middle, which then breathes while the ad flow decides.
class LaunchCover extends StatelessWidget {
  const LaunchCover({super.key});
  @override
  Widget build(BuildContext context) => AbsorbPointer(
    child: ColoredBox(
      color: Palette.of(context).background,
      child: Stack(
        // It fills the screen, so no tap reaches the app behind it.
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          const Center(child: Breathing(child: NinhoLogo(size: 144))),
          Center(
            child: Transform.translate(
              offset: const Offset(0, 124),
              child: const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Grows and shrinks its child a little, slowly, like breathing. Still when
/// animations are off.
class Breathing extends StatefulWidget {
  final Widget child;
  const Breathing({super.key, required this.child});
  @override
  State<Breathing> createState() => _BreathingState();
}

class _BreathingState extends State<Breathing>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (motion(context, 1) == Duration.zero) {
      controller.stop();
    } else if (!controller.isAnimating) {
      controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
    scale: Tween(
      begin: 1.0,
      end: 1.05,
    ).animate(CurvedAnimation(parent: controller, curve: Curves.easeInOut)),
    child: widget.child,
  );
}

/// Cross-fades between whole screens, such as sign-in and the home screen.
/// Each screen needs its own key.
class ScreenSwitch extends StatelessWidget {
  final Widget child;
  const ScreenSwitch({super.key, required this.child});
  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: motion(context, 400),
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    child: child,
  );
}

/// Cross-fades pages with a slight zoom when the tab changes, close to the
/// Material "fade through". Each page needs its own key.
class PageSwitch extends StatelessWidget {
  final Widget child;
  const PageSwitch({super.key, required this.child});
  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: motion(context, 300),
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween(begin: .97, end: 1.0).animate(animation),
        child: child,
      ),
    ),
    layoutBuilder: (current, previous) => Stack(
      alignment: Alignment.topCenter,
      children: [...previous, ?current],
    ),
    child: child,
  );
}

/// A bar that grows to its value when it appears and slides to a new value
/// when it changes, for the category chart and the goals.
class GrowingBar extends StatelessWidget {
  final double value;
  final Color? color;
  final String? semanticsLabel, semanticsValue;
  const GrowingBar(
    this.value, {
    super.key,
    this.color,
    this.semanticsLabel,
    this.semanticsValue,
  });
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: value),
    duration: motion(context, 700),
    curve: Curves.easeOutCubic,
    builder: (context, shown, _) => LinearProgressIndicator(
      value: shown,
      minHeight: 8,
      borderRadius: BorderRadius.circular(99),
      backgroundColor: Palette.of(context).surfaceAlt,
      color: color,
      semanticsLabel: semanticsLabel,
      semanticsValue: semanticsValue,
    ),
  );
}

/// Opens a page of the site, such as the privacy policy, in the browser.
class PageLink extends StatelessWidget {
  final String label;
  final Uri page;
  const PageLink(this.label, this.page, {super.key});
  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: () async {
      final messenger = ScaffoldMessenger.of(context);
      var opened = false;
      try {
        opened = await launchUrl(page, webOnlyWindowName: '_blank');
      } catch (_) {
        // Reported below, like a page that did not open.
      }
      if (!opened) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir a página.')),
        );
      }
    },
    icon: const Icon(Icons.open_in_new, size: 18),
    label: Text(label),
  );
}

/// The eye button at the end of a password field.
class PasswordToggle extends StatelessWidget {
  final bool hidden;
  final VoidCallback onPressed;
  const PasswordToggle({
    super.key,
    required this.hidden,
    required this.onPressed,
  });
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: hidden ? 'Mostrar senha' : 'Ocultar senha',
    onPressed: onPressed,
    icon: Icon(
      hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
    ),
  );
}

/// A card that groups content. Screen readers go through its pieces one by
/// one, in reading order, instead of reading the whole card as one block. A
/// list row wrapped in `Semantics(container: true)` reads as one item, with
/// its buttons after it.
class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
  });
  @override
  Widget build(BuildContext context) => Card(
    semanticContainer: false,
    child: Padding(padding: padding, child: child),
  );
}

class Heading extends StatelessWidget {
  final String title, subtitle;
  final Widget? action;
  const Heading(this.title, this.subtitle, {super.key, this.action});
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: LayoutBuilder(
        builder: (context, b) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Semantics(
                    container: true,
                    header: true,
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: b.maxWidth < 600 ? 26 : 32,
                        fontWeight: FontWeight.w800,
                        color: p.ink,
                        letterSpacing: -.8,
                      ),
                    ),
                  ),
                ),
                if (action != null && b.maxWidth >= 600) action!,
              ],
            ),
            const SizedBox(height: 8),
            Text(subtitle, style: TextStyle(color: p.muted, height: 1.5)),
            if (action != null && b.maxWidth < 600)
              Padding(padding: const EdgeInsets.only(top: 16), child: action!),
          ],
        ),
      ),
    );
  }
}

/// A summary card. Without [color] it is a plain surface; with it, a colored
/// block whose text uses [onColor] (or the theme ink on light tints). Screen
/// readers read it as one item: label, value and note.
class Metric extends StatelessWidget {
  final String label, value, note;
  final IconData icon;
  final Color? color, onColor, accent;
  const Metric(
    this.label,
    this.value,
    this.note,
    this.icon, {
    super.key,
    this.color,
    this.onColor,
    this.accent,
  });
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final strong = onColor ?? p.ink;
    final soft = onColor ?? p.muted;
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: color ?? p.surface,
          borderRadius: BorderRadius.circular(24),
          border: color == null ? Border.all(color: p.border) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(color: soft, fontWeight: FontWeight.w600),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: strong.withValues(alpha: .08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: onColor ?? accent ?? p.brand,
                    size: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // A new value, as when the month changes, rises into place.
            AnimatedSwitcher(
              duration: motion(context, 280),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, .3),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.centerLeft,
                children: [...previous, ?current],
              ),
              child: FittedBox(
                key: ValueKey(value),
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.7,
                    color: strong,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(note, style: TextStyle(color: soft, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// A chip in a group where only one can be on, such as a filter. On the web,
/// a chip reports a checked state and would read as a checkbox; in a
/// mutually exclusive group, screen readers announce it as one option of
/// the group instead (a radio button).
class OptionChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;
  const OptionChip(
    this.label, {
    super.key,
    required this.selected,
    required this.onSelected,
  });
  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(
      inMutuallyExclusiveGroup: true,
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
      ),
    ),
  );
}

/// A small colored label, such as a priority. It reads as plain text, not as
/// a control.
class Tag extends StatelessWidget {
  final String text;
  final Color color;
  const Tag(this.text, {super.key, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Palette.of(context).ink,
      ),
    ),
  );
}

class MetricGrid extends StatelessWidget {
  final List<Widget> children;
  const MetricGrid({super.key, required this.children});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, b) {
      final count = b.maxWidth > 1000
          ? 4
          : b.maxWidth > 320
          ? 2
          : 1;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: children
            .map(
              (w) => SizedBox(
                width: (b.maxWidth - 16 * (count - 1)) / count,
                child: w,
              ),
            )
            .toList(),
      );
    },
  );
}

class EmptyState extends StatelessWidget {
  final String title, text;
  final VoidCallback? onAdd;
  const EmptyState(this.title, this.text, {super.key, this.onAdd});
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Panel(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: p.brandTint,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.add_rounded, size: 30, color: p.brandText),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: p.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted),
              ),
              if (onAdd != null)
                Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: FilledButton(
                    onPressed: onAdd,
                    child: const Text('Adicionar'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? caption;
  const SectionTitle(this.title, {super.key, this.caption});
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            container: true,
            header: true,
            child: Text(
              title,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: p.ink,
              ),
            ),
          ),
          if (caption != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                caption!,
                style: TextStyle(color: p.muted, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}

class GrowthChart extends StatelessWidget {
  final List<Json> rows;
  final String field, title, unit;
  final int divisor;
  const GrowthChart({
    super.key,
    required this.rows,
    required this.field,
    required this.title,
    required this.unit,
    required this.divisor,
  });

  /// Whether [rows] have the two measures of [field] that a line needs.
  static bool plots(List<Json> rows, String field) =>
      rows.where((r) => r[field] != null).length >= 2;

  @override
  Widget build(BuildContext context) {
    if (!plots(rows, field)) return GrowthHint(title);
    final p = Palette.of(context);
    final sorted = rows.where((r) => r[field] != null).toList()
      ..sort(
        (a, b) =>
            (a['measured_at'] as String).compareTo(b['measured_at'] as String),
      );
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            title,
            caption:
                '${decimal(number(sorted.last, field) / divisor)} $unit em ${dateText(sorted.last['measured_at'] as String)}',
          ),
          SizedBox(
            height: 160,
            width: double.infinity,
            child: Semantics(
              label:
                  'Evolução de $title: ${sorted.map((r) => '${dateText(r['measured_at'] as String)}: ${decimal(number(r, field) / divisor)} $unit').join(', ')}',
              child: CustomPaint(
                painter: LinePainter(
                  sorted,
                  field,
                  divisor,
                  line: p.brand,
                  grid: p.border,
                  label: TextStyle(
                    // A painter does not inherit the app font.
                    fontFamily: DefaultTextStyle.of(context).style.fontFamily,
                    fontSize: 11,
                    color: p.muted,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                dateText(sorted.first['measured_at'] as String),
                style: TextStyle(fontSize: 12, color: p.muted),
              ),
              Text(
                dateText(sorted.last['measured_at'] as String),
                style: TextStyle(fontSize: 12, color: p.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Stands in for growth charts until there are two measures to draw.
class GrowthHint extends StatelessWidget {
  final String title;
  const GrowthHint(this.title, {super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(title),
          Text(
            'Registre ao menos duas medidas para ver a evolução.',
            style: TextStyle(color: Palette.of(context).muted),
          ),
        ],
      ),
    ),
  );
}

class LinePainter extends CustomPainter {
  final List<Json> rows;
  final String field;
  final int divisor;
  final Color line, grid;
  final TextStyle label;
  LinePainter(
    this.rows,
    this.field,
    this.divisor, {
    required this.line,
    required this.grid,
    required this.label,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final values = rows.map((e) => number(e, field) / divisor).toList();
    final observedMin = values.reduce((a, b) => a < b ? a : b);
    final observedMax = values.reduce((a, b) => a > b ? a : b);
    final min = observedMin == observedMax ? observedMin - 0.5 : observedMin;
    final max = observedMin == observedMax ? observedMax + 0.5 : observedMax;
    final delta = max - min;
    final path = Path();
    final times = rows
        .map(
          (e) => DateTime.parse(
            e['measured_at'] as String,
          ).millisecondsSinceEpoch.toDouble(),
        )
        .toList();
    final duration = times.last - times.first;
    for (var i = 0; i < 3; i++) {
      final y = 20 + (size.height - 40) * i / 2;
      canvas.drawLine(
        Offset(42, y),
        Offset(size.width, y),
        Paint()..color = grid,
      );
      final text = TextPainter(
        text: TextSpan(
          text: decimal(max - delta * i / 2, digits: 1),
          style: label,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, Offset(0, y - 7));
    }
    for (var i = 0; i < values.length; i++) {
      final x =
          44 +
          (size.width - 52) *
              (duration == 0
                  ? i / (values.length - 1)
                  : (times[i] - times.first) / duration);
      final y =
          size.height - 20 - (values[i] - min) / delta * (size.height - 40);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 5, Paint()..color = line);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant LinePainter oldDelegate) => true;
}
