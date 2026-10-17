import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'data.dart';
import 'domain.dart';
import 'forms.dart';
import 'widgets.dart';

class HomeScreen extends StatefulWidget {
  final Store store;
  final Future<void> Function() onLogout;
  const HomeScreen({super.key, required this.store, required this.onLogout});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int page = 0;
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  bool saving = false;
  String filter = 'all';
  String search = '';
  String? babyId;
  Store get s => widget.store;
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
    Icons.account_balance_wallet_outlined,
    Icons.flag_outlined,
    Icons.child_care_outlined,
    Icons.favorite_border,
    Icons.people_outline,
  ];
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

  Future<void> perform(Future<void> Function() action) async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.error == null ? 'Atualizado.' : s.error!)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(cleanError(e)),
            backgroundColor: const Color(0xff963f32),
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
      await perform(() => s.save(resource, result, id: row?['id'] as String?));
    }
  }

  Future<void> remove(String resource, Json row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir registro?'),
        content: Text(
          'Excluir “${row['title'] ?? row['name'] ?? 'medida'}”? Esta ação também pode remover os registros vinculados e alterar os totais.',
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
      await perform(() => s.remove(resource, row['id'] as String));
    }
  }

  Widget actions(String resource, Json row, VoidCallback onEdit) =>
      PopupMenuButton<String>(
        tooltip: 'Opções do registro',
        enabled: !saving,
        onSelected: (v) {
          if (v == 'edit') {
            onEdit();
          } else {
            remove(resource, row);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'edit', child: Text('Editar')),
          const PopupMenuItem(value: 'delete', child: Text('Excluir')),
        ],
      );
  Widget add(String label, VoidCallback onTap) => FilledButton.icon(
    onPressed: saving ? null : onTap,
    icon: const Icon(Icons.add, size: 18),
    label: Text(label),
  );
  void go(int i) => setState(() {
    page = i;
    search = '';
    filter = 'all';
  });
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1050;
    return Scaffold(
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: page,
              onDestinationSelected: go,
              height: 76,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: [
                for (var i = 0; i < labels.length; i++)
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
                color: Colors.white,
                shape: const Border(
                  right: BorderSide(color: Color(0xffe4e9e2)),
                ),
                child: SizedBox(
                  width: 210,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(26, 34, 20, 36),
                        child: Row(
                          children: [
                            Icon(Icons.spa_outlined, color: green, size: 30),
                            SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                'Ninho',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 27,
                                  fontWeight: FontWeight.w700,
                                  color: ink,
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
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            selected: i == page,
                            selectedTileColor: const Color(0xffe7f0e9),
                            selectedColor: green,
                            leading: Icon(icons[i], size: 21),
                            title: Text(
                              labels[i],
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
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
                            color: muted.withValues(alpha: .85),
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
                        if (!wide)
                          const Padding(
                            padding: EdgeInsets.only(right: 10),
                            child: Icon(Icons.spa_outlined, color: green),
                          ),
                        Expanded(
                          child: Text(
                            s.familyName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: ink,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (s.demo)
                          const Chip(
                            label: Text(
                              'DEMO',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        IconButton(
                          onPressed: s.loading || saving
                              ? null
                              : () => s.refresh(),
                          tooltip: 'Atualizar dados',
                          icon: const Icon(Icons.refresh, size: 21),
                        ),
                        IconButton(
                          onPressed: saving
                              ? null
                              : () => perform(widget.onLogout),
                          tooltip: 'Sair',
                          icon: const Icon(Icons.logout, size: 21),
                        ),
                      ],
                    ),
                  ),
                  if (s.demo)
                    Container(
                      width: double.infinity,
                      color: const Color(0xfff4eddc),
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 20,
                      ),
                      child: const Text(
                        'Dados fictícios. Alterações desta demonstração são temporárias.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  if (saving || s.loading)
                    const LinearProgressIndicator(minHeight: 2),
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
                              constraints: const BoxConstraints(maxWidth: 1440),
                              child: SingleChildScrollView(
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
      color: Colors.white,
      border: Border.all(color: const Color(0xffe4e9e2)),
      borderRadius: BorderRadius.circular(12),
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
              Icons.account_balance_wallet_outlined,
              accent: true,
            ),
            Metric(
              'Receitas previstas',
              money(m.sum(true)),
              'Recebido: ${money(m.sum(true, paid: true))}',
              Icons.south_west,
            ),
            Metric(
              'Despesas previstas',
              money(m.sum(false)),
              'Pago: ${money(m.sum(false, paid: true))}',
              Icons.north_east,
            ),
            Metric(
              'Falta para o essencial',
              unquoted > 0 ? 'Cotar $unquoted itens' : money(missing),
              unquoted > 0
                  ? '${money(missing)} nas metas já cotadas'
                  : '$ready de ${essential.length} metas concluídas',
              Icons.child_care_outlined,
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
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'Nenhuma despesa pendente neste mês.',
                        style: TextStyle(color: muted),
                      ),
                    ),
                  for (final e in upcoming.take(5)) entryTile(e, compact: true),
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
                  const Text(
                    'Resultado do mês, sem incluir saldo bancário anterior.',
                    style: TextStyle(color: muted, fontSize: 12),
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

  Widget categoryBars(MonthSummary m) {
    final cats = <String, int>{};
    for (final e in m.items.where((e) => !e.income)) {
      final name = e.entry['category'] as String;
      cats[name] = (cats[name] ?? 0) + e.amount;
    }
    final sorted = cats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      children: [
        if (sorted.isEmpty)
          const Text(
            'Cadastre despesas para visualizar a distribuição.',
            style: TextStyle(color: muted),
          ),
        for (final e in sorted)
          Padding(
            padding: const EdgeInsets.only(bottom: 17),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(e.key, style: const TextStyle(fontSize: 13)),
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
                  value: m.sum(false) == 0 ? 0 : e.value / m.sum(false),
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(8),
                  backgroundColor: const Color(0xffedf1eb),
                  color: green,
                ),
              ],
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
        const FieldSpec('title', 'Descrição'),
        const FieldSpec('category', 'Categoria', max: 60),
        if (!hasPaid) ...[
          const FieldSpec(
            'kind',
            'Tipo',
            options: {'income': 'Receita', 'expense': 'Despesa'},
          ),
          const FieldSpec('amount_cents', 'Valor (R\$)', type: 'money', min: 1),
          const FieldSpec(
            'start_date',
            'Data / primeiro vencimento',
            type: 'date',
          ),
          const FieldSpec(
            'recurrence',
            'Repetição',
            options: {'once': 'Somente uma vez', 'monthly': 'Todo mês'},
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
          Panel(child: Column(children: [for (final e in list) entryTile(e)])),
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
        const Text(
          'O saldo da dívida é acompanhado separadamente. Cadastre as parcelas em Finanças para incluí-las na previsão mensal e atualize o saldo devedor após os pagamentos.',
          style: TextStyle(color: muted, fontSize: 13, height: 1.5),
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
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(d['title'] as String),
                    subtitle: Text(
                      '${d['creditor']} · Parcela ${money(number(d, 'installment_cents'))}\nSaldo devedor: ${money(number(d, 'balance_cents'))}',
                    ),
                    isThreeLine: true,
                    trailing: actions('debts', d, () => editDebt(d)),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget entryTile(Occurrence e, {bool compact = false}) {
    final overdue =
        !e.paid &&
        e.date.isBefore(
          DateTime(
            DateTime.now().year,
            DateTime.now().month,
            DateTime.now().day,
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: e.income
                  ? const Color(0xffeaf3ed)
                  : const Color(0xfff5eee7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              e.income ? Icons.south_west : Icons.north_east,
              size: 19,
              color: e.income ? green : const Color(0xff92674c),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.entry['title'] as String,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  '${DateFormat('dd/MM').format(e.date)} · ${e.entry['category']}${overdue ? ' · Em atraso' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    color: overdue ? const Color(0xffa14b3f) : muted,
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
              if (!compact)
                TextButton(
                  onPressed: saving
                      ? null
                      : () => perform(
                          () => s.rpc('settle_entry', {
                            'p_entry_id': e.entry['id'],
                            'p_occurrence': iso(e.date),
                            'p_paid': !e.paid,
                          }),
                        ),
                  child: Text(
                    e.paid
                        ? 'Desfazer baixa'
                        : e.income
                        ? 'Receber'
                        : 'Pagar',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
          if (!compact) actions('entries', e.entry, () => editEntry(e.entry)),
        ],
      ),
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
        const Text(
          '“Falta reservar” usa o orçamento proporcional à quantidade que falta, descontando a reserva atual. Atualize preços conforme suas cotações.',
          style: TextStyle(color: muted, fontSize: 12, height: 1.6),
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
              Chip(
                label: Text(
                  priorityLabels[g['priority']] ?? 'Meta',
                  style: const TextStyle(fontSize: 11),
                ),
                visualDensity: VisualDensity.compact,
              ),
              const Spacer(),
              actions('goals', g, () => editGoal(g)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            g['title'] as String,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$acquired de $quantity adquiridos · ${dateText(g['target_date'] as String?)}',
            style: const TextStyle(fontSize: 12, color: muted),
          ),
          const SizedBox(height: 22),
          LinearProgressIndicator(
            value: progress,
            minHeight: 7,
            borderRadius: BorderRadius.circular(8),
            backgroundColor: const Color(0xffedf1eb),
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
            style: const TextStyle(color: muted, fontSize: 12),
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
      await perform(() => s.rpc('buy_goal', {'p_goal_id': g['id'], ...data}));
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
    });
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
        'Use a data prevista informada no pré-natal. Você pode cadastrar mais de um bebê.',
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
              const CircleAvatar(
                radius: 28,
                backgroundColor: Color(0xffe7f0e9),
                child: Icon(Icons.child_care, color: green, size: 28),
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
                      style: const TextStyle(color: muted),
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
                  ListTile(
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
        'Registre consultas, exames, vacinas e medicamentos conforme a orientação recebida. O app não prescreve doses nem interpreta resultados.',
  );
  Widget health() {
    final list = [...s.rows('health_events')]
      ..sort(
        (a, b) =>
            (a['event_date'] as String).compareTo(b['event_date'] as String),
      );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Heading(
          'Cuidado também é organização.',
          'Consultas, exames, medicamentos e seus custos.',
          action: add('Novo registro', () => editHealth()),
        ),
        if (list.isEmpty)
          EmptyState(
            'Nenhum compromisso registrado',
            'Comece pela próxima consulta ou exame.',
            onAdd: () => editHealth(),
          )
        else
          Panel(
            child: Column(
              children: [
                for (final e in list)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              e['completed'] == true
                                  ? Icons.check_circle_outline
                                  : Icons.favorite_border,
                              color: green,
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
                                    '${typeLabels[e['event_type']]} · ${dateText(e['event_date'] as String)}',
                                    style: const TextStyle(
                                      color: muted,
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
                              style: const TextStyle(color: muted),
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
                                        'completed': e['completed'] != true,
                                      }, id: e['id'] as String),
                                    ),
                              child: Text(
                                e['completed'] == true
                                    ? 'Reabrir'
                                    : 'Marcar como realizado',
                              ),
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
                        const Divider(height: 1),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
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
            const Icon(Icons.spa_outlined, size: 54, color: green),
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
    if (value != null) await perform(() => s.rpc('create_household', value));
  }

  Future<void> acceptInvite() async {
    final value = await editForm(
      context,
      'Entrar na família',
      const [FieldSpec('p_token', 'Código do convite')],
      help:
          'Cole o código compartilhado por quem criou a família. Ele expira em 72 horas e só pode ser usado uma vez.',
    );
    if (value != null) await perform(() => s.rpc('accept_invite', value));
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
                      if (v != null) perform(() => s.selectFamily(v));
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
            const SizedBox(height: 16),
            const Text(
              'Convites são gerados pelo criador da família. Quem entrar poderá ver e editar finanças e registros de saúde. Gere somente para pessoas que devem compartilhar esses dados. Quem criou a família pode remover pessoas a qualquer momento.',
              style: TextStyle(color: muted, height: 1.6, fontSize: 13),
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
              const Text(
                'As pessoas aparecem aqui quando entram com um convite.',
                style: TextStyle(color: muted),
              ),
            for (final m in s.members)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(m['email'] as String? ?? 'Sem e-mail'),
                subtitle: Text(
                  m['role'] == 'owner' ? 'Criou a família' : 'Participa',
                ),
                trailing: s.isOwner && m['role'] != 'owner'
                    ? TextButton(
                        onPressed: saving ? null : () => removeMember(m),
                        child: const Text('Remover'),
                      )
                    : null,
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
      const Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionTitle('Sobre esta versão'),
            Text(
              'Ninho 0.1 · Planejamento familiar\n\nRecursos de cobrança de assinatura não estão ativos nesta versão. O compartilhamento funciona por família.\n\nEm Saúde, registre informações recebidas dos profissionais. O aplicativo não substitui o acompanhamento clínico.',
              style: TextStyle(color: muted, height: 1.6),
            ),
          ],
        ),
      ),
    ],
  );
  Future<void> invite() async {
    String? code;
    await perform(() async {
      code =
          await s.rpc('create_invite', {'p_household_id': s.householdId})
              as String;
    });
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
    );
  }
}
