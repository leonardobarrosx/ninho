import 'package:flutter/material.dart';
import 'domain.dart';

const ink = Color(0xff233c35),
    green = Color(0xff316b5b),
    muted = Color(0xff69796e);

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
    child: Padding(padding: padding, child: child),
  );
}

class Heading extends StatelessWidget {
  final String title, subtitle;
  final Widget? action;
  const Heading(this.title, this.subtitle, {super.key, this.action});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: LayoutBuilder(
      builder: (context, b) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: b.maxWidth < 600 ? 26 : 32,
                    fontWeight: FontWeight.w700,
                    color: ink,
                    letterSpacing: -.8,
                  ),
                ),
              ),
              if (action != null && b.maxWidth >= 600) action!,
            ],
          ),
          const SizedBox(height: 8),
          Text(subtitle, style: const TextStyle(color: muted, height: 1.5)),
          if (action != null && b.maxWidth < 600)
            Padding(padding: const EdgeInsets.only(top: 16), child: action!),
        ],
      ),
    ),
  );
}

class Metric extends StatelessWidget {
  final String label, value, note;
  final IconData icon;
  final bool accent;
  const Metric(
    this.label,
    this.value,
    this.note,
    this.icon, {
    super.key,
    this.accent = false,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: accent ? green : Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: accent ? green : const Color(0xffe4e9e2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: accent ? Colors.white70 : muted),
              ),
            ),
            Icon(icon, color: accent ? Colors.white70 : green, size: 21),
          ],
        ),
        const SizedBox(height: 16),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -.7,
              color: accent ? Colors.white : ink,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          note,
          style: TextStyle(
            color: accent ? Colors.white70 : muted,
            fontSize: 12,
          ),
        ),
      ],
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
  Widget build(BuildContext context) => Panel(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            const Icon(Icons.add_circle_outline, size: 36, color: green),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted),
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

class SectionTitle extends StatelessWidget {
  final String title;
  final String? caption;
  const SectionTitle(this.title, {super.key, this.caption});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
        if (caption != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              caption!,
              style: const TextStyle(color: muted, fontSize: 13),
            ),
          ),
      ],
    ),
  );
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
  @override
  Widget build(BuildContext context) {
    final sorted = rows.where((r) => r[field] != null).toList()
      ..sort(
        (a, b) =>
            (a['measured_at'] as String).compareTo(b['measured_at'] as String),
      );
    if (sorted.length < 2) {
      return Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionTitle(title),
            const Text(
              'Registre ao menos duas medidas para ver a evolução.',
              style: TextStyle(color: muted),
            ),
          ],
        ),
      );
    }
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
              child: CustomPaint(painter: LinePainter(sorted, field, divisor)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                dateText(sorted.first['measured_at'] as String),
                style: const TextStyle(fontSize: 12, color: muted),
              ),
              Text(
                dateText(sorted.last['measured_at'] as String),
                style: const TextStyle(fontSize: 12, color: muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class LinePainter extends CustomPainter {
  final List<Json> rows;
  final String field;
  final int divisor;
  LinePainter(this.rows, this.field, this.divisor);
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
        Paint()..color = const Color(0xffedf0ea),
      );
      final label = TextPainter(
        text: TextSpan(
          text: decimal(max - delta * i / 2, digits: 1),
          style: const TextStyle(fontSize: 11, color: muted),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(0, y - 7));
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
      canvas.drawCircle(Offset(x, y), 4, Paint()..color = green);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant LinePainter oldDelegate) => true;
}
