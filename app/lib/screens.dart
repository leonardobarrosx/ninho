import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'ads.dart';
import 'data.dart';
import 'domain.dart';
import 'forms.dart';
import 'theme.dart';
import 'widgets.dart';

class HomeScreen extends StatefulWidget {
  final Store store;
  final Ads ads;
  final Future<void> Function() onLogout;
  final NinhoTheme theme;
  final ValueChanged<NinhoTheme> onTheme;
  const HomeScreen({
    super.key,
    required this.store,
    this.ads = const Ads(),
    required this.onLogout,
    required this.theme,
    required this.onTheme,
  });
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int page = 0;
  // The tab that Família goes back to.
  int lastTab = 0;
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  bool saving = false;
  String filter = 'all';
  String search = '';
  String? babyId;
  Store get s => widget.store;
  Palette get p => Palette.of(context);
  static const labels = [
    'Visão geral',
    'Finanças',
    'Enxoval',
    'Bebê',
    'Saúde',
    'Família',
  ];
  static const icons = [
    Icons.grid_view_rounded,
    Icons.account_balance_wallet_rounded,
    Icons.checkroom_rounded,
    Icons.child_care_rounded,
    Icons.favorite_rounded,
    Icons.people_alt_rounded,
  ];
  // Família is the last page. Phones open it from the account menu, so the
  // bottom bar keeps five tabs.
  static const familyPage = 5;
  @override
  void initState() {
    super.initState();
    s.addListener(changed);
  }

  @override
  void dispose() {
    s.removeListener(changed);
    super.dispose();
  }

  void changed() {
    if (mounted) setState(() {});
  }

  /// Runs a change and says how it went: [done] on success, with an [undo]
  /// button when the change can be reverted.
  Future<void> perform(
    Future<void> Function() action, {
    String done = 'Atualizado.',
    SnackBarAction? undo,
  }) async {
    // An undo tapped after leaving this screen has nothing left to change.
    if (saving || !mounted) return;
    setState(() => saving = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.error ?? done),
            action: s.error == null ? undo : null,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(cleanError(e), style: TextStyle(color: p.background)),
            backgroundColor: p.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> edit(
    String resource,
    String title,
    List<FieldSpec> fields, {
    Json? row,
    Json defaults = const {},
    String? help,
  }) async {
    final result = await editForm(
      context,
      title,
      fields,
      initial: row ?? defaults,
      help: help,
    );
    if (result != null) {
      await perform(
        () => s.save(resource, result, id: row?['id'] as String?),
        done: row == null ? 'Registro adicionado.' : 'Alterações salvas.',
      );
    }
  }

  /// How a record is named in messages and screen reader labels.
  String recordName(Json row) =>
      (row['title'] ?? row['name']) as String? ??
      (row['measured_at'] == null
          ? 'registro'
          : 'medida de ${dateText(row['measured_at'] as String)}');

  Future<void> remove(String resource, Json row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir registro?'),
        content: Text(
          'Excluir “${recordName(row)}”? Esta ação também pode remover os registros vinculados e alterar os totais.',
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
        () => s.remove(resource, row['id'] as String),
        done: 'Registro excluído.',
      );
    }
  }

  /// The ⋮ menu of a record. [undo] adds an item that reverts its last
  /// change, such as a payment.
  Widget actions(
    String resource,
    Json row,
    VoidCallback onEdit, {
    (String, VoidCallback)? undo,
  }) => PopupMenuButton<String>(
    tooltip: 'Opções de ${recordName(row)}',
    enabled: !saving,
    onSelected: (v) {
      switch (v) {
        case 'edit':
          onEdit();
        case 'undo':
          undo!.$2();
        default:
          remove(resource, row);
      }
    },
    itemBuilder: (_) => [
      const PopupMenuItem(value: 'edit', child: Text('Editar')),
      if (undo != null) PopupMenuItem(value: 'undo', child: Text(undo.$1)),
      const PopupMenuItem(value: 'delete', child: Text('Excluir')),
    ],
  );
  Widget add(String label, VoidCallback onTap) => FilledButton.icon(
    onPressed: saving ? null : onTap,
    icon: const Icon(Icons.add, size: 18),
    label: Text(label),
  );
  void go(int i) => setState(() {
    if (page != familyPage) lastTab = page;
    page = i;
    search = '';
    filter = 'all';
  });

  /// The back button: from Família to the tab it was opened from, from any
  /// other tab to Visão geral, and from there out of the app.
  void back() => go(page == familyPage ? lastTab : 0);

  /// Family and account, data refresh, theme and sign-out in one menu, so the
  /// header fits a narrow phone.
  Widget accountMenu() => PopupMenuButton<Object>(
    tooltip: 'Conta e ajustes',
    icon: const Icon(Icons.account_circle_outlined),
    onSelected: (v) {
      switch (v) {
        case NinhoTheme theme:
          widget.onTheme(theme);
        case 'family':
          go(familyPage);
        case 'refresh':
          s.refresh();
        case 'logout':
          perform(widget.onLogout);
      }
    },
    itemBuilder: (_) => [
      menuItem('family', Icons.people_alt_outlined, 'Família e conta'),
      menuItem(
        'refresh',
        Icons.refresh,
        'Atualizar dados',
        enabled: !s.loading && !saving,
      ),
      const PopupMenuDivider(),
      for (final theme in NinhoTheme.values)
        CheckedPopupMenuItem<Object>(
          value: theme,
          checked: theme == widget.theme,
          child: Text('Tema ${themeLabels[theme]!.toLowerCase()}'),
        ),
      const PopupMenuDivider(),
      menuItem(
        'logout',
        Icons.logout,
        s.demo ? 'Sair da demonstração' : 'Sair',
        enabled: !saving,
      ),
    ],
  );

