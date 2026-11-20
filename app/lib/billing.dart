import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// The Plus product in the Play Console.
const plusProduct = 'ninho_plus';

/// The Ninho page on Google Play, where the web app sends people to buy Plus.
final playListing = Uri.parse(
  'https://play.google.com/store/apps/details?id=br.com.ninho.app',
);

/// Whether this build buys Plus itself: only the Android app, through Google
/// Play Billing. Plus is per account, so the web app shows it too.
bool get buysPlus => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// What Google Play gets as the obfuscated account id: a hash of the user id,
/// the same the API computes, so a purchase stays with the account that made
/// it without Google seeing the id itself.
String accountTag(String userId) => sha256
    .convert(utf8.encode('ninho-plus:${userId.toLowerCase()}'))
    .toString();

/// Sends a purchase to the server, which checks it with Google. Answers the
/// state the server recorded: purchased, pending or canceled.
typedef SendPurchase = Future<String> Function(String product, String token);

/// Google Play Billing for Plus. It listens to the purchase updates from the
/// start, as Google asks, because a purchase can finish after the app closed,
/// as a pending payment does. A purchase is finished (acknowledged) only once
/// the server recorded it; otherwise Google refunds it after three days.
class PlayBilling {
  PlayBilling({required this.send, required this.userId, InAppPurchase? iap})
    : _iap = iap ?? InAppPurchase.instance {
    _updates = _iap.purchaseStream.listen(
      (purchases) {
        for (final p in purchases) {
          unawaited(_handle(p));
        }
      },
      onError: (Object e) =>
          _finish('Não foi possível falar com a Google Play. Tente novamente.'),
    );
  }

  final InAppPurchase _iap;
  final SendPurchase send;
  final String userId;
  late final StreamSubscription<List<PurchaseDetails>> _updates;
  Completer<String>? _waiting;

  /// The price of Plus as Google Play shows it, in the person's currency.
  /// Null when Google Play does not answer or the product is not on sale.
  Future<String?> price() async {
    try {
      if (!await _iap.isAvailable()) return null;
      final found = await _iap.queryProductDetails({plusProduct});
      return found.productDetails.firstOrNull?.price;
    } catch (_) {
      return null;
    }
  }

  /// Opens Google Play's purchase sheet. Completes with the message for the
  /// person once the purchase ends, or throws when it could not start.
  Future<String> buy() async {
    if (_waiting != null) throw Exception('Uma compra já está em andamento.');
    if (!await _iap.isAvailable()) {
      throw Exception('A Google Play não está disponível neste aparelho.');
    }
    final found = await _iap.queryProductDetails({plusProduct});
    if (found.productDetails.isEmpty) {
      throw Exception('O Plus ainda não está à venda na Google Play.');
    }
    final waiting = _waiting = Completer<String>();
    final started = await _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(
        productDetails: found.productDetails.first,
        applicationUserName: accountTag(userId),
      ),
    );
    if (!started) {
      _waiting = null;
      throw Exception('Não foi possível abrir a compra. Tente novamente.');
    }
    return waiting.future.timeout(
      const Duration(minutes: 10),
      onTimeout: () {
        _waiting = null;
        return 'A compra ainda não terminou. O Plus aparece assim que ela for '
            'confirmada.';
      },
    );
  }

  /// Asks Google Play for the purchases of this Google account, to bring back
  /// a Plus bought before on this Ninho account.
  Future<String> restore() async {
    if (!await _iap.isAvailable()) {
      throw Exception('A Google Play não está disponível neste aparelho.');
    }
    final waiting = _waiting ??= Completer<String>();
    await _iap.restorePurchases(applicationUserName: accountTag(userId));
    // Google sends nothing when there is nothing to restore.
    return waiting.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        _waiting = null;
        return 'Nenhuma compra do Plus encontrada nesta conta da Google.';
      },
    );
  }

  Future<void> _handle(PurchaseDetails p) async {
    if (p.productID != plusProduct) return;
    switch (p.status) {
      case PurchaseStatus.pending:
        _finish(
          'Pagamento pendente. O Plus é liberado assim que a Google Play '
          'confirmar.',
        );
      case PurchaseStatus.canceled:
        _finish('Compra cancelada.');
      case PurchaseStatus.error:
        _finish('A compra não foi concluída. Tente novamente.');
      case PurchaseStatus.purchased || PurchaseStatus.restored:
        try {
          final state = await send(
            p.productID,
            p.verificationData.serverVerificationData,
          );
          if (state == 'purchased' && p.pendingCompletePurchase) {
            await _iap.completePurchase(p);
          }
          _finish(switch (state) {
            'purchased' => 'Pronto! O Ninho Plus está ativo.',
            'pending' =>
              'Pagamento pendente. O Plus é liberado assim que a Google Play '
                  'confirmar.',
            _ => 'Essa compra foi cancelada na Google Play.',
          });
        } catch (e) {
          // Not finished: Google delivers it again on the next launch or
          // restore, and the server gets another chance.
          _finish(e.toString().replaceFirst('Exception: ', ''));
        }
    }
  }

  void _finish(String message) {
    final waiting = _waiting;
    _waiting = null;
    if (waiting != null && !waiting.isCompleted) waiting.complete(message);
  }

  void dispose() => unawaited(_updates.cancel());
}
