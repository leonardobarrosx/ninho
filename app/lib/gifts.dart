import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'data.dart';
import 'domain.dart';
import 'forms.dart';
import 'layette.dart';
import 'theme.dart';
import 'widgets.dart';

/// How the items show on the family's page.
const giftTemplates = {
  'cards': ('Cartões', 'Fotos grandes, em grade', Icons.grid_view_rounded),
  'polaroid': ('Polaroid', 'Fotos de varal, com fita', Icons.photo_outlined),
  'lista': ('Lista', 'Linhas com foto pequena', Icons.view_list_rounded),
  'minimal': ('Minimalista', 'Só texto, bem elegante', Icons.notes_rounded),
};

/// The page palettes, as on the site (site/lista.css).
const giftPalettes = {
  'pessego': ('Pêssego', Color(0xffff8a5c)),
  'menta': ('Menta', Color(0xff4cc496)),
  'ceu': ('Céu', Color(0xff6b9cf2)),
  'lavanda': ('Lavanda', Color(0xff9b8cf0)),
  'areia': ('Areia', Color(0xffc99a5b)),
};

const pixKeyTypes = {
  'email': 'E-mail',
  'phone': 'Celular',
  'cpf': 'CPF',
  'cnpj': 'CNPJ',
  'random': 'Chave aleatória',
};

/// A Pix key as the BR Code carries it, or null when it does not fit [type].
String? pixKey(String type, String raw) {
  final text = raw.trim();
  final digits = text.replaceAll(RegExp(r'\D'), '');
  switch (type) {
    case 'cpf':
      return digits.length == 11 ? digits : null;
    case 'cnpj':
      return digits.length == 14 ? digits : null;
    case 'phone':
      final national = digits.startsWith('55') && digits.length >= 12
          ? digits.substring(2)
          : digits;
      return national.length == 10 || national.length == 11
          ? '+55$national'
          : null;
    case 'email':
      return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text) &&
              text.length <= 77
          ? text.toLowerCase()
          : null;
    default:
      final key = text.toLowerCase();
      return RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          ).hasMatch(key)
          ? key
          : null;
  }
}

/// The kind of a saved key, to edit it again.
String pixKeyType(String key) => key.contains('@')
    ? 'email'
    : key.startsWith('+')
    ? 'phone'
    : RegExp(r'^\d{11}$').hasMatch(key)
    ? 'cpf'
    : RegExp(r'^\d{14}$').hasMatch(key)
    ? 'cnpj'
    : key.isEmpty
    ? 'email'
    : 'random';

/// The part of the link after /lista/: lowercase letters, digits and hyphens.
String slugify(String text) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  final out = StringBuffer();
  for (final c in text.toLowerCase().split('')) {
    final i = from.indexOf(c);
    out.write(i >= 0 ? to[i] : c);
  }
  final slug = out
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final cut = slug.length > 40 ? slug.substring(0, 40) : slug;
  return cut.replaceAll(RegExp(r'-+$'), '');
}

bool validSlug(String slug) =>
    RegExp(r'^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$').hasMatch(slug) &&
    !slug.contains('--');

/// Joins names the Brazilian way: "Maria", "Maria e João", "Ana, Bia e Caio".
String joinNames(List<String> names) => names.length <= 1
    ? names.join()
    : '${names.sublist(0, names.length - 1).join(', ')} e ${names.last}';

/// The gift list: friends and family open the family's link, choose items or
/// part of them and pay by Pix. Ninho handles no money; here the family sets
/// up the page and confirms each Pix that arrives.
class GiftListPage extends StatefulWidget {
  final Store store;
  const GiftListPage({super.key, required this.store});
  @override
  State<GiftListPage> createState() => _GiftListPageState();
}

class _GiftListPageState extends State<GiftListPage> {
  bool saving = false;
  Store get s => widget.store;
  Palette get p => Palette.of(context);
  Json? get list => s.rows('gift_lists').firstOrNull;
  Uri? link(Json l) => sitePage('lista/${l['slug']}');

