import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Google's demo App Open unit. It only serves test ads.
const testAppOpenUnit = 'ca-app-pub-3940256099942544/9257395921';
const _releaseUnit = String.fromEnvironment('ADMOB_APP_OPEN_ID');

/// At most one app open ad per interval. A new install also waits one
/// interval, so nobody meets an ad on their first visits.
const adInterval = Duration(hours: 4);

/// How long a launch may wait for the consent check and the ad. Past it the
/// app opens, and an ad that arrives late is thrown away.
const adWait = Duration(seconds: 4);

/// Saved on the device: when the next app open ad may appear.
const nextAdKey = 'ninho.ads.next';

/// The unit to load: Google's test unit in debug and profile builds, and the
/// real one only in release builds that receive ADMOB_APP_OPEN_ID.
String? get appOpenUnit => !kReleaseMode
    ? testAppOpenUnit
    : _releaseUnit.isEmpty
    ? null
    : _releaseUnit;

/// Whether an app open ad may appear at [now]. [next] is when the next one is
/// allowed, and null on a new install.
bool adDue(DateTime now, DateTime? next) => next != null && !now.isBefore(next);

/// The ad side of the app. This base class shows nothing, which is what the
/// web, the tests and release builds without an ad unit get.
class Ads {
  const Ads();

  /// Whether this build shows ads at all.
  bool get enabled => false;

  /// Whether the launch waits behind a cover for an app open ad.
  bool get coversLaunch => false;

  /// Whether the app must offer the ad privacy options (consent regions).
  ValueListenable<bool> get privacyOptions => _noPrivacyOptions;

  /// Runs the consent check and, on a launch that [coversLaunch], the app
  /// open ad. Completes when the app can be shown, and never throws.
  /// [blocked] is read again right before the ad would appear.
  Future<void> start({required bool Function() blocked}) async {}

  Future<void> showPrivacyOptions() async {}
}

final _noPrivacyOptions = ValueNotifier(false);

/// The calls to Google's SDKs that the launch flow makes. Tests replace them.
abstract class AdBackend {
  /// Refreshes the consent information. False when Google did not answer.
  Future<bool> refreshConsent();
  Future<ConsentStatus> consentStatus();

  /// Shows Google's consent message if it is required.
  Future<void> askConsent();
  Future<bool> canRequestAds();
  Future<bool> privacyOptionsRequired();
  Future<void> showPrivacyOptions();

  /// Loads an app open ad. Null when none is available.
  Future<OpenAd?> load(String unit, {required bool nonPersonalized});
}

abstract class OpenAd {
  /// Shows the ad. [onShown] runs once it is on screen, and the future
  /// completes when it is closed or could not be shown.
  Future<void> show({required VoidCallback onShown});
  Future<void> dispose();
}

/// AdMob on Android: Google's consent message first, then at most one app
/// open ad per [adInterval], shown over the launch cover. Nothing here may
/// hold the app up: every wait has a deadline or ends in "no ad".
class AdMobAds extends Ads {
  AdMobAds._(
    this._backend,
    this._unit,
    this._prefs,
    this.coversLaunch,
    this._wait,
  );
  final AdBackend _backend;
  final String _unit;
  final SharedPreferences _prefs;
  final Duration _wait;
  final _privacy = ValueNotifier(false);

  @override
  final bool coversLaunch;

  @override
  bool get enabled => true;

  @override
  ValueListenable<bool> get privacyOptions => _privacy;

