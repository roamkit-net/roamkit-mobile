import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roamkit_mobile/esim.dart';
import 'package:roamkit_mobile/esim_detail_api.dart';
import 'package:roamkit_mobile/esim_setup_screen.dart';
import 'package:roamkit_mobile/esims_screen.dart';
import 'package:roamkit_mobile/session.dart';
import 'package:roamkit_mobile/store_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSession.instance.signOut();
  });

  test('activation code keeps one GSMA form', () {
    expect(
      androidActivationCode(lpa: r'LPA:1$smdp.example$CODE'),
      r'1$smdp.example$CODE',
    );
    expect(
      androidActivationCode(lpa: 'smdp.example', matchingId: 'CODE'),
      r'1$smdp.example$CODE',
    );
  });

  test('Europe and Discover Global use catalog region icons', () {
    expect(regionIconSlug('Europe'), 'europe');
    expect(regionIconSlug('Discover Global'), 'global');
    expect(regionIconSlug('Croatia'), isNull);
  });

  test('Android setup link matches the web carddata form', () {
    const link =
        'https://esimsetup.android.com/esim_qrcode_provisioning?carddata=LPA%3A1%24smdp.example%24CODE';
    expect(androidSetupLink(lpa: 'smdp.example', matchingId: 'CODE'), link);
    expect(androidSetupLink(lpa: r'LPA:1$smdp.example$CODE'), link);
    expect(androidSetupLink(lpa: '', matchingId: ''), isNull);
  });

  test('Apple setup link matches the carddata form', () {
    const link =
        'https://esimsetup.apple.com/esim_qrcode_provisioning?carddata=LPA%3A1%24smdp.example%24CODE';
    expect(appleSetupLink(lpa: 'smdp.example', matchingId: 'CODE'), link);
    expect(appleSetupLink(lpa: r'LPA:1$smdp.example$CODE'), link);
    expect(
      appleSetupLink(
        lpa: r'LPA:1$consumer.e-sim.global$TN202606052058468D8811A3',
      ),
      'https://esimsetup.apple.com/esim_qrcode_provisioning?carddata=LPA%3A1%24consumer.e-sim.global%24TN202606052058468D8811A3',
    );
    expect(appleSetupLink(lpa: '', matchingId: ''), isNull);
  });

  testWidgets('logged-out My eSIMs asks for Log in', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: StoreScreen(initialLocations: [])),
    );

    await tester.tap(find.text('My eSIMs'));
    await tester.pumpAndSettle();

    expect(find.text('My eSIMs'), findsWidgets);
    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Active (1)'), findsNothing);
  });

  testWidgets('list groups Active, Expired, and Archived', (tester) async {
    SharedPreferences.setMockInitialValues({
      'roamkit_access_token': 'access',
      'roamkit_refresh_token': 'refresh',
      'roamkit_display_name': 'Ante',
    });
    await AppSession.instance.restore(refreshBalance: false);

    await tester.pumpWidget(
      MaterialApp(
        home: EsimsScreen(
          packageLoader: (_) async => [],
          loader: () async => [
            _esim(
              id: 1,
              title: 'Croatia',
              status: 'installation_started',
              issuedAt: '2026-10-10T00:00:00Z',
              iccid: '8910300000060613949',
              note: 'Japan trip',
            ),
            _esim(
              id: 2,
              title: 'Serbia',
              status: 'expired',
              issuedAt: '2026-10-11T00:00:00Z',
            ),
            _esim(
              id: 3,
              title: 'Germany',
              status: 'active',
              archivedAt: '2026-10-09T00:00:00Z',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Active (1)'), findsOneWidget);
    expect(find.text('Expired (1)'), findsOneWidget);
    expect(find.text('Archived (1)'), findsOneWidget);
    expect(find.textContaining('Croatia'), findsOneWidget);
    expect(find.text('1 GB · Usage not synced'), findsWidgets);
    expect(find.text('Installation Started'), findsOneWidget);
    expect(find.text('ICCID: 8910300000060613949'), findsOneWidget);
    expect(find.text('Note: Japan trip'), findsOneWidget);
    expect(find.text('Note: '), findsNWidgets(2));
    expect(find.text('Expired (0)'), findsNothing);
  });

  testWidgets('Discover Global shows the catalog image', (tester) async {
    SharedPreferences.setMockInitialValues({
      'roamkit_access_token': 'access',
      'roamkit_refresh_token': 'refresh',
      'roamkit_display_name': 'Ante',
    });
    await AppSession.instance.restore(refreshBalance: false);

    await tester.pumpWidget(
      MaterialApp(
        home: EsimsScreen(
          packageLoader: (_) async => [],
          loader: () async => [
            _esim(
              id: 8,
              title: 'Discover Global',
              status: 'in_use',
              countryCode: '',
            ),
          ],
          regionImage: (slug) async =>
              slug == 'global' ? 'https://example.com/global.png' : null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is NetworkImage &&
            (widget.image as NetworkImage).url ==
                'https://example.com/global.png',
      ),
      findsOneWidget,
    );
  });

  testWidgets('main card uses the latest active package expiry badge', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'roamkit_access_token': 'access',
      'roamkit_refresh_token': 'refresh',
      'roamkit_display_name': 'Ante',
    });
    await AppSession.instance.restore(refreshBalance: false);
    final now = DateTime.now().toUtc();

    await tester.pumpWidget(
      MaterialApp(
        home: EsimsScreen(
          loader: () async => [_esim(id: 9, title: 'Europe', status: 'in_use')],
          packageLoader: (_) async => [
            _package(expiresAt: now.add(const Duration(hours: 36))),
            _package(expiresAt: now.add(const Duration(hours: 216))),
            _package(
              status: 'expired',
              expiresAt: now.add(const Duration(days: 30)),
            ),
          ],
          regionImage: (_) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('9 days'), findsOneWidget);
    expect(find.text('7 days'), findsNothing);
  });

  testWidgets('search filters all sections by ICCID and Note', (tester) async {
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
            _esim(
              id: 10,
              title: 'Croatia',
              status: 'in_use',
              iccid: '8910300000000000010',
              note: 'Summer',
            ),
            _esim(
              id: 11,
              title: 'Germany',
              status: 'expired',
              archivedAt: '2026-10-09T00:00:00Z',
              iccid: '8910300000000000011',
              note: 'Work Trip',
            ),
          ],
          packageLoader: (_) async => [],
          regionImage: (_) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '000010');
    await tester.pump();
    expect(find.textContaining('Croatia'), findsOneWidget);
    expect(find.textContaining('Germany'), findsNothing);
    expect(find.text('Active (1)'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'work trip');
    await tester.pump();
    expect(find.textContaining('Croatia'), findsNothing);
    expect(find.textContaining('Germany'), findsOneWidget);
    expect(find.text('Archived (1)'), findsOneWidget);
    expect(find.text('Active (1)'), findsNothing);

    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pump();
    expect(find.text('No matching eSIMs.'), findsOneWidget);
  });

  testWidgets('Install eSIM opens the Android setup link', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final seen = <String>[];
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: EsimSetupScreen(
            esim: _esim(
              id: 2,
              title: 'Croatia',
              status: 'installation_started',
              lpa: 'smdp.example',
              matchingId: 'CODE',
              iccid: '8910300000060613949',
            ),
            installer: (code) async {
              seen.add(code);
              return null;
            },
          ),
        ),
      );

      expect(find.text('Set up your eSIM'), findsOneWidget);
      expect(find.text('ICCID: 8910300000060613949'), findsOneWidget);
      expect(find.text('Manual install'), findsOneWidget);
      expect(find.text('QR code'), findsOneWidget);
      expect(
        find.text('Data Roaming must be turned on for the service to work.'),
        findsOneWidget,
      );
      expect(find.text('smdp.example'), findsNothing);
      expect(find.text('CODE'), findsNothing);

      await tester.tap(find.text('Install eSIM'));
      await tester.pumpAndSettle();

      expect(seen, [
        'https://esimsetup.android.com/esim_qrcode_provisioning?carddata=LPA%3A1%24smdp.example%24CODE',
      ]);
      expect(find.text('Install eSIM'), findsOneWidget);
      expect(find.text('Manual install'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Install eSIM opens the Apple setup link on iOS', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final seen = <String>[];
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: EsimSetupScreen(
            esim: _esim(
              id: 2,
              title: 'Croatia',
              status: 'installation_started',
              lpa: r'LPA:1$consumer.e-sim.global$TN202606052058468D8811A3',
            ),
            installer: (code) async {
              seen.add(code);
              return null;
            },
          ),
        ),
      );

      await tester.tap(find.text('Install eSIM'));
      await tester.pumpAndSettle();

      expect(seen, [
        'https://esimsetup.apple.com/esim_qrcode_provisioning?carddata=LPA%3A1%24consumer.e-sim.global%24TN202606052058468D8811A3',
      ]);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Manual install copies the activation code without a QR', (
    tester,
  ) async {
    final copied = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: EsimSetupScreen(
          esim: _esim(
            id: 2,
            title: 'Croatia',
            status: 'installation_started',
            lpa: 'smdp.example',
            matchingId: 'CODE',
            qrcodeUrl: 'https://example.com/qr.png',
          ),
          copier: (code) async => copied.add(code),
        ),
      ),
    );

    await tester.tap(find.text('Manual install'));
    await tester.pumpAndSettle();

    expect(copied, [r'LPA:1$smdp.example$CODE']);
    expect(find.text(r'LPA:1$smdp.example$CODE'), findsOneWidget);
    expect(find.text('Copied'), findsOneWidget);
    expect(find.text('1. Connections'), findsOneWidget);
    expect(find.text('6. Done'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is NetworkImage,
      ),
      findsNothing,
    );

    await tester.tap(find.text(r'LPA:1$smdp.example$CODE'));
    await tester.pumpAndSettle();
    expect(copied, [r'LPA:1$smdp.example$CODE', r'LPA:1$smdp.example$CODE']);
  });

  testWidgets('QR code shows the image', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EsimSetupScreen(
          esim: _esim(
            id: 2,
            title: 'Croatia',
            status: 'installation_started',
            lpa: 'smdp.example',
            matchingId: 'CODE',
            qrcodeUrl: 'https://example.com/qr.png',
            iccid: '8910300000060613949',
          ),
        ),
      ),
    );

    await tester.tap(find.text('QR code'));
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is NetworkImage,
      ),
      findsOneWidget,
    );
    expect(find.text('ICCID: 8910300000060613949'), findsOneWidget);
    expect(find.text('Activation code'), findsNothing);
    expect(find.text('1. Connections'), findsNothing);
  });
}

