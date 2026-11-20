import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:ninho/billing.dart';

const user = 'd2717c73-3a3a-4a24-9a10-8053a7e5d771';

class FakePlay implements InAppPurchase {
  final updates = StreamController<List<PurchaseDetails>>.broadcast();
  final completed = <String>[];
  String? boughtFor;
  bool listed = true;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => updates.stream;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async =>
      ProductDetailsResponse(
        productDetails: [
          if (listed)
            ProductDetails(
              id: plusProduct,
              title: 'Ninho Plus',
              description: '',
              price: r'R$ 10,00',
              rawPrice: 10,
              currencyCode: 'BRL',
            ),
        ],
        notFoundIDs: listed ? [] : ids.toList(),
      );
  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    boughtFor = purchaseParam.applicationUserName;
    return true;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async =>
      completed.add(purchase.verificationData.serverVerificationData);
  @override
  Future<void> restorePurchases({String? applicationUserName}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PurchaseDetails purchase(String token, PurchaseStatus status) =>
    PurchaseDetails(
      productID: plusProduct,
      verificationData: PurchaseVerificationData(
        localVerificationData: '{}',
        serverVerificationData: token,
        source: 'google_play',
      ),
      transactionDate: '0',
      status: status,
    )..pendingCompletePurchase = true;

void main() {
  test('the account tag is the one the API computes', () {
    // Same vector as TestAccountTag in backend/internal/api/plus_test.go.
    expect(
      accountTag(user.toUpperCase()),
      'ff5d845404b541036a69263de085205eec5ba006fa5e3b083479cae0671b7544',
    );
  });

  test('a purchase is finished only after the server records it', () async {
    final play = FakePlay();
    final sent = <String>[];
    var answer = 'purchased';
    final billing = PlayBilling(
      userId: user,
      iap: play,
      send: (product, token) async {
        sent.add(token);
        if (answer == 'fail') throw Exception('Sem conexão com o servidor.');
        return answer;
      },
    );
    final bought = billing.buy();
    await Future<void>.delayed(Duration.zero);
    expect(play.boughtFor, accountTag(user));
    play.updates.add([purchase('token-0001', PurchaseStatus.purchased)]);
    expect(await bought, 'Pronto! O Ninho Plus está ativo.');
    expect(play.completed, ['token-0001']);

    // The server could not record it: Google keeps it unfinished and sends it
    // again later.
    answer = 'fail';
    final again = billing.buy();
    await Future<void>.delayed(Duration.zero);
    play.updates.add([purchase('token-0002', PurchaseStatus.purchased)]);
    expect(await again, 'Sem conexão com o servidor.');
    expect(play.completed, ['token-0001']);

    final pending = billing.buy();
    await Future<void>.delayed(Duration.zero);
    play.updates.add([purchase('token-0003', PurchaseStatus.pending)]);
    expect(await pending, startsWith('Pagamento pendente'));
    expect(sent, ['token-0001', 'token-0002']);

    // A purchase restored or finished while nobody waits is still recorded.
    answer = 'purchased';
    play.updates.add([purchase('token-0003', PurchaseStatus.purchased)]);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(play.completed, ['token-0001', 'token-0003']);
    billing.dispose();
  });

  test('a product missing from Google Play says so', () async {
    final play = FakePlay()..listed = false;
    final billing = PlayBilling(
      userId: user,
      iap: play,
      send: (_, _) async => 'purchased',
    );
    await expectLater(
      billing.buy(),
      throwsA(
        predicate((e) => e.toString().contains('ainda não está à venda')),
      ),
    );
    billing.dispose();
  });
}
