import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'domain.dart';

const apiUrl = String.fromEnvironment('API_URL');
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
bool get configured =>
    apiUrl.isNotEmpty && supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
const resources = [
  'babies',
  'entries',
  'settlements',
  'debts',
  'goals',
  'measurements',
  'health_events',
];

class Store extends ChangeNotifier {
  final bool demo;
  final http.Client _client = http.Client();
  final Map<String, List<Json>> data = {};
  List<Json> households = [];
  List<Json> members = [];
  String? householdId;
  bool loading = false;
  bool _disposed = false;
  int _refreshVersion = 0;
  String? error;
  Store({this.demo = false}) {
    if (demo) _seed();
  }
  List<Json> rows(String name) => data[name] ?? [];
  String get familyName =>
      households
          .where((r) => r['id'] == householdId)
          .map((r) => r['name'] as String)
          .firstOrNull ??
      'Sua família';
  bool get isOwner {
    final me = demo ? null : Supabase.instance.client.auth.currentUser?.id;
    final family = households.where((h) => h['id'] == householdId);
    return me != null && family.any((h) => h['owner_id'] == me);
  }

  Future<dynamic> request(String method, String path, [Json? body]) async {
    if (!configured) {
      throw Exception('Configure a conexão antes de salvar dados reais.');
    }
    var session = Supabase.instance.client.auth.currentSession;
    if (session == null) throw Exception('Entre na sua conta.');
    if (session.isExpired) {
      await Supabase.instance.client.auth.refreshSession();
      session = Supabase.instance.client.auth.currentSession;
    }
    final req = http.Request(
      method,
      Uri.parse('${apiUrl.replaceAll(RegExp(r'/$'), '')}/v1/$path'),
    );
    req.headers.addAll({
      'Authorization': 'Bearer ${session?.accessToken}',
      'Content-Type': 'application/json',
    });
    if (body != null) req.body = jsonEncode(body);
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(req).timeout(const Duration(seconds: 30)),
      );
    } on TimeoutException {
      throw Exception('O servidor demorou para responder. Tente novamente.');
    } on http.ClientException {
      throw Exception('Sem conexão com o servidor. Tente novamente.');
    }
    if (response.statusCode >= 400) {
      throw Exception(_errorText(response.body));
    }
    return response.body.isEmpty ? null : jsonDecode(response.body);
  }

  Future<List<Json>> _load(String resource, {String? familyId}) async {
    final all = <Json>[];
    for (var offset = 0; ; offset += 200) {
      final query = resource == 'households'
          ? '?offset=$offset'
          : '?household_id=$familyId&offset=$offset';
      final page = (await request('GET', 'data/$resource$query') as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      all.addAll(page);
      if (page.length < 200) return all;
    }
  }

  Future<List<Json>> _members(String? familyId) async {
    final result = await request('POST', 'rpc/list_members', {
      'p_household_id': familyId,
    });
    return (result as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> refresh() async {
    if (_disposed) return;
    if (demo) {
      notifyListeners();
      return;
    }
    loading = true;
    final version = ++_refreshVersion;
    error = null;
    notifyListeners();
    try {
      final families = await _load('households');
      if (_disposed || version != _refreshVersion) return;
      households = families;
      if (!households.any((e) => e['id'] == householdId)) {
        householdId = households.firstOrNull?['id'] as String?;
      }
      if (householdId != null) {
        final selected = householdId;
        final loaded = await Future.wait([
          for (final r in resources) _load(r, familyId: selected),
          _members(selected),
        ]);
        if (_disposed || version != _refreshVersion) return;
        for (var i = 0; i < resources.length; i++) {
          data[resources[i]] = loaded[i];
        }
        members = loaded.last;
      } else {
        data.clear();
        members = [];
      }
    } catch (e) {
      if (_disposed || version != _refreshVersion) return;
      data.clear();
      members = [];
      error = cleanError(e);
    }
    loading = false;
    notifyListeners();
  }

  Future<void> selectFamily(String id) async {
    householdId = id;
    data.clear();
    await refresh();
  }

  Future<void> save(
    String resource,
    Json values, {
    String? id,
    bool reload = true,
  }) async {
    if (demo) {
      final list = data.putIfAbsent(resource, () => []);
      if (id == null) {
        list.add({
          ...values,
          'id': DateTime.now().microsecondsSinceEpoch.toString(),
          'household_id': householdId,
        });
      } else {
        final i = list.indexWhere((e) => e['id'] == id);
        list[i] = {...list[i], ...values};
      }
      notifyListeners();
      return;
    }
    await request(
      id == null ? 'POST' : 'PATCH',
      'data/$resource${id == null ? '' : '/$id'}',
      {...values, if (id == null) 'household_id': householdId},
    );
    if (reload) await refresh();
  }

  Future<void> remove(String resource, String id) async {
    if (demo) {
      data[resource]?.removeWhere((e) => e['id'] == id);
      notifyListeners();
      return;
    }
    await request('DELETE', 'data/$resource/$id');
    await refresh();
  }

  Future<dynamic> rpc(String name, Json args) async {
    if (demo) {
      if (name == 'settle_entry') {
        data['settlements']!.removeWhere(
          (e) =>
              e['entry_id'] == args['p_entry_id'] &&
              e['occurrence'] == args['p_occurrence'],
        );
        if (args['p_paid'] == true) {
          final entry = rows(
            'entries',
          ).firstWhere((e) => e['id'] == args['p_entry_id']);
          data['settlements']!.add({
            'id': DateTime.now().microsecondsSinceEpoch.toString(),
            'entry_id': entry['id'],
            'occurrence': args['p_occurrence'],
            'amount_cents': entry['amount_cents'],
          });
        }
      } else if (name == 'buy_goal') {
        final g = rows('goals').firstWhere((e) => e['id'] == args['p_goal_id']);
        g['acquired'] = number(g, 'acquired') + (args['p_quantity'] as int);
        g['saved_cents'] =
            (number(g, 'saved_cents') - (args['p_cost_cents'] as int)).clamp(
              0,
              99999999999,
            );
        if ((args['p_cost_cents'] as int) > 0) {
          _demoExpense(
            g['title'] as String,
            args['p_cost_cents'] as int,
            args['p_date'] as String,
            'Enxoval',
          );
        }
      } else if (name == 'record_health_cost') {
        final e = rows(
          'health_events',
        ).firstWhere((e) => e['id'] == args['p_event_id']);
        e['expense_entry_id'] = _demoExpense(
          e['title'] as String,
          args['p_amount_cents'] as int,
          args['p_date'] as String,
          'Saúde',
        );
      } else {
        throw Exception('Essa ação exige uma conta real.');
      }
      notifyListeners();
      return null;
    }
    final result = await request('POST', 'rpc/$name', args);
    if (name == 'create_household' || name == 'accept_invite') {
      householdId = result as String?;
    }
    await refresh();
    return result;
  }

  String _demoExpense(String title, int amount, String date, String category) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    data['entries']!.add({
      'id': id,
      'title': title,
      'amount_cents': amount,
      'start_date': date,
      'recurrence': 'once',
      'kind': 'expense',
      'category': category,
    });
    data['settlements']!.add({
      'id': 's$id',
      'entry_id': id,
      'occurrence': date,
      'amount_cents': amount,
    });
    return id;
  }

  void _seed() {
    final now = DateTime.now();
    String day(int d) => iso(DateTime(now.year, now.month, d));
    householdId = 'demo';
    households = [
      {'id': 'demo', 'name': 'Família de exemplo'},
    ];
    data['entries'] = [
      {
        'id': '1',
        'title': 'Salário mensal',
        'kind': 'income',
        'category': 'Salário',
        'amount_cents': 650000,
        'start_date': day(5),
        'recurrence': 'monthly',
      },
      {
        'id': '2',
        'title': 'Renda do trabalho autônomo',
        'kind': 'income',
        'category': 'Trabalho',
        'amount_cents': 240000,
        'start_date': day(10),
        'recurrence': 'monthly',
      },
      {
        'id': '3',
        'title': 'Aluguel',
        'kind': 'expense',
        'category': 'Moradia',
        'amount_cents': 180000,
        'start_date': day(10),
        'recurrence': 'monthly',
      },
      {
        'id': '4',
        'title': 'Supermercado',
        'kind': 'expense',
        'category': 'Alimentação',
        'amount_cents': 120000,
        'start_date': day(15),
        'recurrence': 'monthly',
      },
      {
        'id': '5',
        'title': 'Internet e energia',
        'kind': 'expense',
        'category': 'Casa',
        'amount_cents': 42000,
        'start_date': day(20),
        'recurrence': 'monthly',
      },
      {
        'id': '6',
        'title': 'Ultrassom',
        'kind': 'expense',
        'category': 'Saúde',
        'amount_cents': 23000,
        'start_date': day(22),
        'recurrence': 'once',
      },
      {
        'id': '7',
        'title': 'Parcela do financiamento',
        'kind': 'expense',
        'category': 'Dívidas',
        'amount_cents': 60000,
        'start_date': day(25),
        'recurrence': 'monthly',
      },
    ];
    data['settlements'] = [
      {
        'id': 's1',
        'entry_id': '1',
        'occurrence': day(5),
        'amount_cents': 650000,
      },
      {
        'id': 's3',
        'entry_id': '3',
        'occurrence': day(10),
        'amount_cents': 180000,
      },
    ];
    data['goals'] = [
      {
        'id': 'g1',
        'title': 'Berço e colchão',
        'priority': 'essential',
        'target_cents': 140000,
        'saved_cents': 80000,
        'quantity': 1,
        'acquired': 0,
        'target_date': iso(now.add(const Duration(days: 90))),
        'notes': 'Conferir certificação e medidas.',
      },
      {
        'id': 'g2',
        'title': 'Roupas para os primeiros meses',
        'priority': 'essential',
        'target_cents': 60000,
        'saved_cents': 20000,
        'quantity': 20,
        'acquired': 5,
        'target_date': iso(now.add(const Duration(days: 120))),
      },
      {
        'id': 'g3',
        'title': 'Carrinho compacto',
        'priority': 'comfort',
        'target_cents': 180000,
        'saved_cents': 40000,
        'quantity': 1,
        'acquired': 0,
        'target_date': iso(now.add(const Duration(days: 150))),
      },
    ];
    data['debts'] = [
      {
        'id': 'd1',
        'title': 'Financiamento',
        'creditor': 'Exemplo',
        'balance_cents': 600000,
        'installment_cents': 60000,
        'due_day': 25,
        'notes': 'Parcela já cadastrada em Finanças.',
      },
    ];
    data['babies'] = [
      {
        'id': 'b1',
        'name': 'Nosso bebê',
        'due_date': iso(now.add(const Duration(days: 200))),
        'birth_date': null,
        'notes': '',
      },
    ];
    data['measurements'] = [];
    data['health_events'] = [
      {
        'id': 'h1',
        'baby_id': 'b1',
        'title': 'Consulta de pré-natal',
        'event_type': 'appointment',
        'event_date': iso(now.add(const Duration(days: 9))),
        'provider': 'Clínica de exemplo',
        'completed': false,
        'notes': '',
      },
    ];
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshVersion++;
    _client.close();
    super.dispose();
  }
}

String cleanError(Object e) => e.toString().replaceFirst('Exception: ', '');

String _errorText(String body) {
  try {
    final result = jsonDecode(body);
    final error = result is Map ? result['error'] : null;
    if (error is String) return error;
  } on FormatException {
    // Proxies and the host may answer with HTML, for example while waking up.
  }
  return 'Não foi possível concluir. Tente novamente.';
}
