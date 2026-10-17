import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:ninho/ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stands in for Google's SDKs, so the launch flow runs without a device.
class FakeBackend implements AdBackend {
  Future<bool> Function() consent = () async => true;
  ConsentStatus status = ConsentStatus.obtained;
  Future<void> Function() form = () async {};
  bool canRequest = true, privacy = false;
  Future<OpenAd?> Function() ad = () async => FakeAd();
  int refreshed = 0, asked = 0;
  final loads = <bool>[];
  OpenAd? loaded;

  @override
  Future<bool> refreshConsent() {
    refreshed++;
    return consent();
  }

  @override
  Future<ConsentStatus> consentStatus() async => status;
  @override
  Future<void> askConsent() {
    asked++;
    return form();
  }

  @override
  Future<bool> canRequestAds() async => canRequest;
  @override
  Future<bool> privacyOptionsRequired() async => privacy;
  @override
  Future<void> showPrivacyOptions() async {}
  @override
  Future<OpenAd?> load(String unit, {required bool nonPersonalized}) async {
    expect(unit, testAppOpenUnit);
    loads.add(nonPersonalized);
    return loaded = await ad();
  }
}

class FakeAd implements OpenAd {
  bool shown = false, disposed = false;
  @override
  Future<void> show({required VoidCallback onShown}) async {
    shown = true;
    onShown();
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

final past = DateTime.now().subtract(const Duration(minutes: 1));

Future<AdMobAds> launch(
  FakeBackend backend, {
  DateTime? next,
  Duration wait = const Duration(seconds: 2),
}) async {
  SharedPreferences.setMockInitialValues({
    if (next != null) nextAdKey: next.millisecondsSinceEpoch,
  });
  return await AdMobAds.create(backend: backend, wait: wait) as AdMobAds;
}

Future<DateTime> savedNext() async => DateTime.fromMillisecondsSinceEpoch(
  (await SharedPreferences.getInstance()).getInt(nextAdKey)!,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an ad is due only once its time comes', () {
    final now = DateTime(2026, 10, 17, 12);
    expect(adDue(now, null), isFalse);
    expect(adDue(now, now.add(const Duration(minutes: 1))), isFalse);
    expect(adDue(now, now), isTrue);
    expect(adDue(now, now.subtract(adInterval)), isTrue);
  });

  test('builds outside release use Google test unit', () {
    expect(appOpenUnit, testAppOpenUnit);
  });

  test('a new install opens without an ad and waits one interval', () async {
    final backend = FakeBackend();
    final before = DateTime.now();
    final ads = await launch(backend);
    expect(ads.coversLaunch, isFalse);
    await ads.start(blocked: () => false);
    expect(backend.refreshed, 1, reason: 'consent is checked on every launch');
    expect(backend.loads, isEmpty);
    expect(
      (await savedNext()).isBefore(before.add(adInterval)),
      isFalse,
      reason: 'the first ad waits a whole interval',
    );
  });

  test('before the interval ends there is no cover and no ad', () async {
    final backend = FakeBackend();
    final ads = await launch(
      backend,
      next: DateTime.now().add(const Duration(hours: 1)),
    );
    expect(ads.coversLaunch, isFalse);
    await ads.start(blocked: () => false);
    await Future<void>.delayed(Duration.zero);
    expect(backend.loads, isEmpty);
  });

  test(
    'a due launch shows a personalized ad and waits 4 h for the next',
    () async {
      final backend = FakeBackend();
      final ads = await launch(backend, next: past);
      expect(ads.coversLaunch, isTrue);
      await ads.start(blocked: () => false);
      expect(backend.loads, [false]);
      expect((backend.loaded! as FakeAd).shown, isTrue);
      expect(
        (await savedNext()).isAfter(
          DateTime.now().add(adInterval - const Duration(minutes: 1)),
        ),
        isTrue,
      );
    },
  );

