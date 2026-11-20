import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'data.dart';
import 'domain.dart';
import 'forms.dart';
import 'theme.dart';
import 'widgets.dart';

/// A layette item takes up to five product options.
const maxOptions = 5;

/// Creates an option of [goal] from a store link, filled with what the
/// store's page says, and returns the message for the person. A page that
/// cannot be read still gives an option with the link, priced by hand.
Future<String> addOptionFromLink(
  Store s,
  Json goal,
  String url, {
  String title = '',
}) async {
  Json found = const {};
  String? problem;
  try {
    found = await s.preview(url);
  } catch (e) {
    problem = cleanError(e);
  }
  final name = (found['title'] as String? ?? '').trim();
  await s.save('goal_options', {
    'goal_id': goal['id'],
    'title': title.trim().isNotEmpty
        ? title.trim()
        : name.isNotEmpty
        ? name
        : goal['title'],
    'url': url,
    'image_url': found['image_url'] ?? '',
    'description': found['description'] ?? '',
    'store': found['store'] ?? Uri.parse(url).host.replaceFirst('www.', ''),
    'price_cents': found['price_cents'],
    'list_price_cents': found['list_price_cents'],
    'notes': '',
  }, reload: false);
  if (problem != null) return 'Opção salva com o link. $problem';
  if (found['price_cents'] == null) {
    return 'Opção salva. A página não mostrou o preço: edite para preencher.';
  }
  return 'Opção salva com foto e preço da loja.';
}

/// Opens a store's page in the browser.
Future<void> openLink(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  var opened = false;
  try {
    opened = await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
  } catch (_) {
    // Reported below, like a page that did not open.
  }
  if (!opened) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Não foi possível abrir a página.')),
    );
  }
}

/// A product photo from the store, or a soft tile while there is none. The
/// title beside it already names the product, so screen readers skip it.
class ProductImage extends StatelessWidget {
  final String url;
  final double size;
  // Names the kind of product while there is no photo.
  final String category;
  const ProductImage(this.url, {super.key, this.size = 72, this.category = ''});
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tile = ColoredBox(
      color: p.brandTint,
      child: Center(
        child: Icon(
          categoryIcon(category),
          color: p.brandText,
          size: size * .42,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(size < 60 ? 12 : 18),
      child: SizedBox.square(
        dimension: size,
        child: url.isEmpty
            ? tile
            : ColoredBox(
                color: Colors.white,
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  excludeFromSemantics: true,
                  cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                      .round(),
                  // Stores rarely allow other sites to read their images, so
                  // the web app shows them as plain <img> elements.
                  webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                  errorBuilder: (_, _, _) => tile,
                ),
              ),
      ),
    );
  }
}

IconData categoryIcon(String category) {
  final c = category.toLowerCase();
  bool has(List<String> words) => words.any(c.contains);
  if (has(['quarto', 'berço', 'sono', 'móve'])) return Icons.crib_rounded;
  if (has(['passeio', 'carrinho', 'carro', 'transporte'])) {
    return Icons.child_friendly_rounded;
  }
  if (has(['banho', 'higiene'])) return Icons.bathtub_rounded;
  if (has(['aliment', 'mamada', 'amament'])) return Icons.local_drink_rounded;
  if (has(['saúde', 'farmácia', 'remédio'])) {
    return Icons.medical_services_rounded;
  }
  if (has(['brinquedo', 'brincar'])) return Icons.toys_rounded;
  return Icons.checkroom_rounded;
}

