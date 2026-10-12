import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roamkit_mobile/catalog.dart';
import 'package:roamkit_mobile/esim.dart';
import 'package:roamkit_mobile/esim_detail_api.dart';
import 'package:roamkit_mobile/esim_detail_screen.dart';
import 'package:roamkit_mobile/esims_screen.dart';
import 'package:roamkit_mobile/orders_api.dart';
import 'package:roamkit_mobile/session.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSession.instance.signOut();
  });

  Future<void> pumpDetail(
    WidgetTester tester,
    OwnedEsim esim, {
    List<AppliedPackage> packages = const [],
    List<TopupOffer>? topups,
    List<String>? notes,
  }) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: EsimDetailScreen(
          esim: esim,
          api: _api(packages: packages, notes: notes, topups: topups),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('purchased keeps install and hides empty packages', (
    tester,
  ) async {
    await pumpDetail(tester, _esim(status: 'installation_started'));

    expect(find.text('ICCID: 8910300000060613949'), findsOneWidget);
    expect(find.text('Install eSIM'), findsOneWidget);
    expect(find.text('Manual install'), findsOneWidget);
    expect(find.text('Packages'), findsNothing);
    expect(find.text('Available top-ups'), findsOneWidget);
    expect(find.text('1 GB Top-up'), findsOneWidget);
    expect(find.text('Renew'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
  });

  testWidgets('in use shows packages with the data bar and no install', (
    tester,
  ) async {
    await pumpDetail(
      tester,
      _esim(status: 'in_use', remainingMb: 395, totalMb: 500),
      packages: [
        _package(status: 'active'),
        _package(status: 'expired'),
      ],
    );

    expect(find.text('Install eSIM'), findsNothing);
    expect(find.byKey(const Key('esim-usage-bar')), findsOneWidget);
    expect(find.text('Data left: 395 MB (79%)'), findsOneWidget);
    expect(find.text('Available packages'), findsOneWidget);
    expect(find.text('Previous packages'), findsOneWidget);
    expect(find.text('Renew'), findsOneWidget);
  });

  testWidgets('expired shows previous packages without bar or install', (
    tester,
  ) async {
    await pumpDetail(
      tester,
      _esim(status: 'expired', remainingMb: 0, totalMb: 500),
      packages: [_package(status: 'expired')],
    );

    expect(find.text('Install eSIM'), findsNothing);
    expect(find.byKey(const Key('esim-usage-bar')), findsNothing);
    expect(find.text('Previous packages'), findsOneWidget);
    expect(find.text('Available packages'), findsNothing);

    await tester.tap(find.text('Unlimited · 3 days'));
    await tester.pumpAndSettle();
    expect(find.text('Amount'), findsOneWidget);
    expect(find.text(r'$3.30 USD'), findsOneWidget);
  });

  testWidgets('Notes saves the trimmed note', (tester) async {
    final notes = <String>[];
    await pumpDetail(tester, _esim(status: 'expired'), notes: notes);

    await tester.enterText(find.byType(TextField).last, '  Japan trip ');
    await tester.pump();
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    expect(notes, ['Japan trip']);
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('in use card fills light blue by data left', (tester) async {
    SharedPreferences.setMockInitialValues({
      'roamkit_access_token': 'access',
      'roamkit_refresh_token': 'refresh',
      'roamkit_display_name': 'Ante',
    });
    await AppSession.instance.restore(refreshBalance: false);

    await tester.pumpWidget(
      MaterialApp(
        home: EsimsScreen(
          loader: () async => [
            _esim(id: 4, status: 'in_use', remainingMb: 395, totalMb: 500),
            _esim(id: 35, status: 'expired', remainingMb: 0, totalMb: 500),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    Gradient? fill(int id) {
      final ink = tester.widget<Ink>(find.byKey(ValueKey('esim-card-$id')));
      return (ink.decoration as BoxDecoration?)?.gradient;
    }

    final inUse = fill(4) as LinearGradient;
    expect(inUse.stops, [0, 0.79, 0.79, 1]);
    expect(inUse.colors.last, Colors.white);
    expect(fill(35), isNull);
  });

  test('top-up offer keeps the list price from the API', () {
    final offer = TopupOffer.fromJson({
      'id': 'pkg',
      'title': '3 GB - 30 days',
      'data_allowance': '3 GB',
      'validity_days': 30,
      'price_usd': '3.00',
      'list_price_usd': '11.00',
      'is_unlimited': false,
    });

    expect(offer.listPriceUsd, '11.00');
    expect(offer.toCatalogPackage().listPriceUsd, '11.00');
  });

  testWidgets('discounted top-up shows the struck list price', (tester) async {
    await pumpDetail(
      tester,
      _esim(status: 'in_use'),
      topups: const [
        TopupOffer(
          id: 'topup-3gb',
          title: '3 GB - 30 days',
          dataAllowance: '3 GB',
          validityDays: 30,
          priceUsd: '3.00',
          listPriceUsd: '11.00',
          isUnlimited: false,
          planType: 'topup',
        ),
        TopupOffer(
          id: 'topup-1gb',
          title: '1 GB Top-up',
          dataAllowance: '1 GB',
          validityDays: 7,
          priceUsd: '4.50',
          isUnlimited: false,
          planType: 'topup',
        ),
      ],
    );

    expect(find.text('11.00 credits'), findsOneWidget);
    expect(find.text('3.00 credits'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('11.00 credits')).style?.decoration,
      TextDecoration.lineThrough,
    );
    expect(find.text('4.50 credits'), findsOneWidget);

    await tester.tap(find.text('Buy').first);
    await tester.pumpAndSettle();

    expect(find.text('Confirm purchase'), findsNWidgets(2));
    expect(find.text('11.00 credits'), findsNWidgets(2));
    expect(find.text('3.00 credits'), findsNWidgets(2));
    expect(
      tester
          .widgetList<Text>(find.text('11.00 credits'))
          .every(
            (text) => text.style?.decoration == TextDecoration.lineThrough,
          ),
      isTrue,
    );
  });
}

EsimDetailApi _api({
  List<AppliedPackage> packages = const [],
  List<TopupOffer>? topups,
  List<String>? notes,
}) {
  return EsimDetailApi(
    packages: (_) async => packages,
    usage: (_) async =>
        const EsimUsage(remainingMb: 395, totalMb: 500, isUnlimited: false),
    topups: (_) async =>
        topups ??
        const [
          TopupOffer(
            id: 'topup-1gb',
            title: '1 GB Top-up',
            dataAllowance: '1 GB',
            validityDays: 7,
            priceUsd: '4.50',
            isUnlimited: false,
            planType: 'topup',
          ),
        ],
    buyTopup: (_, _, _) async => const OrderOutcome.success(),
    autoTopup: (_) async => const AutoTopupLoad(),
    saveAutoTopup: (_, _, _) async => throw UnimplementedError(),
    deleteAutoTopup: (_, _) async {},
    saveNote: (_, note) async {
      notes?.add(note);
      return note;
    },
    display: () async => BillingDisplay.fallback,
  );
}

AppliedPackage _package({required String status}) {
  return AppliedPackage(
    id: 'pkg-$status',
    kind: 'esim',
    status: status,
    dataAllowance: '',
    validityDays: 3,
    isUnlimited: true,
    createdAt: '2026-09-13T19:29:00Z',
    activatedAt: '2026-09-13T19:34:00Z',
    expiresAt: '2026-09-16T19:34:00Z',
    paidUsd: '3.30',
    currency: 'USD',
  );
}

OwnedEsim _esim({
  int id = 7,
  required String status,
  int? remainingMb,
  int? totalMb,
}) {
  return OwnedEsim(
    id: id,
    status: status,
    locationTitle: 'Croatia',
    packageTitle: '',
    countryCode: 'HR',
    dataAllowance: '1 GB',
    validityDays: 7,
    usageRemainingMb: remainingMb,
    usageTotalMb: totalMb,
    usageIsUnlimited: false,
    usageExpiredAt: null,
    issuedAt: '2026-10-10T00:00:00Z',
    createdAt: '2026-10-10T00:00:00Z',
    archivedAt: null,
    lpa: 'smdp.example',
    matchingId: 'CODE',
    qrcodeUrl: '',
    iccid: '8910300000060613949',
  );
}