AppliedPackage _package({
  String status = 'active',
  required DateTime expiresAt,
}) {
  return AppliedPackage(
    id: expiresAt.toIso8601String(),
    kind: 'esim',
    status: status,
    dataAllowance: '300 MB',
    validityDays: 7,
    isUnlimited: false,
    createdAt: null,
    activatedAt: null,
    expiresAt: expiresAt.toIso8601String(),
    paidUsd: null,
    currency: 'USD',
  );
}

OwnedEsim _esim({
  required int id,
  required String title,
  required String status,
  String? issuedAt,
  String? archivedAt,
  String lpa = '',
  String matchingId = '',
  String qrcodeUrl = '',
  String iccid = '',
  String note = '',
  String countryCode = 'HR',
}) {
  return OwnedEsim(
    id: id,
    status: status,
    locationTitle: title,
    packageTitle: '',
    countryCode: countryCode,
    dataAllowance: '1 GB',
    validityDays: 7,
    usageRemainingMb: null,
    usageTotalMb: null,
    usageIsUnlimited: false,
    usageExpiredAt: null,
    issuedAt: issuedAt,
    createdAt: issuedAt,
    archivedAt: archivedAt,
    lpa: lpa,
    matchingId: matchingId,
    qrcodeUrl: qrcodeUrl,
    iccid: iccid,
    note: note,
  );
}