/// What the layette costs with the options chosen, beside what it would
/// cost with the cheapest or the priciest option of each item.
class LayetteTotalsPanel extends StatelessWidget {
  final LayetteTotals totals;
  final int items;
  const LayetteTotalsPanel(this.totals, {super.key, required this.items});
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget side(String label, int value, String note, Color color) => Expanded(
      child: MergeSemantics(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: p.ink,
                ),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  money(value),
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: p.ink,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(note, style: TextStyle(fontSize: 12, color: p.ink)),
            ],
          ),
        ),
      ),
    );
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enxoval com as opções escolhidas',
                  style: TextStyle(color: p.muted, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    money(totals.chosen),
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.8,
                      color: p.ink,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                ),
                Text(
                  '$items ${items == 1 ? 'item' : 'itens'}${totals.compared == 0 ? '' : ' · ${totals.compared} com opções para comparar'}',
                  style: TextStyle(color: p.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          if (totals.compared > 0) ...[
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                side(
                  'Só as mais baratas',
                  totals.cheapest,
                  totals.chosen > totals.cheapest
                      ? 'Economia de ${money(totals.chosen - totals.cheapest)}'
                      : 'Já é o menor valor',
                  p.mintTint,
                ),
                const SizedBox(width: 12),
                side(
                  'Só as mais caras',
                  totals.priciest,
                  totals.priciest > totals.chosen
                      ? '${money(totals.priciest - totals.chosen)} a mais'
                      : 'Já é o maior valor',
                  p.sunnyTint,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A short line about a recent price change: green when it dropped.
class PriceAlertTag extends StatelessWidget {
  final PriceAlert alert;
  const PriceAlertTag(this.alert, {super.key});
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final dropped = alert.delta < 0;
    final days = DateTime.now().difference(alert.at).inDays;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: dropped ? p.mintTint : p.sunnyTint,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            dropped
                ? Icons.trending_down_rounded
                : alert.delta > 0
                ? Icons.trending_up_rounded
                : Icons.sell_outlined,
            size: 16,
            color: dropped ? p.mintIcon : p.sunnyIcon,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '${alert.text} · ${days == 0
                  ? 'hoje'
                  : days == 1
                  ? 'ontem'
                  : 'há $days dias'}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: p.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A price with the store's list price struck through beside it.
class PriceLine extends StatelessWidget {
  final Json option;
  final double size;
  const PriceLine(this.option, {super.key, this.size = 22});
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final price = maybe(option, 'price_cents');
    final list = maybe(option, 'list_price_cents');
    final off = discountPercent(option);
    if (price == null) {
      return Text(
        'Sem preço',
        style: TextStyle(color: p.muted, fontWeight: FontWeight.w600),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          money(price),
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w800,
            letterSpacing: -.4,
            color: p.ink,
            fontFeatures: tabularFigures,
          ),
        ),
        if (off != null) ...[
          Text(
            money(list!),
            semanticsLabel: 'antes ${money(list)}',
            style: TextStyle(
              color: p.muted,
              decoration: TextDecoration.lineThrough,
              fontFeatures: tabularFigures,
            ),
          ),
          Tag('-$off%', color: p.mintTint),
        ],
      ],
    );
  }
}

/// One layette item with its options: the main one sets the budget, the
/// others are there to compare. Prices are checked once a day.
class LayetteItemPage extends StatefulWidget {
  final Store store;
  final String goalId;
  final void Function(Json goal) onEdit;
  const LayetteItemPage({
    super.key,
    required this.store,
    required this.goalId,
    required this.onEdit,
  });
  @override
  State<LayetteItemPage> createState() => _LayetteItemPageState();
}

class _LayetteItemPageState extends State<LayetteItemPage> {
  bool saving = false;
  Store get s => widget.store;
  Palette get p => Palette.of(context);
  Json? get goal =>
      s.rows('goals').where((g) => g['id'] == widget.goalId).firstOrNull;

  /// Runs a change and says how it went. An action that returns text says
  /// that instead of [done].
  Future<void> perform(
    Future<Object?> Function() action, {
    String done = 'Atualizado.',
  }) async {
    if (saving || !mounted) return;
    setState(() => saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await action();
      messenger.showSnackBar(
        SnackBar(content: Text(result is String ? result : done)),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(cleanError(e), style: TextStyle(color: p.background)),
          backgroundColor: p.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> addOption(Json g) async {
    final result = await editForm(
      context,
      'Nova opção',
      const [
        FieldSpec('url', 'Link do produto', type: 'url'),
        FieldSpec('title', 'Nome (opcional)', optional: true),
      ],
      help:
          'Cole o link da loja. O Ninho busca foto, descrição e preço, e confere o preço todo dia.',
    );
    if (result == null) return;
    await perform(() async {
      final message = await addOptionFromLink(
        s,
        g,
        result['url'] as String,
        title: result['title'] as String,
      );
      await s.refresh();
      return message;
    });
  }

  Future<void> editOption(Json o) async {
    final result = await editForm(
      context,
      'Editar opção',
      const [
        FieldSpec('title', 'Nome'),
        FieldSpec('url', 'Link do produto', type: 'url', optional: true),
        FieldSpec('price_cents', 'Preço (R\$)', type: 'money', optional: true),
        FieldSpec(
          'list_price_cents',
          'Preço sem desconto (R\$)',
          type: 'money',
          optional: true,
        ),
        FieldSpec('store', 'Loja', optional: true, max: 80),
        FieldSpec(
          'description',
          'Descrição',
          type: 'notes',
          optional: true,
          max: 600,
        ),
        FieldSpec('notes', 'Observações', type: 'notes', optional: true),
      ],
      initial: o,
      help: 'O preço do link é conferido todo dia e substitui o digitado.',
    );
    if (result == null) return;
    await perform(
      () => s.save('goal_options', result, id: o['id'] as String),
      done: 'Opção atualizada.',
    );
  }

  /// Reads the store's page again now, for a price that looks out of date.
  Future<void> reread(Json o) => perform(() async {
    final found = await s.preview(o['url'] as String);
    await s.save('goal_options', {
      if (found['price_cents'] != null) ...{
        'price_cents': found['price_cents'],
        'list_price_cents': found['list_price_cents'],
      },
      if ((o['image_url'] as String? ?? '').isEmpty &&
          found['image_url'] != null)
        'image_url': found['image_url'],
      if ((o['description'] as String? ?? '').isEmpty &&
          found['description'] != null)
        'description': found['description'],
    }, id: o['id'] as String);
    return found['price_cents'] == null
        ? 'A página não mostrou o preço agora.'
        : 'Preço conferido: ${money(found['price_cents'] as int)}.';
  });

  Future<void> removeOption(Json o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir opção?'),
        content: Text(
          'Excluir “${o['title']}” e o histórico de preços dela? Se for a principal, a mais barata das outras assume.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await perform(
        () => s.remove('goal_options', o['id'] as String),
        done: 'Opção excluída.',
      );
    }
  }

  Future<void> choose(Json g, Json o) => perform(
    () => s.save('goals', {'chosen_option_id': o['id']}, id: g['id'] as String),
    done: '“${o['title']}” agora é a principal.',
  );

  void history(Json o) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => PriceHistory(
      option: o,
      prices:
          s
              .rows('goal_option_prices')
              .where((h) => h['option_id'] == o['id'])
              .toList()
            ..sort(
              (a, b) => (a['recorded_at'] as String).compareTo(
                b['recorded_at'] as String,
              ),
            ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: s,
    builder: (context, _) {
      final g = goal;
      if (g == null) {
        // The item was deleted, here or by someone else in the family.
        return Scaffold(
          appBar: AppBar(),
          body: const Center(child: Text('Este item não existe mais.')),
        );
      }
      final options = optionsOf(g, s.rows('goal_options'));
      final wide = MediaQuery.sizeOf(context).width >= 760;
      return Scaffold(
        appBar: AppBar(
          actions: [
            IconButton(
              tooltip: 'Editar item',
              onPressed: saving ? null : () => widget.onEdit(g),
              icon: const Icon(Icons.edit_outlined),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(wide ? 32 : 18, 12, wide ? 32 : 18, 48),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header(g, options),
                  const SizedBox(height: 20),
                  if (comparison(g, options) case final panel?) ...[
                    panel,
                    const SizedBox(height: 20),
                  ],
                  SectionTitle(
                    'Opções',
                    caption: options.isEmpty
                        ? null
                        : '${options.length} de $maxOptions. A principal define o orçamento do item.',
                  ),
                  if (options.isEmpty)
                    EmptyState(
                      'Qual produto vocês estão\u00a0olhando?',
                      'Cole o link da loja e compare até cinco opções.',
                      onAdd: saving ? null : () => addOption(g),
                    )
                  else ...[
                    for (final o in options)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: optionCard(g, o, wide: wide),
                      ),
                    if (options.length < maxOptions)
                      OutlinedButton.icon(
                        onPressed: saving ? null : () => addOption(g),
                        icon: const Icon(Icons.add_link_rounded),
                        label: Text(
                          options.length == 1
                              ? 'Adicionar outra opção para comparar'
                              : 'Adicionar opção',
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget header(Json g, List<Json> options) {
    final quantity = number(g, 'quantity');
    final category = g['category'] as String? ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Tag(
              priorityLabels[g['priority']] ?? 'Item',
              color: priorityColor(p, g['priority']),
            ),
            if (category.isNotEmpty) Tag(category, color: p.surfaceAlt),
          ],
        ),
        const SizedBox(height: 12),
        Semantics(
          header: true,
          child: Text(
            g['title'] as String,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -.6,
              color: p.ink,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${number(g, 'acquired')} de $quantity adquiridos · orçamento ${money(number(g, 'target_cents'))}${quantity > 1 ? ' para $quantity unidades' : ''}',
          style: TextStyle(color: p.muted),
        ),
      ],
    );
  }

  /// Cheapest against priciest, and what the main option costs beside them.
  Widget? comparison(Json g, List<Json> options) {
    final priced = options.where((o) => o['price_cents'] != null).toList()
      ..sort(
        (a, b) => number(a, 'price_cents').compareTo(number(b, 'price_cents')),
      );
    if (priced.length < 2) return null;
    final cheap = priced.first, dear = priced.last;
    final quantity = number(g, 'quantity');
    final chosen = priced
        .where((o) => o['id'] == g['chosen_option_id'])
        .firstOrNull;
    final extra = chosen == null
        ? 0
        : (number(chosen, 'price_cents') - number(cheap, 'price_cents')) *
              quantity;
    Widget side(String label, Json o, Color color) => Expanded(
      child: MergeSemantics(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontWeight: FontWeight.w700, color: p.ink),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  money(number(o, 'price_cents') * quantity),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: p.ink,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${o['title']}${(o['store'] as String? ?? '').isEmpty ? '' : ' · ${o['store']}'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: p.ink),
              ),
            ],
          ),
        ),
      ),
    );
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            'Mais barata e mais\u00a0cara',
            caption:
                'Diferença de ${money((number(dear, 'price_cents') - number(cheap, 'price_cents')) * quantity)}${quantity > 1 ? ' nas $quantity unidades' : ''}.',
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              side('Mais barata', cheap, p.mintTint),
              const SizedBox(width: 12),
              side('Mais cara', dear, p.sunnyTint),
            ],
          ),
          if (extra > 0) ...[
            const SizedBox(height: 14),
            Text(
              'A principal custa ${money(extra)} a mais que a mais barata.',
              style: TextStyle(color: p.muted),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: saving ? null : () => choose(g, cheap),
              icon: const Icon(Icons.savings_outlined, size: 18),
              label: const Text('Escolher a mais barata'),
            ),
          ],
        ],
      ),
    );
  }

  Widget optionCard(Json g, Json o, {required bool wide}) {
    final main = o['id'] == g['chosen_option_id'];
    final alert = priceAlert(o, DateTime.now());
    final url = o['url'] as String? ?? '';
    final store = o['store'] as String? ?? '';
    final description = o['description'] as String? ?? '';
    final checked = DateTime.tryParse(o['checked_at'] as String? ?? '');
    final name = o['title'] as String;
    final buttons = Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        if (!main)
          OutlinedButton.icon(
            onPressed: saving ? null : () => choose(g, o),
            icon: const Icon(Icons.star_outline_rounded, size: 18),
            label: Text(
              'Tornar principal',
              semanticsLabel: 'Tornar principal: $name',
            ),
          ),
        if (url.isNotEmpty)
          TextButton.icon(
            onPressed: () => openLink(context, url),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text('Ver na loja', semanticsLabel: 'Ver na loja: $name'),
          ),
        TextButton.icon(
          onPressed: () => history(o),
          icon: const Icon(Icons.show_chart_rounded, size: 18),
          label: Text('Histórico', semanticsLabel: 'Histórico de $name'),
        ),
      ],
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (main) ...[
              Tag('Principal', color: p.brandTint),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                store,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: p.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Opções de ${o['title']}',
              enabled: !saving,
              onSelected: (v) {
                switch (v) {
                  case 'edit':
                    editOption(o);
                  case 'reread':
                    reread(o);
                  default:
                    removeOption(o);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Editar')),
                if (url.isNotEmpty)
                  const PopupMenuItem(
                    value: 'reread',
                    child: Text('Conferir preço agora'),
                  ),
                const PopupMenuItem(value: 'delete', child: Text('Excluir')),
              ],
            ),
          ],
        ),
        Text(
          o['title'] as String,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: p.ink,
            height: 1.3,
          ),
        ),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: p.muted, fontSize: 13, height: 1.4),
          ),
        ],
        const SizedBox(height: 10),
        PriceLine(o),
        if (alert != null) ...[const SizedBox(height: 8), PriceAlertTag(alert)],
        const SizedBox(height: 6),
        Text(
          o['check_failed'] == true
              ? 'Não deu para conferir a página no último dia.'
              : checked == null
              ? url.isEmpty
                    ? 'Sem link: o preço não é conferido.'
                    : 'O preço será conferido amanhã.'
              : 'Conferido em ${dayText(checked.toLocal())}',
          style: TextStyle(fontSize: 12, color: p.muted),
        ),
        if (wide) ...[const SizedBox(height: 10), buttons],
      ],
    );
    return AnimatedContainer(
      duration: motion(context, 240),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: main ? p.brand : Colors.transparent,
          width: 2,
        ),
      ),
      child: Panel(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProductImage(
                  o['image_url'] as String? ?? '',
                  size: wide ? 120 : 76,
                  category: g['category'] as String? ?? '',
                ),
                const SizedBox(width: 16),
                Expanded(child: details),
              ],
            ),
            if (!wide) ...[const SizedBox(height: 12), buttons],
          ],
        ),
      ),
    );
  }
}