  /// The ads for this platform and build. [backend] and [wait] are for tests.
  static Future<Ads> create({AdBackend? backend, Duration? wait}) async {
    final unit = appOpenUnit;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const Ads();
    }
    if (unit == null) return const Ads();
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final saved = prefs.getInt(nextAdKey);
      if (saved == null) {
        await prefs.setInt(
          nextAdKey,
          now.add(adInterval).millisecondsSinceEpoch,
        );
      }
      final next = saved == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(saved);
      return AdMobAds._(
        backend ?? _GoogleAds(),
        unit,
        prefs,
        adDue(now, next),
        wait ?? adWait,
      );
    } catch (_) {
      return const Ads();
    }
  }

  @override
  Future<void> start({required bool Function() blocked}) {
    final cover = Completer<void>();
    void release() {
      if (!cover.isCompleted) cover.complete();
    }

    if (!coversLaunch) release();
    unawaited(
      _run(blocked, release).catchError((Object _) {}).whenComplete(release),
    );
    return cover.future;
  }

  Future<void> _run(bool Function() blocked, VoidCallback release) async {
    var expired = false;
    final deadline = Future<void>.delayed(_wait, () => expired = true);
    Future<T?> beforeDeadline<T>(Future<T> step) =>
        Future.any([step, deadline.then((_) => null)]);

    // Consent comes first, on every launch. Without an answer in time, the
    // choice Google saved on an earlier launch still applies.
    final consent = _backend.refreshConsent();
    final fresh =
        (coversLaunch ? await beforeDeadline(consent) : await consent) ?? false;
    if (fresh) {
      _privacy.value = await _backend.privacyOptionsRequired();
      if (await _backend.consentStatus() == ConsentStatus.required) {
        // The message goes over the app, and no ad follows it.
        release();
        if (!blocked()) await _backend.askConsent();
        _privacy.value = await _backend.privacyOptionsRequired();
        return;
      }
    }
    // Past the deadline the app is already open, so no ad is even requested.
    if (!coversLaunch || expired || !await _backend.canRequestAds()) return;

    // Without a fresh consent answer, only non-personalized ads are requested.
    final loading = _backend.load(_unit, nonPersonalized: !fresh);
    final ad = await beforeDeadline(loading);
    if (ad == null || expired) {
      unawaited(loading.then((late) => late?.dispose()));
      return;
    }
    final state = WidgetsBinding.instance.lifecycleState;
    if (blocked() || (state != null && state != AppLifecycleState.resumed)) {
      await ad.dispose();
      return;
    }
    // If Google never reports the ad as closed, the cover still goes away.
    await ad
        .show(onShown: _remember)
        .timeout(const Duration(minutes: 2), onTimeout: () {});
  }

  void _remember() => unawaited(
    _prefs.setInt(
      nextAdKey,
      DateTime.now().add(adInterval).millisecondsSinceEpoch,
    ),
  );

  @override
  Future<void> showPrivacyOptions() => _backend.showPrivacyOptions();
}

class _GoogleAds implements AdBackend {
  final _consent = ConsentInformation.instance;
  bool _started = false;

  @override
  Future<bool> refreshConsent() {
    final done = Completer<bool>();
    _consent.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () => done.complete(true),
      (_) => done.complete(false),
    );
    return done.future;
  }

  @override
  Future<ConsentStatus> consentStatus() => _consent.getConsentStatus();

  @override
  Future<void> askConsent() =>
      ConsentForm.loadAndShowConsentFormIfRequired((_) {});

  @override
  Future<bool> canRequestAds() => _consent.canRequestAds();

  @override
  Future<bool> privacyOptionsRequired() async =>
      await _consent.getPrivacyOptionsRequirementStatus() ==
      PrivacyOptionsRequirementStatus.required;

  @override
  Future<void> showPrivacyOptions() =>
      ConsentForm.showPrivacyOptionsForm((_) {});

  @override
  Future<OpenAd?> load(String unit, {required bool nonPersonalized}) async {
    if (!_started) {
      _started = true;
      // A family app with health records keeps mature ads out.
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(maxAdContentRating: MaxAdContentRating.pg),
      );
      MobileAds.instance.initialize().ignore();
    }
    final loaded = Completer<OpenAd?>();
    await AppOpenAd.load(
      adUnitId: unit,
      request: AdRequest(nonPersonalizedAds: nonPersonalized ? true : null),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) => loaded.complete(_GoogleOpenAd(ad)),
        onAdFailedToLoad: (_) => loaded.complete(null),
      ),
    );
    return loaded.future;
  }
}

class _GoogleOpenAd implements OpenAd {
  _GoogleOpenAd(this._ad);
  final AppOpenAd _ad;

  @override
  Future<void> show({required VoidCallback onShown}) async {
    final closed = Completer<void>();
    void close() {
      _ad.dispose();
      if (!closed.isCompleted) closed.complete();
    }

    _ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) => onShown(),
      onAdDismissedFullScreenContent: (_) => close(),
      onAdFailedToShowFullScreenContent: (_, _) => close(),
    );
    try {
      await _ad.show();
    } catch (_) {
      close();
    }
    await closed.future;
  }

  @override
  Future<void> dispose() => _ad.dispose();
}