  Future<void> perform(
    Future<Object?> Function() action, {
    String done = 'Alterações salvas.',
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
      var text = cleanError(e);
      if (text.startsWith('Registro já existe')) {
        text = 'Esse endereço já está em uso. Escolha outro.';
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(text, style: TextStyle(color: p.background)),
          backgroundColor: p.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  /// Suggestions for the title, from the babies' names.
  List<String> get titles {
    final babies = s
        .rows('babies')
        .map((b) => (b['name'] as String).trim())
        .where((n) => n.isNotEmpty && !n.toLowerCase().contains('bebê'))
        .toList();
    return [
      if (babies.isNotEmpty) 'Enxoval de ${joinNames(babies)}',
      'Enxoval do papai e da mamãe',
      'Enxoval do nosso bebê',
    ];
  }

  Future<void> editPage(Json? l) async {
    final result = await editForm(
      context,
      l == null ? 'Criar a lista de presentes' : 'Texto e endereço',
      const [
        FieldSpec('title', 'Título da página', max: 80),
        FieldSpec('slug', 'Endereço: ninho…/lista/', max: 40),
        FieldSpec(
          'message',
          'Recado para quem visitar',
          type: 'notes',
          optional: true,
          max: 600,
        ),
      ],
      initial:
          l ??
          {
            'title': titles.first,
            'slug': slugify('${titles.first} ${s.familyName}'),
            'message':
                'Estamos montando o enxoval com muito carinho. Qualquer ajuda, inteira ou um pedacinho, já deixa tudo mais leve. Obrigado!',
          },
      help:
          'Ex.: "Enxoval do papai Pedro e da mamãe Ana" ou "Enxoval de Maria e João". Sugestões: ${titles.join(' · ')}.',
    );
    if (result == null) return;
    final slug = slugify(result['slug'] as String);
    if (!validSlug(slug)) {
      return perform(
        () => throw Exception(
          'Use de 3 a 40 letras, números ou hífens no endereço.',
        ),
      );
    }
    await perform(
      () => s.save('gift_lists', {
        ...result,
        'slug': slug,
      }, id: l?['id'] as String?),
      done: l == null ? 'Lista criada. Falta o Pix.' : 'Alterações salvas.',
    );
  }

  Future<void> editPix(Json l) async {
    final key = l['pix_key'] as String? ?? '';
    final result = await editForm(
      context,
      'Pix de quem\u00a0recebe',
      const [
        FieldSpec('type', 'Tipo de chave', options: pixKeyTypes),
        FieldSpec('pix_key', 'Chave Pix', max: 77),
        FieldSpec('pix_name', 'Nome de quem recebe', max: 25),
        FieldSpec('pix_city', 'Cidade', max: 15),
      ],
      initial: {...l, 'type': pixKeyType(key)},
      help:
          'O dinheiro vai direto para essa chave. Nome e cidade aparecem no app do banco de quem paga; use como estão no seu banco.',
    );
    if (result == null) return;
    final normalized = pixKey(
      result.remove('type') as String,
      result['pix_key'] as String,
    );
    if (normalized == null) {
      return perform(
        () => throw Exception('Confira a chave Pix para o tipo escolhido.'),
      );
    }
    await perform(
      () => s.save('gift_lists', {
        ...result,
        'pix_key': normalized,
      }, id: l['id'] as String),
      done: 'Pix salvo.',
    );
  }

  Future<void> set(Json l, String key, Object value) => perform(
    () => s.save('gift_lists', {key: value}, id: l['id'] as String),
    done: key == 'published'
        ? (value == true
              ? 'Lista publicada. Já dá para compartilhar.'
              : 'Lista fora do ar.')
        : 'Alterações salvas.',
  );

  Future<void> decide(Json c, String status) => perform(
    () => s.rpc('decide_gift', {'p_id': c['id'], 'p_status': status}),
    done: switch (status) {
      'confirmed' => 'Pix confirmado. O valor entrou na reserva dos itens.',
      'declined' => 'Marcado como não recebido.',
      _ => 'Confirmação desfeita.',
    },
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: s,
    builder: (context, _) {
      final l = list;
      final wide = MediaQuery.sizeOf(context).width >= 760;
      return Scaffold(
        appBar: AppBar(title: const Text('Lista de presentes')),
        body: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(wide ? 32 : 18, 8, wide ? 32 : 18, 48),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: !s.plus
                    ? [plusOffer()]
                    : l == null
                    ? [intro(), const SizedBox(height: 20), start()]
                    : [
                        intro(),
                        const SizedBox(height: 20),
                        share(l),
                        const SizedBox(height: 20),
                        received(l),
                        const SizedBox(height: 20),
                        look(l),
                        const SizedBox(height: 20),
                        pixPanel(l),
                        const SizedBox(height: 20),
                        items(),
                      ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget intro() => Text(
    'Amigos e família abrem o link, escolhem um item ou uma parte dele e pagam por Pix, direto para vocês. O Ninho não recebe dinheiro: aqui vocês confirmam o que chegou.',
    style: TextStyle(color: p.muted, height: 1.5),
  );

  Widget plusOffer() => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Tag('Ninho Plus', color: p.brandTint),
        const SizedBox(height: 14),
        Text(
          'Lista de presentes com\u00a0Pix',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: p.ink,
          ),
        ),
        const SizedBox(height: 10),
        for (final line in const [
          'Um link com o nome de vocês para mandar no grupo da família',
          'Quatro modelos de página e cinco cores',
          'Quem visita escolhe o item inteiro ou uma parte e paga por Pix',
          'Vocês confirmam cada Pix e o valor entra na reserva do item',
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_rounded, size: 20, color: p.mintIcon),
                const SizedBox(width: 10),
                Expanded(child: Text(line)),
              ],
            ),
          ),
        const SizedBox(height: 10),
        Text(
          'R\$ 10, pago uma vez. Vale para a conta toda, sem mensalidade.',
          style: TextStyle(fontWeight: FontWeight.w700, color: p.ink),
        ),
        const SizedBox(height: 6),
        Text(
          kIsWeb
              ? 'Pague por Pix ou cartão, pelo Mercado Pago. O Plus é liberado assim que o pagamento é aprovado.'
              : 'A compra pelo app Android chega em breve.',
          style: TextStyle(color: p.muted),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (kIsWeb)
              FilledButton.icon(
                onPressed: saving ? null : buyPlus,
                icon: const Icon(Icons.lock_open_rounded, size: 18),
                label: const Text('Comprar o Plus'),
              ),
            if (sitePage('lista/exemplo') case final example?)
              OutlinedButton.icon(
                onPressed: () => openLink(context, example.toString()),
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('Ver uma lista de exemplo'),
              ),
          ],
        ),
      ],
    ),
  );

