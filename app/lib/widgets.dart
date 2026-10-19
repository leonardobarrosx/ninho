import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'domain.dart';
import 'theme.dart';

/// Shown over the app while a launch waits for the app open ad. Like the
/// Android launch screen, it is the page background, here with the logo.
class LaunchCover extends StatelessWidget {
  const LaunchCover({super.key});
  @override
  Widget build(BuildContext context) => AbsorbPointer(
    child: ColoredBox(
      color: Palette.of(context).background,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NinhoLogo(size: 96),
            SizedBox(height: 28),
            SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ),
      ),
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
            FittedBox(
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
            const SizedBox(height: 8),
            Text(note, style: TextStyle(color: soft, fontSize: 12)),
          ],
        ),
      ),
    );
  }
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