  // Lined up with the checked theme items, which are list tiles too.
  PopupMenuItem<Object> menuItem(
    String value,
    IconData icon,
    String label, {
    bool enabled = true,
  }) => PopupMenuItem(
    value: value,
    enabled: enabled,
    child: ListTile(enabled: enabled, leading: Icon(icon), title: Text(label)),
  );
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1050;
    // On a phone, Família opens over the tabs, with a way back.
    final sub = !wide && page == familyPage;
    return PopScope(
      canPop: page == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) back();
      },
      child: Scaffold(
        bottomNavigationBar: wide || sub
            ? null
            : NavigationBar(
                selectedIndex: page,
                onDestinationSelected: go,
                height: 76,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                destinations: [
                  for (var i = 0; i < familyPage; i++)
                    NavigationDestination(
                      icon: Icon(icons[i], size: 22),
                      label: labels[i],
                    ),
                ],
              ),
        body: SafeArea(
          child: Row(
            children: [
              if (wide)
                Material(
                  color: p.surface,
                  shape: Border(right: BorderSide(color: p.border)),
                  child: SizedBox(
                    width: 210,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(22, 30, 20, 32),
                          child: Row(
                            children: [
                              const NinhoLogo(size: 38),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  'Ninho',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 27,
                                    fontWeight: FontWeight.w800,
                                    color: p.ink,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        for (var i = 0; i < labels.length; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 4,
                            ),
                            child: ListTile(
                              shape: const StadiumBorder(),
                              selected: i == page,
                              selectedTileColor: p.brandTint,
                              selectedColor: p.ink,
                              leading: Icon(icons[i], size: 21),
                              title: Text(
                                labels[i],
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              onTap: () => go(i),
                            ),
                          ),
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.all(22),
                          child: Text(
                            'Um passo de cada vez.\nTudo no seu tempo.',
                            style: TextStyle(
                              color: p.muted,
                              height: 1.6,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: Column(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: wide ? 32 : 18,
                        vertical: 16,
                      ),
                      child: Row(
                        children: [
                          if (sub)
                            IconButton(
                              onPressed: back,
                              tooltip: 'Voltar',
                              icon: const Icon(Icons.arrow_back),
                            )
                          else if (!wide)
                            const Padding(
                              padding: EdgeInsets.only(right: 10),
                              child: NinhoLogo(size: 30),
                            ),
                          Expanded(
                            child: Text(
                              sub ? 'Família e conta' : s.familyName,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: p.ink,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (s.demo) Tag('DEMO', color: p.sunnyTint),
                          accountMenu(),
                        ],
                      ),
                    ),
                    if (s.demo)
                      Container(
                        width: double.infinity,
                        color: p.sunnyTint,
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 20,
                        ),
                        child: Text(
                          'Dados fictícios. Alterações desta demonstração são temporárias.',
                          style: TextStyle(fontSize: 12, color: p.ink),
                        ),
                      ),
                    if (saving || s.loading)
                      const LinearProgressIndicator(
                        minHeight: 2,
                        semanticsLabel: 'Atualizando',
                      ),
                    Expanded(
                      child: s.loading && s.households.isEmpty
                          ? const Center(child: CircularProgressIndicator())
                          : s.error != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(s.error!, textAlign: TextAlign.center),
                                    const SizedBox(height: 16),
                                    FilledButton(
                                      onPressed: () => s.refresh(),
                                      child: const Text('Tentar novamente'),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : s.householdId == null
                          ? onboarding()
                          : Align(
                              alignment: Alignment.topCenter,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 1440,
                                ),
                                child: SingleChildScrollView(
                                  // Each page keeps its own scroll position,
                                  // instead of opening where the last one was.
                                  key: PageStorageKey(page),
                                  padding: EdgeInsets.fromLTRB(
                                    wide ? 32 : 18,
                                    20,
                                    wide ? 32 : 18,
                                    40,
                                  ),
                                  child: content(),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget content() => switch (page) {
    0 => overview(),
    1 => finances(),
    2 => goals(),
    3 => baby(),
    4 => health(),
    _ => family(),
  };
  Widget monthPicker() => Container(
    decoration: BoxDecoration(
      color: p.surface,
      border: Border.all(color: p.border),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Mês anterior',
          onPressed: () =>
              setState(() => month = DateTime(month.year, month.month - 1)),
          icon: const Icon(Icons.chevron_left),
        ),
        Text(
          DateFormat('MMM yyyy', 'pt_BR').format(month),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        IconButton(
          tooltip: 'Próximo mês',
          onPressed: () =>
              setState(() => month = DateTime(month.year, month.month + 1)),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    ),
  );
  MonthSummary get summary => MonthSummary(
    occurrences(s.rows('entries'), s.rows('settlements'), month),
  );
  Widget overview() {
    final m = summary;
    final essential = s
        .rows('goals')
        .where((g) => g['priority'] == 'essential')
        .toList();
    final missing = essential.fold<int>(0, (a, g) => a + remainingGoal(g));
    final unquoted = essential
        .where(
          (g) =>
              number(g, 'target_cents') == 0 &&
              number(g, 'acquired') < number(g, 'quantity'),
        )
        .length;
    final ready = essential
        .where((g) => number(g, 'acquired') >= number(g, 'quantity'))
        .length;
    final upcoming = m.items.where((e) => !e.paid && !e.income).toList();
    final colors = categoryIndex(m);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Heading(
          'Seu próximo passo, mais claro.',
          'As contas da casa e os planos para o bebê, no mesmo lugar.',
          action: monthPicker(),
        ),
        MetricGrid(
          children: [
            Metric(
              'Saldo previsto',
              money(m.balance),
              'Receitas menos despesas do mês',
              Icons.account_balance_wallet_rounded,
              color: p.brand,
              onColor: p.onBrand,
            ),
            Metric(
              'Receitas previstas',
              money(m.sum(true)),
              'Recebido: ${money(m.sum(true, paid: true))}',
              Icons.south_west_rounded,
              color: p.mintTint,
              accent: p.mint,
            ),
            Metric(
              'Despesas previstas',
              money(m.sum(false)),
              'Pago: ${money(m.sum(false, paid: true))}',
              Icons.north_east_rounded,
              color: p.indigoTint,
              accent: p.indigo,
            ),
            Metric(
              'Falta para o essencial',
              unquoted > 0 ? 'Cotar $unquoted itens' : money(missing),
              unquoted > 0
                  ? '${money(missing)} nas metas já cotadas'
                  : '$ready de ${essential.length} metas concluídas',
              Icons.child_care_rounded,
              color: p.sunnyTint,
              accent: p.sunny,
            ),
          ],
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, b) {
            final left = Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionTitle(
                    'Contas que pedem atenção',
                    caption: 'Pendências do mês selecionado',
                  ),
                  if (upcoming.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'Nenhuma despesa pendente neste mês.',
                        style: TextStyle(color: p.muted),
                      ),
                    ),
                  for (final e in upcoming.take(5))
                    entryTile(e, compact: true, colors: colors),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => go(1),
                      child: const Text('Ver todas as finanças'),
                    ),
                  ),
                ],
              ),
            );
            final right = Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionTitle(
                    'Para onde vai o dinheiro',
                    caption: 'Despesas previstas por categoria',
                  ),
                  categoryBars(m),
                  const SizedBox(height: 20),
                  Text(
                    'Resultado já realizado: ${money(m.realized)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Resultado do mês, sem incluir saldo bancário anterior.',
                    style: TextStyle(color: p.muted, fontSize: 12),
                  ),
                ],
              ),
            );
            return b.maxWidth > 820
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 6, child: left),
                      const SizedBox(width: 20),
                      Expanded(flex: 5, child: right),
                    ],
                  )
                : Column(children: [left, const SizedBox(height: 20), right]);
          },
        ),
        const SizedBox(height: 24),
        const SectionTitle('Metas em andamento'),
        if (s.rows('goals').isEmpty)
          EmptyState(
            'Vamos preparar o enxoval?',
            'Cadastre uma meta e acompanhe o que falta.',
            onAdd: () => go(2),
          )
        else
          goalGrid(
            s
                .rows('goals')
                .where((g) => number(g, 'acquired') < number(g, 'quantity'))
                .take(3)
                .toList(),
          ),
      ],
    );
  }

  /// The month's expense categories with their totals, largest first. The
  /// order picks each category's color, so the chart and the entry rows of
  /// the month match.
  List<MapEntry<String, int>> expenseCategories(MonthSummary m) {
    final totals = <String, int>{};
    for (final e in m.items.where((e) => !e.income)) {
      final name = e.entry['category'] as String;
      totals[name] = (totals[name] ?? 0) + e.amount;
    }
    return totals.entries.toList()..sort(
      (a, b) => a.value == b.value
          ? a.key.compareTo(b.key)
          : b.value.compareTo(a.value),
    );
  }

  /// Each expense category's place in the palette's category colors.
  Map<String, int> categoryIndex(MonthSummary m) {
    final last = p.categories.length - 1;
    return {
      for (final (i, e) in expenseCategories(m).indexed)
        e.key: i < last ? i : last,
    };
  }

  Widget categoryBars(MonthSummary m) {
    final sorted = expenseCategories(m);
    final colors = categoryIndex(m);
    final total = m.sum(false);
    return Column(
      children: [
        if (sorted.isEmpty)
          Text(
            'Cadastre despesas para visualizar a distribuição.',
            style: TextStyle(color: p.muted),
          ),
        for (final e in sorted)
          // One item for screen readers: the category, its total and share.
          Semantics(
            container: true,
            label:
                '${e.key}: ${money(e.value)}, ${total == 0 ? 0 : (e.value * 100 / total).round()}% das despesas previstas',
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 17),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: p.categories[colors[e.key]!].$1,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            e.key,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Text(
                          money(e.value),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: total == 0 ? 0 : e.value / total,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(99),
                      backgroundColor: p.surfaceAlt,
                      color: p.categories[colors[e.key]!].$1,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  void editEntry([Json? row]) {
    final hasPaid =
        row != null &&
        s.rows('settlements').any((p) => p['entry_id'] == row['id']);
    edit(
      'entries',
      row == null ? 'Novo lançamento' : 'Editar lançamento',
      [
        if (!hasPaid)
          const FieldSpec(
            'kind',
            'Tipo',
            options: {'income': 'Receita', 'expense': 'Despesa'},
            segmented: true,
          ),
        const FieldSpec('title', 'Descrição'),
        if (!hasPaid)
          const FieldSpec('amount_cents', 'Valor (R\$)', type: 'money', min: 1),
        const FieldSpec('category', 'Categoria', max: 60),
        if (!hasPaid) ...[
          const FieldSpec(
            'start_date',
            'Data / primeiro vencimento',
            type: 'date',
          ),
          const FieldSpec(
            'recurrence',
            'Repetição',
            options: {'once': 'Somente uma vez', 'monthly': 'Todo mês'},
            segmented: true,
          ),
        ],
        const FieldSpec(
          'end_date',
          'Última data (opcional)',
          type: 'date',
          optional: true,
        ),
        const FieldSpec('notes', 'Observações', type: 'notes', optional: true),
      ],
      row: row,
      defaults: {
        'kind': 'expense',
        'category': 'Outros',
        'recurrence': 'once',
        'start_date': iso(DateTime.now()),
      },
      help: hasPaid
          ? 'Há pagamentos registrados. Valor, tipo e início ficam preservados. Para mudar a regra, encerre esta e crie outra.'
          : 'Receitas e despesas mensais aparecem em cada mês a partir da primeira data. Marque cada ocorrência como paga ou recebida.',
    );
  }

  Widget finances() {
    final m = summary;
    final colors = categoryIndex(m);
    final list = m.items
        .where(
          (e) =>
              (filter == 'all' ||
                  filter == 'income' && e.income ||
                  filter == 'expense' && !e.income ||
                  filter == 'pending' && !e.paid) &&
              (e.entry['title'] as String).toLowerCase().contains(
                search.toLowerCase(),
              ),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Heading(
          'Finanças da família',
          'Salários, contas mensais, despesas pontuais e dívidas.',
          action: add('Novo lançamento', () => editEntry()),
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            monthPicker(),
            for (final e in {
              'all': 'Todos',
              'income': 'Receitas',
              'expense': 'Despesas',
              'pending': 'Pendentes',
            }.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: filter == e.key,
                onSelected: (_) => setState(() => filter = e.key),
              ),
          ],
        ),
        const SizedBox(height: 18),
        TextField(
          decoration: const InputDecoration(
            hintText: 'Buscar lançamento',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => search = v),
        ),
        const SizedBox(height: 20),
        if (list.isEmpty)
          EmptyState(
            'Nenhum lançamento encontrado',
            'Adicione uma receita ou despesa para este período.',
            onAdd: () => editEntry(),
          )
        else
          Panel(
            child: Column(
              children: [for (final e in list) entryTile(e, colors: colors)],
            ),
          ),
        const SizedBox(height: 28),
        Row(
          children: [
            const Expanded(child: SectionTitle('Dívidas em aberto')),
            TextButton.icon(
              onPressed: () => editDebt(),
              icon: const Icon(Icons.add),
              label: const Text('Adicionar dívida'),
            ),
          ],
        ),
        Text(
          'O saldo da dívida é acompanhado separadamente. Cadastre as parcelas em Finanças para incluí-las na previsão mensal e atualize o saldo devedor após os pagamentos.',
          style: TextStyle(color: p.muted, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 16),
        if (s.rows('debts').isEmpty)
          const EmptyState(
            'Nenhuma dívida cadastrada',
            'Você pode acompanhar credor, parcela e saldo devedor aqui.',
          )
        else
          Panel(
            child: Column(
              children: [
                for (final d in s.rows('debts'))
                  Semantics(
                    container: true,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(d['title'] as String),
                      subtitle: Text(
                        '${d['creditor']} · Parcela ${money(number(d, 'installment_cents'))}\nSaldo devedor: ${money(number(d, 'balance_cents'))}',
                      ),
                      isThreeLine: true,
                      trailing: actions('debts', d, () => editDebt(d)),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// One occurrence of an entry. A paid one shows its state; undoing the
  /// payment is in its ⋮ menu and in the message right after paying.
  /// Expenses take their category's color from [colors].
  Widget entryTile(
    Occurrence e, {
    bool compact = false,
    Map<String, int> colors = const {},
  }) {
    final overdue =
        !e.paid && e.date.isBefore(DateUtils.dateOnly(DateTime.now()));
    final title = e.entry['title'] as String;
    final color = colors[e.entry['category']];
    final (icon, tint) = e.income
        ? (p.mint, p.mintTint)
        : color == null
        ? (p.indigo, p.indigoTint)
        : (p.categories[color].$3, p.categories[color].$2);
    final verb = e.income ? 'Receber' : 'Pagar';
    // A row is one item for screen readers, with its buttons after it.
    return Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
              child: Icon(
                e.income ? Icons.south_west_rounded : Icons.north_east_rounded,
                size: 19,
                color: icon,
                semanticLabel: e.income ? 'Receita' : 'Despesa',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${DateFormat('dd/MM').format(e.date)} · ${e.entry['category']}${overdue ? ' · Em atraso' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      color: overdue ? p.danger : p.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  money(e.amount),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (!compact && e.paid)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          size: 16,
                          color: p.mint,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          e.income ? 'Recebido' : 'Pago',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: p.muted,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (!compact)
                  TextButton(
                    onPressed: saving ? null : () => settle(e, true),
                    child: Text(
                      verb,
                      semanticsLabel: '$verb $title',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
            if (!compact)
              actions(
                'entries',
                e.entry,
                () => editEntry(e.entry),
                undo: e.paid
                    ? (
                        e.income
                            ? 'Desfazer recebimento'
                            : 'Desfazer pagamento',
                        () => settle(e, false),
                      )
                    : null,
              ),
          ],
        ),
      ),
    );
  }

  /// Marks one occurrence as paid or received, or undoes that. Paying offers
  /// an undo in the message.
  Future<void> settle(Occurrence e, bool paid) {
    final what = e.income ? 'Recebimento' : 'Pagamento';
    return perform(
      () => s.rpc('settle_entry', {
        'p_entry_id': e.entry['id'],
        'p_occurrence': iso(e.date),
        'p_paid': paid,
      }),
      done: paid ? '$what registrado.' : '$what desfeito.',
      undo: paid
          ? SnackBarAction(label: 'Desfazer', onPressed: () => settle(e, false))
          : null,
    );
  }

  void editDebt([Json? row]) => edit(
    'debts',
    row == null ? 'Nova dívida' : 'Editar dívida',
    const [
      FieldSpec('title', 'Descrição'),
      FieldSpec('creditor', 'Credor', optional: true),
      FieldSpec('balance_cents', 'Saldo devedor atual (R\$)', type: 'money'),
      FieldSpec('installment_cents', 'Parcela mensal (R\$)', type: 'money'),
      FieldSpec('due_day', 'Dia do vencimento', type: 'int', min: 1, max: 31),
      FieldSpec('notes', 'Observações', type: 'notes', optional: true),
    ],
    row: row,
    defaults: const {'due_day': 10, 'installment_cents': 0},
  );
  void editGoal([Json? row]) => edit(
    'goals',
    row == null ? 'Nova meta' : 'Editar meta',
    const [
      FieldSpec('title', 'O que vocês querem comprar?'),
      FieldSpec('priority', 'Prioridade', options: priorityLabels),
      FieldSpec(
        'target_cents',
        'Orçamento para toda a quantidade (R\$)',
        type: 'money',
      ),
      FieldSpec('saved_cents', 'Dinheiro reservado hoje (R\$)', type: 'money'),
      FieldSpec(
        'quantity',
        'Quantidade total',
        type: 'int',
        min: 1,
        max: 10000,
      ),
      FieldSpec('acquired', 'Quantidade que já tem', type: 'int', max: 10000),
      FieldSpec('target_date', 'Data desejada', type: 'date', optional: true),
      FieldSpec('notes', 'Observações', type: 'notes', optional: true),
    ],
    row: row,
    defaults: const {
      'priority': 'essential',
      'target_cents': 0,
      'saved_cents': 0,
      'quantity': 1,
      'acquired': 0,
    },
    help:
        'Defina o orçamento total da meta. Presentes entram na quantidade já adquirida. A reserva é apenas uma separação do seu dinheiro, não uma nova despesa.',
  );
  Widget goals() {
    final list = s
        .rows('goals')
        .where(
          (g) =>
              (filter == 'all' || g['priority'] == filter) &&
              (g['title'] as String).toLowerCase().contains(
                search.toLowerCase(),
              ),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Heading(
          'Planos que ganham forma.',
          'O essencial primeiro. Conforto e praticidade quando couberem.',
          action: add('Nova meta', () => editGoal()),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final e in {'all': 'Tudo', ...priorityLabels}.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: filter == e.key,
                onSelected: (_) => setState(() => filter = e.key),
              ),
            TextButton.icon(
              onPressed: saving ? null : seedEssentials,
              icon: const Icon(Icons.playlist_add),
              label: const Text('Adicionar checklist inicial'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (list.isEmpty)
          EmptyState(
            'Qual é o primeiro plano?',
            'Adicione um item do enxoval ou uma meta da família.',
            onAdd: () => editGoal(),
          )
        else
          goalGrid(list),
        const SizedBox(height: 16),
        Text(
          '“Falta reservar” usa o orçamento proporcional à quantidade que falta, descontando a reserva atual. Atualize preços conforme suas cotações.',
          style: TextStyle(color: p.muted, fontSize: 12, height: 1.6),
        ),
      ],
    );
  }

  Widget goalGrid(List<Json> list) => LayoutBuilder(
    builder: (context, b) {
      final cols = b.maxWidth > 1050
          ? 3
          : b.maxWidth > 650
          ? 2
          : 1;
      return Wrap(
        spacing: 18,
        runSpacing: 18,
        children: [
          for (final g in list)
            SizedBox(
              width: (b.maxWidth - 18 * (cols - 1)) / cols,
              child: goalCard(g),
            ),
        ],
      );
    },
  );
  Widget goalCard(Json g) {
    final quantity = number(g, 'quantity');
    final acquired = number(g, 'acquired');
    final done = acquired >= quantity;
    final target = number(g, 'target_cents');
    final progress = done
        ? 1.0
        : target == 0
        ? 0.0
        : (1 - remainingGoal(g) / target).clamp(0.0, 1.0);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Tag(
                priorityLabels[g['priority']] ?? 'Meta',
                color: switch (g['priority']) {
                  'comfort' => p.skyTint,
                  'optional' => p.indigoTint,
                  _ => p.brandTint,
                },
              ),
              const Spacer(),
              actions('goals', g, () => editGoal(g)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            g['title'] as String,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: p.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$acquired de $quantity adquiridos · ${dateText(g['target_date'] as String?)}',
            style: TextStyle(fontSize: 12, color: p.muted),
          ),
          const SizedBox(height: 22),
          LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            borderRadius: BorderRadius.circular(99),
            backgroundColor: p.surfaceAlt,
            semanticsLabel: 'Progresso da meta',
            semanticsValue: '${(progress * 100).round()}%',
          ),
          const SizedBox(height: 12),
          Text(
            done
                ? 'Concluído'
                : target == 0
                ? 'Defina o orçamento'
                : 'Falta reservar ${money(remainingGoal(g))}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 5),
          Text(
            'Reservado ${money(number(g, 'saved_cents'))}',
            style: TextStyle(color: p.muted, fontSize: 12),
          ),
          const SizedBox(height: 18),
          if (!done)
            OutlinedButton.icon(
              onPressed: saving ? null : () => purchase(g),
              icon: const Icon(Icons.check, size: 17),
              label: const Text('Registrar aquisição'),
            ),
        ],
      ),
    );
  }

  Future<void> purchase(Json g) async {
    final max = number(g, 'quantity') - number(g, 'acquired');
    final data = await editForm(
      context,
      'Registrar aquisição',
      [
        FieldSpec(
          'p_quantity',
          'Quantidade adquirida',
          type: 'int',
          min: 1,
          max: max,
        ),
        const FieldSpec('p_cost_cents', 'Total pago (R\$)', type: 'money'),
        const FieldSpec('p_date', 'Data', type: 'date'),
      ],
      initial: {
        'p_quantity': 1,
        'p_cost_cents': 0,
        'p_date': iso(DateTime.now()),
      },
      help:
          'Use R\$ 0 para presente ou reaproveitamento. Um valor pago será registrado uma única vez nas despesas do mês.',
    );
    if (data != null) {
      await perform(
        () => s.rpc('buy_goal', {'p_goal_id': g['id'], ...data}),
        done: 'Aquisição registrada.',
      );
    }
  }

  Future<void> seedEssentials() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Adicionar checklist inicial?'),
        content: const Text(
          'Adiciona 12 itens sem preço, com quantidades iniciais editáveis. Itens com o mesmo nome não serão duplicados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await perform(() async {
      for (final entry in {
        'Berço e colchão adequado': 1,
        'Lençol com elástico': 3,
        'Bodies RN': 4,
        'Bodies P': 6,
        'Macacões P': 4,
        'Toalha macia': 2,
        'Banheira': 1,
        'Fralda RN (pacote pequeno)': 1,
        'Fralda P (pacote)': 2,
        'Pano de boca': 6,
        'Termômetro digital': 1,
        'Absorvente pós-parto (pacote)': 2,
      }.entries) {
        if (s.rows('goals').any((g) => g['title'] == entry.key)) continue;
        await s.save('goals', {
          'title': entry.key,
          'priority': 'essential',
          'quantity': entry.value,
          'acquired': 0,
          'target_cents': 0,
          'saved_cents': 0,
          'notes': 'Quantidade sugerida. Ajuste à rotina da família.',
        }, reload: false);
      }
      await s.refresh();
    }, done: 'Checklist adicionado.');
  }

  void editBaby([Json? row]) => edit(
    'babies',
    row == null ? 'Cadastrar bebê' : 'Editar bebê',
    const [
      FieldSpec('name', 'Nome ou apelido', max: 80),
      FieldSpec(
        'due_date',
        'Data prevista do parto',
        type: 'date',
        optional: true,
      ),
      FieldSpec('birth_date', 'Nascimento', type: 'date', optional: true),
      FieldSpec('notes', 'Observações', type: 'notes', optional: true),
    ],
    row: row,
    help:
        'Use a data prevista informada no pré-natal. Você pode cadastrar mais de um bebê. Ao salvar, você declara ser mãe, pai ou responsável legal e autoriza o registro dos dados e da saúde do bebê, que ficam só com a sua família.',
  );
  Widget baby() {
    final babies = s.rows('babies');
    if (babies.isEmpty) {
      return Column(
        children: [
          Heading(
            'Cada fase, registrada.',
            'Do planejamento à chegada do bebê.',
            action: add('Cadastrar bebê', () => editBaby()),
          ),
          EmptyState(
            'Vamos conhecer seu bebê?',
            'Você pode começar com um apelido e a data prevista.',
            onAdd: () => editBaby(),
          ),
        ],
      );
    }
    final selected =
        babies.where((b) => b['id'] == babyId).firstOrNull ?? babies.first;
    final measures =
        s
            .rows('measurements')
            .where((r) => r['baby_id'] == selected['id'])
            .toList()
          ..sort(
            (a, b) => (b['measured_at'] as String).compareTo(
              a['measured_at'] as String,
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Heading(
          'Cada fase, registrada.',
          'Histórico de peso e comprimento, sem comparações automáticas com padrões clínicos.',
          action: add('Novo bebê', () => editBaby()),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final b in babies)
              ChoiceChip(
                label: Text(b['name'] as String),
                selected: b['id'] == selected['id'],
                onSelected: (_) => setState(() => babyId = b['id'] as String),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Panel(
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: p.skyTint,
                child: Icon(Icons.child_care_rounded, color: p.sky, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selected['name'] as String,
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      selected['birth_date'] != null
                          ? 'Nascimento: ${dateText(selected['birth_date'] as String)}'
                          : 'Previsão de chegada: ${dateText(selected['due_date'] as String?)}',
                      style: TextStyle(color: p.muted),
                    ),
                  ],
                ),
              ),
              actions('babies', selected, () => editBaby(selected)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (ctx, b) {
            final cards = [
              GrowthChart(
                rows: measures,
                field: 'weight_grams',
                title: 'Peso',
                unit: 'kg',
                divisor: 1000,
              ),
              GrowthChart(
                rows: measures,
                field: 'length_mm',
                title: 'Comprimento',
                unit: 'cm',
                divisor: 10,
              ),
            ];
            return b.maxWidth > 750
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: 20),
                      Expanded(child: cards[1]),
                    ],
                  )
                : Column(
                    children: [cards[0], const SizedBox(height: 20), cards[1]],
                  );
          },
        ),
        const SizedBox(height: 26),
        Row(
          children: [
            const Expanded(child: SectionTitle('Histórico de medidas')),
            TextButton.icon(
              onPressed: () => editMeasure(selected['id'] as String),
              icon: const Icon(Icons.add),
              label: const Text('Registrar'),
            ),
          ],
        ),
        if (measures.isEmpty)
          EmptyState(
            'Ainda não há medidas',
            'Registre os valores informados na consulta.',
            onAdd: () => editMeasure(selected['id'] as String),
          )
        else
          Panel(
            child: Column(
              children: [
                for (final r in measures)
                  Semantics(
                    container: true,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(dateText(r['measured_at'] as String)),
                      subtitle: Text(
                        '${r['weight_grams'] == null ? 'Peso não informado' : '${decimal(number(r, 'weight_grams') / 1000)} kg'} · ${r['length_mm'] == null ? 'Comprimento não informado' : '${decimal(number(r, 'length_mm') / 10)} cm'}',
                      ),
                      trailing: actions(
                        'measurements',
                        r,
                        () => editMeasure(selected['id'] as String, r),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> editMeasure(String id, [Json? row]) async {
    final result = await editForm(
      context,
      'Registrar medida',
      const [
        FieldSpec('measured_at', 'Data da medida', type: 'date'),
        FieldSpec(
          'weight_grams',
          'Peso em gramas (ex.: 3250)',
          type: 'int',
          optional: true,
          min: 1,
          max: 200000,
        ),
        FieldSpec(
          'length_mm',
          'Comprimento em milímetros (ex.: 490)',
          type: 'int',
          optional: true,
          min: 1,
          max: 2500,
        ),
        FieldSpec('notes', 'Observações', type: 'notes', optional: true),
      ],
      initial: row ?? {'measured_at': iso(DateTime.now())},
      help:
          'Preencha pelo menos uma medida. 3,250 kg = 3250 g. 49 cm = 490 mm.',
    );
    if (result == null) return;
    if (result['weight_grams'] == null && result['length_mm'] == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informe peso ou comprimento.')),
        );
      }
      return;
    }
    await perform(
      () => s.save('measurements', {
        ...result,
        'baby_id': id,
      }, id: row?['id'] as String?),
      done: row == null ? 'Medida registrada.' : 'Alterações salvas.',
    );
  }

  void editHealth([Json? row]) => edit(
    'health_events',
    row == null ? 'Novo registro de saúde' : 'Editar registro',
    [
      const FieldSpec('title', 'Descrição'),
      const FieldSpec('event_type', 'Tipo', options: typeLabels),
      const FieldSpec('event_date', 'Data', type: 'date'),
      FieldSpec(
        'baby_id',
        'Bebê (opcional)',
        optional: true,
        options: {
          for (final b in s.rows('babies'))
            b['id'] as String: b['name'] as String,
        },
      ),
      const FieldSpec('provider', 'Profissional / local', optional: true),
      const FieldSpec(
        'notes',
        'Anotações / orientação recebida',
        type: 'notes',
        optional: true,
      ),
    ],
    row: row,
    defaults: {'event_type': 'appointment', 'event_date': iso(DateTime.now())},
    help:
        'Registre consultas, exames, vacinas e medicamentos conforme a orientação recebida. O app não prescreve doses nem interpreta resultados. Esses dados ficam só com a sua família e nunca são usados em anúncios.',
  );

  /// Pending events first, the nearest on top, so the next appointment never
  /// hides among old ones; then the completed ones, the latest on top.
  Widget health() {
    int byDate(Json a, Json b) =>
        (a['event_date'] as String).compareTo(b['event_date'] as String);
    final all = s.rows('health_events');
    final upcoming = all.where((e) => e['completed'] != true).toList()
      ..sort(byDate);
    final done = all.where((e) => e['completed'] == true).toList()
      ..sort((a, b) => byDate(b, a));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Heading(
          'Cuidado também é organização.',
          'Consultas, exames, medicamentos e seus custos.',
          action: add('Novo registro', () => editHealth()),
        ),
        if (all.isEmpty)
          EmptyState(
            'Nenhum compromisso registrado',
            'Comece pela próxima consulta ou exame.',
            onAdd: () => editHealth(),
          )
        else ...[
          const SectionTitle('Próximos'),
          if (upcoming.isEmpty)
            SizedBox(
              width: double.infinity,
              child: Panel(
                child: Text(
                  'Nenhum compromisso pendente.',
                  style: TextStyle(color: p.muted),
                ),
              ),
            )
          else
            healthList(upcoming),
          if (done.isNotEmpty) ...[
            const SizedBox(height: 28),
            const SectionTitle('Realizados'),
            healthList(done),
          ],
        ],
      ],
    );
  }

  Widget healthList(List<Json> list) => Panel(
    child: Column(
      children: [
        for (final (i, e) in list.indexed) ...[
          if (i > 0) const Divider(height: 1),
          healthTile(e),
        ],
      ],
    ),
  );

  Widget healthTile(Json e) {
    final completed = e['completed'] == true;
    final date = e['event_date'] as String;
    final passed = !completed && date.compareTo(iso(DateTime.now())) < 0;
    return Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: completed ? p.mintTint : p.brandTint,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    completed ? Icons.check_rounded : Icons.favorite_rounded,
                    size: 19,
                    color: completed ? p.mint : p.brandText,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e['title'] as String,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '${typeLabels[e['event_type']]} · ${dateText(date)}${passed ? ' · Data já passou' : ''}',
                        style: TextStyle(
                          color: passed ? p.danger : p.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                actions('health_events', e, () => editHealth(e)),
              ],
            ),
            if ((e['notes'] ?? '').toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  e['notes'] as String,
                  style: TextStyle(color: p.muted),
                ),
              ),
            Wrap(
              spacing: 12,
              children: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => perform(
                          () => s.save('health_events', {
                            'completed': !completed,
                          }, id: e['id'] as String),
                          done: completed
                              ? 'Registro reaberto.'
                              : 'Marcado como realizado.',
                        ),
                  child: Text(completed ? 'Reabrir' : 'Marcar como realizado'),
                ),
                TextButton(
                  onPressed: saving || e['expense_entry_id'] != null
                      ? null
                      : () => healthCost(e),
                  child: Text(
                    e['expense_entry_id'] != null
                        ? 'Despesa registrada'
                        : 'Registrar custo',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> healthCost(Json e) async {
    final result = await editForm(
      context,
      'Registrar custo',
      const [
        FieldSpec('p_amount_cents', 'Total pago (R\$)', type: 'money', min: 1),
        FieldSpec('p_date', 'Data do pagamento', type: 'date'),
      ],
      initial: {'p_date': iso(DateTime.now())},
      help: 'O valor será incluído em Saúde nas despesas e marcado como pago.',
    );
    if (result != null) {
      await perform(
        () => s.rpc('record_health_cost', {'p_event_id': e['id'], ...result}),
        done: 'Custo registrado em Finanças.',
      );
    }
  }

  Widget onboarding() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 550),
        child: Column(
          children: [
            const NinhoLogo(size: 88),
            const SizedBox(height: 20),
            const Heading(
              'Um lugar para os planos de vocês.',
              'Crie uma família ou entre com o convite de quem já começou.',
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: saving ? null : createFamily,
                child: const Text('Criar minha família'),
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: saving ? null : acceptInvite,
              child: const Text('Tenho um convite'),
            ),
          ],
        ),
      ),
    ),
  );
  Future<void> createFamily() async {
    final value = await editForm(context, 'Criar família', const [
      FieldSpec('p_name', 'Nome da família', max: 80),
    ]);
    if (value != null) {
      await perform(
        () => s.rpc('create_household', value),
        done: 'Família criada.',
      );
    }
  }

  Future<void> acceptInvite() async {
    final value = await editForm(
      context,
      'Entrar na família',
      const [FieldSpec('p_token', 'Código do convite')],
      help:
          'Cole o código compartilhado por quem criou a família. Ele expira em 72 horas e só pode ser usado uma vez.',
    );
    if (value != null) {
      await perform(
        () => s.rpc('accept_invite', value),
        done: 'Você entrou na família.',
      );
    }
  }

  Widget family() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Heading(
        'Juntos no mesmo plano.',
        'Cada pessoa entra com sua própria conta e acessa os dados da família.',
      ),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('Família atual'),
            DropdownButtonFormField<String>(
              value: s.householdId,
              isExpanded: true,
              items: [
                for (final h in s.households)
                  DropdownMenuItem(
                    value: h['id'] as String,
                    child: Text(
                      h['name'] as String,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: saving
                  ? null
                  : (v) {
                      if (v != null) {
                        perform(
                          () => s.selectFamily(v),
                          done: 'Família selecionada.',
                        );
                      }
                    },
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: saving || s.demo ? null : invite,
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Gerar convite'),
                ),
                OutlinedButton(
                  onPressed: saving || s.demo ? null : acceptInvite,
                  child: const Text('Usar convite'),
                ),
                TextButton(
                  onPressed: saving || s.demo ? null : createFamily,
                  child: const Text('Nova família'),
                ),
              ],
            ),
            // Says why the buttons above are off.
            if (s.demo)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 18, color: p.brandText),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Convites e novas famílias ficam disponíveis quando você cria uma conta.',
                        style: TextStyle(
                          color: p.ink,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            Text(
              'Convites são gerados pelo criador da família. Quem entrar poderá ver e editar finanças e registros de saúde. Gere somente para pessoas que devem compartilhar esses dados. Quem criou a família pode remover pessoas a qualquer momento.',
              style: TextStyle(color: p.muted, height: 1.6, fontSize: 13),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('Pessoas nesta família'),
            if (s.members.isEmpty)
              Text(
                'As pessoas aparecem aqui quando entram com um convite.',
                style: TextStyle(color: p.muted),
              ),
            for (final m in s.members)
              Semantics(
                container: true,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(m['email'] as String? ?? 'Sem e-mail'),
                  subtitle: Text(
                    m['role'] == 'owner' ? 'Criou a família' : 'Participa',
                  ),
                  trailing: s.isOwner && m['role'] != 'owner'
                      ? TextButton(
                          onPressed: saving ? null : () => removeMember(m),
                          child: Text(
                            'Remover',
                            semanticsLabel: 'Remover ${m['email']}',
                          ),
                        )
                      : null,
                ),
              ),
            if (!s.isOwner && !s.demo)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: OutlinedButton(
                  onPressed: saving ? null : leaveFamily,
                  child: const Text('Sair desta família'),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      account(),
      const SizedBox(height: 20),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('Sobre esta versão'),
            Text(
              'Ninho 0.1 · Planejamento familiar\n\nRecursos de cobrança de assinatura não estão ativos nesta versão. O compartilhamento funciona por família.\n\nEm Saúde, registre informações recebidas dos profissionais. O aplicativo não substitui o acompanhamento clínico.${widget.ads.enabled ? '\n\nO app é gratuito e mostra um anúncio ao abrir, no máximo a cada 4 horas. Dados de finanças, família e saúde nunca são usados em anúncios.' : ''}',
              style: TextStyle(color: p.muted, height: 1.6),
            ),
          ],
        ),
      ),
    ],
  );
  Widget account() => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('Sua conta'),
        Text(
          s.email != null
              ? 'Você entrou como ${s.email}.'
              : s.demo
              ? 'A demonstração não tem conta. Os dados fictícios somem ao sair.'
              : 'Você entrou na sua conta.',
          style: TextStyle(color: p.muted, height: 1.6),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            if (privacyPolicy case final page?)
              PageLink('Política de privacidade', page),
            ValueListenableBuilder<bool>(
              valueListenable: widget.ads.privacyOptions,
              builder: (context, shown, _) => shown
                  ? TextButton.icon(
                      onPressed: widget.ads.showPrivacyOptions,
                      icon: const Icon(Icons.privacy_tip_outlined, size: 18),
                      label: const Text('Privacidade dos anúncios'),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: saving || !s.canDeleteAccount ? null : deleteAccount,
          style: OutlinedButton.styleFrom(foregroundColor: p.danger),
          icon: const Icon(Icons.delete_forever_outlined, size: 20),
          label: const Text('Excluir minha conta'),
        ),
      ],
    ),
  );
  Future<void> deleteAccount() async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const DeleteAccountDialog(),
    );
    if (password == null || !mounted) return;
    // Deleting ends the session and replaces this screen, so the message goes
    // to the app's messenger, which outlives it.
    final messenger = ScaffoldMessenger.of(context);
    final palette = p;
    setState(() => saving = true);
    try {
      await s.deleteAccount(password);
      messenger.showSnackBar(const SnackBar(content: Text('Conta excluída.')));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            cleanError(e),
            style: TextStyle(color: palette.background),
          ),
          backgroundColor: palette.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> invite() async {
    String? code;
    await perform(() async {
      code =
          await s.rpc('create_invite', {'p_household_id': s.householdId})
              as String;
    }, done: 'Convite gerado.');
    if (code == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Convite da família'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Válido por 72 horas e para uma pessoa. Gerar outro código invalida o anterior.',
            ),
            const SizedBox(height: 18),
            SelectableText(code!),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
          FilledButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code!));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Copiar código'),
          ),
        ],
      ),
    );
  }

  Future<void> removeMember(Json member) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover da família?'),
        content: Text(
          '${member['email']} perde o acesso aos dados desta família. Convites ainda não usados deixam de valer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await perform(
      () => s.rpc('remove_member', {
        'p_household_id': s.householdId,
        'p_user_id': member['user_id'],
      }),
      done: 'Pessoa removida da família.',
    );
  }

  Future<void> leaveFamily() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sair de ${s.familyName}?'),
        content: const Text(
          'Você perde o acesso aos dados desta família. Para voltar, será preciso um novo convite.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await perform(
      () => s.rpc('leave_household', {'p_household_id': s.householdId}),
      done: 'Você saiu da família.',
    );
  }
}