Color priorityColor(Palette p, Object? priority) => switch (priority) {
  'comfort' => p.skyTint,
  'optional' => p.indigoTint,
  _ => p.brandTint,
};

/// How the price of one option changed over time.
class PriceHistory extends StatelessWidget {
  final Json option;
  final List<Json> prices;
  const PriceHistory({super.key, required this.option, required this.prices});
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final whole = NumberFormat('#,##0', 'pt_BR');
    String when(Json h) =>
        dayText(DateTime.parse(h['recorded_at'] as String).toLocal());
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionTitle(
                'Histórico de\u00a0preço',
                caption: option['title'] as String,
              ),
              if (prices.length >= 2) ...[
                SizedBox(
                  height: 170,
                  width: double.infinity,
                  child: Semantics(
                    label:
                        'Evolução do preço: ${prices.map((h) => '${when(h)}: ${money(number(h, 'price_cents'))}').join(', ')}',
                    child: CustomPaint(
                      painter: LinePainter(
                        prices,
                        'price_cents',
                        100,
                        time: 'recorded_at',
                        format: (v) => whole.format(v),
                        line: p.brand,
                        grid: p.border,
                        label: TextStyle(
                          fontFamily: DefaultTextStyle.of(
                            context,
                          ).style.fontFamily,
                          fontSize: 11,
                          color: p.muted,
                          fontFeatures: tabularFigures,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (prices.isEmpty)
                Text(
                  'Ainda sem preços registrados. Eles aparecem quando a loja mostra o preço ou você o preenche.',
                  style: TextStyle(color: p.muted),
                )
              else
                for (final (i, h) in prices.reversed.indexed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      money(number(h, 'price_cents')),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                    subtitle: Text(
                      [
                        when(h),
                        if (h['list_price_cents'] != null)
                          'sem desconto ${money(number(h, 'list_price_cents'))}',
                      ].join(' · '),
                    ),
                    trailing: i + 1 < prices.length
                        ? changeText(
                            p,
                            number(h, 'price_cents') -
                                number(
                                  prices.reversed.elementAt(i + 1),
                                  'price_cents',
                                ),
                          )
                        : null,
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? changeText(Palette p, int delta) => delta == 0
      ? null
      : Text(
          '${delta < 0 ? '−' : '+'}${money(delta.abs())}',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: delta < 0 ? p.mintIcon : p.sunnyIcon,
            fontFeatures: tabularFigures,
          ),
        );
}

/// Drags the layette items into the family's order. Pops the new order.
class ReorderDialog extends StatefulWidget {
  final List<Json> items;
  const ReorderDialog(this.items, {super.key});
  @override
  State<ReorderDialog> createState() => _ReorderDialogState();
}

class _ReorderDialogState extends State<ReorderDialog> {
  late final List<Json> items = [...widget.items];
  void move(int from, int to) => setState(() {
    final item = items.removeAt(from);
    items.insert(to, item);
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return AlertDialog(
      title: const Text('Organizar ordem'),
      content: SizedBox(
        width: 440,
        height: MediaQuery.sizeOf(context).height * .6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Arraste pelos pontinhos ou use as setas. O primeiro da lista aparece primeiro.',
              style: TextStyle(color: p.muted),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                itemCount: items.length,
                onReorder: (from, to) => move(from, to > from ? to - 1 : to),
                itemBuilder: (_, i) => ListTile(
                  key: ValueKey(items[i]['id']),
                  contentPadding: EdgeInsets.zero,
                  leading: ReorderableDragStartListener(
                    index: i,
                    child: const Icon(Icons.drag_indicator_rounded),
                  ),
                  title: Text(
                    items[i]['title'] as String,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Subir ${items[i]['title']}',
                        onPressed: i == 0 ? null : () => move(i, i - 1),
                        icon: const Icon(Icons.arrow_upward_rounded),
                      ),
                      IconButton(
                        tooltip: 'Descer ${items[i]['title']}',
                        onPressed: i == items.length - 1
                            ? null
                            : () => move(i, i + 1),
                        icon: const Icon(Icons.arrow_downward_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, items),
          child: const Text('Salvar ordem'),
        ),
      ],
    );
  }
}