  /// Goes to Mercado Pago's checkout in this tab. It comes back to
  /// /app/?plus=retorno, where the home screen checks the payment.
  Future<void> buyPlus() => perform(() async {
    final page = await s.plusCheckout();
    if (!await launchUrl(page, webOnlyWindowName: '_self')) {
      throw Exception('Não foi possível abrir o Mercado Pago.');
    }
    return 'Abrindo o Mercado Pago…';
  });

  Widget start() => EmptyState(
    'Monte a página de\u00a0vocês',
    'Escolham o título, o endereço e o recado. Depois, o Pix e o visual.',
    onAdd: saving ? null : () => editPage(null),
  );

  Widget share(Json l) {
    final url = link(l)?.toString() ?? '/lista/${l['slug']}';
    final published = l['published'] == true;
    final ready = (l['pix_key'] as String? ?? '').isNotEmpty;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  l['title'] as String,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: p.ink,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Editar texto e endereço',
                onPressed: saving ? null : () => editPage(l),
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            url,
            style: TextStyle(color: p.brandText, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: published,
            onChanged: saving || (!ready && !published)
                ? null
                : (v) => set(l, 'published', v),
            title: Text(published ? 'Publicada' : 'Fora do ar'),
            subtitle: Text(
              !ready
                  ? 'Cadastre o Pix para publicar.'
                  : published
                  ? 'Quem tiver o link pode abrir.'
                  : 'Ninguém abre o link até vocês publicarem.',
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await Clipboard.setData(
                    ClipboardData(
                      text:
                          '${l['title']}\n${(l['message'] as String? ?? '').isEmpty ? '' : '${l['message']}\n'}$url',
                    ),
                  );
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Convite copiado. Cole no WhatsApp ou onde quiser.',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copiar convite'),
              ),
              if (link(l) case final page?)
                OutlinedButton.icon(
                  onPressed: () => openLink(
                    context,
                    '$page?modelo=${l['template']}&cor=${l['palette']}',
                  ),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Ver a página'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget received(Json l) {
    final gifts = [...s.rows('gift_contributions')]
      ..sort(
        (a, b) => (b['created_at'] as String? ?? '').compareTo(
          a['created_at'] as String? ?? '',
        ),
      );
    int sum(String status) => gifts
        .where((c) => c['status'] == status)
        .fold(0, (t, c) => t + number(c, 'amount_cents'));
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            'Presentes\u00a0recebidos',
            caption: gifts.isEmpty
                ? 'Quando alguém presentear, aparece aqui para vocês conferirem no banco.'
                : '${money(sum('confirmed'))} confirmados · ${money(sum('pending'))} para conferir',
          ),
          for (final c in gifts) gift(c),
        ],
      ),
    );
  }

  Widget gift(Json c) {
    final items = s
        .rows('gift_contribution_items')
        .where((i) => i['contribution_id'] == c['id'])
        .toList();
    final free =
        number(c, 'amount_cents') -
        items.fold(0, (t, i) => t + number(i, 'amount_cents'));
    final status = c['status'] as String;
    final message = c['message'] as String? ?? '';
    final when = DateTime.tryParse(c['created_at'] as String? ?? '');
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: status == 'pending' ? p.sunnyTint : p.surfaceAlt,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        c['name'] as String,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: p.ink,
                        ),
                      ),
                    ),
                    Text(
                      money(number(c, 'amount_cents')),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: p.ink,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    for (final i in items)
                      '${i['title']} (${money(number(i, 'amount_cents'))})',
                    if (free > 0) 'Valor livre (${money(free)})',
                  ].join(' · '),
                  style: TextStyle(color: p.ink, fontSize: 13),
                ),
                if (message.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '“$message”',
                    style: TextStyle(color: p.ink, fontStyle: FontStyle.italic),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  '${switch (status) {
                    'confirmed' => 'Confirmado',
                    'declined' => 'Não chegou',
                    _ => 'Confira no banco',
                  }}${when == null ? '' : ' · ${dayText(when.toLocal())}'}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: p.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: status == 'pending'
                ? [
                    FilledButton.icon(
                      onPressed: saving ? null : () => decide(c, 'confirmed'),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: Text(
                        'Confirmar',
                        semanticsLabel: 'Confirmar o Pix de ${c['name']}',
                      ),
                    ),
                    TextButton(
                      onPressed: saving ? null : () => decide(c, 'declined'),
                      child: Text(
                        'Não chegou',
                        semanticsLabel: 'O Pix de ${c['name']} não chegou',
                      ),
                    ),
                  ]
                : [
                    TextButton(
                      onPressed: saving ? null : () => decide(c, 'pending'),
                      child: Text(
                        'Desfazer',
                        semanticsLabel: 'Desfazer a decisão sobre ${c['name']}',
                      ),
                    ),
                  ],
          ),
        ],
      ),
    );
  }

  Widget look(Json l) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('Visual da\u00a0página'),
        LayoutBuilder(
          builder: (context, b) {
            final cols = b.maxWidth > 600 ? 4 : 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final e in giftTemplates.entries)
                  SizedBox(
                    width: (b.maxWidth - 10 * (cols - 1)) / cols,
                    child: templateTile(l, e.key, e.value),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        Text('Cor', style: TextStyle(color: p.muted)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            for (final e in giftPalettes.entries)
              Semantics(
                button: true,
                selected: l['palette'] == e.key,
                label: 'Cor ${e.value.$1}',
                child: Tooltip(
                  message: e.value.$1,
                  child: InkResponse(
                    onTap: saving ? null : () => set(l, 'palette', e.key),
                    radius: 26,
                    child: AnimatedContainer(
                      duration: motion(context, 200),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: e.value.$2,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: l['palette'] == e.key
                              ? p.ink
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: l['palette'] == e.key
                          ? const Icon(Icons.check, color: Colors.white)
                          : null,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: l['show_prices'] == true,
          onChanged: saving ? null : (v) => set(l, 'show_prices', v),
          title: const Text('Mostrar os preços'),
          subtitle: const Text('Sem preço, a página mostra só quanto falta.'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: l['allow_partial'] == true,
          onChanged: saving ? null : (v) => set(l, 'allow_partial', v),
          title: const Text('Aceitar partes de um item'),
          subtitle: const Text(
            'Quem visita pode dar metade, um quarto ou outro valor.',
          ),
        ),
      ],
    ),
  );

  Widget templateTile(Json l, String key, (String, String, IconData) t) {
    final on = l['template'] == key;
    return Semantics(
      button: true,
      selected: on,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: saving ? null : () => set(l, 'template', key),
        child: AnimatedContainer(
          duration: motion(context, 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: on ? p.brandTint : p.surfaceAlt.withValues(alpha: .5),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: on ? p.brand : p.border, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(t.$3, color: p.brandText),
              const SizedBox(height: 8),
              Text(
                t.$1,
                style: TextStyle(fontWeight: FontWeight.w800, color: p.ink),
              ),
              Text(t.$2, style: TextStyle(fontSize: 12, color: p.muted)),
            ],
          ),
        ),
      ),
    );
  }

  Widget pixPanel(Json l) {
    final key = l['pix_key'] as String? ?? '';
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            'Pix de quem\u00a0recebe',
            caption: key.isEmpty
                ? 'Sem o Pix, a página não pode ser publicada.'
                : '${pixKeyTypes[pixKeyType(key)]}: $key\n${l['pix_name']} · ${l['pix_city']}',
          ),
          OutlinedButton.icon(
            onPressed: saving ? null : () => editPix(l),
            icon: const Icon(Icons.pix_rounded, size: 18),
            label: Text(key.isEmpty ? 'Cadastrar o Pix' : 'Trocar o Pix'),
          ),
        ],
      ),
    );
  }

  Widget items() {
    final goals = inOrder(s.rows('goals'));
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(
            'Itens na\u00a0página',
            caption:
                'Aparecem os itens com orçamento que ainda faltam. Desmarque o que vocês preferem comprar.',
          ),
          for (final g in goals)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: g['gift'] != false,
              onChanged: saving
                  ? null
                  : (v) => perform(
                      () => s.save('goals', {
                        'gift': v == true,
                      }, id: g['id'] as String),
                      done: v == true
                          ? 'Item na página.'
                          : 'Item fora da página.',
                    ),
              title: Text(g['title'] as String),
              subtitle: Text(
                number(g, 'acquired') >= number(g, 'quantity')
                    ? 'Já adquirido'
                    : number(g, 'target_cents') == 0
                    ? 'Sem orçamento: não aparece'
                    : 'Falta ${money(remainingGoalBudget(g))}',
              ),
            ),
        ],
      ),
    );
  }
}

/// The budget of the units an item still needs, before gifts and savings.
int remainingGoalBudget(Json g) {
  final quantity = number(g, 'quantity');
  if (quantity <= 0) return 0;
  return number(g, 'target_cents') *
      (quantity - number(g, 'acquired')) ~/
      quantity;
}