  test('without a fresh consent answer only non-personalized ads are asked '
      'for', () async {
    final backend = FakeBackend()..consent = () async => false;
    await (await launch(backend, next: past)).start(blocked: () => false);
    expect(backend.loads, [true]);
    expect((backend.loaded! as FakeAd).shown, isTrue);
  });

  test(
    'without a consent message, as in Brazil, ads are not personalized',
    () async {
      final backend = FakeBackend()..status = ConsentStatus.notRequired;
      await (await launch(backend, next: past)).start(blocked: () => false);
      expect(backend.loads, [true]);
      expect((backend.loaded! as FakeAd).shown, isTrue);
    },
  );

  test('without any consent answer there is no ad', () async {
    final backend = FakeBackend()
      ..consent = (() async => false)
      ..canRequest = false;
    await (await launch(backend, next: past)).start(blocked: () => false);
    expect(backend.loads, isEmpty);
  });

  test('the consent message replaces the ad on that launch', () async {
    final message = Completer<void>();
    final backend = FakeBackend()
      ..status = ConsentStatus.required
      ..form = (() => message.future);
    final ads = await launch(backend, next: past);
    // The cover lifts before the message, which then goes over the app.
    await ads.start(blocked: () => false);
    expect(backend.asked, 1);
    expect(message.isCompleted, isFalse);
    message.complete();
    await Future<void>.delayed(Duration.zero);
    expect(backend.loads, isEmpty);
  });

  test('a failed ad opens the app at once', () async {
    final backend = FakeBackend()..ad = () async => null;
    final clock = Stopwatch()..start();
    await (await launch(backend, next: past)).start(blocked: () => false);
    expect(clock.elapsed, lessThan(const Duration(seconds: 1)));
    expect(backend.loads, [false]);
  });

  test('an ad that arrives after the deadline is thrown away', () async {
    final arrival = Completer<OpenAd?>();
    final backend = FakeBackend()..ad = (() => arrival.future);
    final ads = await launch(
      backend,
      next: past,
      wait: const Duration(milliseconds: 50),
    );
    await ads.start(blocked: () => false);
    final late = FakeAd();
    arrival.complete(late);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(late.shown, isFalse);
    expect(late.disposed, isTrue);
  });

  test('a consent answer that never comes does not hold the launch', () async {
    final backend = FakeBackend()..consent = () => Completer<bool>().future;
    final ads = await launch(
      backend,
      next: past,
      wait: const Duration(milliseconds: 50),
    );
    final clock = Stopwatch()..start();
    await ads.start(blocked: () => false);
    expect(clock.elapsed, lessThan(const Duration(seconds: 1)));
    expect(backend.loads, isEmpty, reason: 'past the deadline, nothing loads');
  });

  test('password recovery gets no ad', () async {
    final backend = FakeBackend();
    await (await launch(backend, next: past)).start(blocked: () => true);
    final ad = backend.loaded! as FakeAd;
    expect(ad.shown, isFalse);
    expect(ad.disposed, isTrue);
    expect(
      (await savedNext()).millisecondsSinceEpoch,
      past.millisecondsSinceEpoch,
      reason: 'a skipped ad does not count against the interval',
    );
  });

  test('the ad privacy options follow Google', () async {
    final backend = FakeBackend()..privacy = true;
    final ads = await launch(backend, next: past);
    expect(ads.privacyOptions.value, isFalse);
    await ads.start(blocked: () => false);
    expect(ads.privacyOptions.value, isTrue);
  });

  test('the privacy options show even when consent never answers', () async {
    final backend = FakeBackend()
      ..consent = (() => Completer<bool>().future)
      ..privacy = true;
    final ads = await launch(
      backend,
      next: past,
      wait: const Duration(milliseconds: 50),
    );
    await ads.start(blocked: () => false);
    expect(ads.privacyOptions.value, isTrue);
  });

  test('a failing SDK never holds the launch', () async {
    final backend = FakeBackend()
      ..consent = () async => throw Exception('SDK indisponível');
    await (await launch(backend, next: past)).start(blocked: () => false);
    expect(backend.loads, isEmpty);
  });
}
