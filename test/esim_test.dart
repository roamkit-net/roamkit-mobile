import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roamkit_mobile/esim.dart';
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

  test('Android setup link matches the web carddata form', () {
    const link =
        'https://esimsetup.android.com/esim_qrcode_provisioning?carddata=LPA%3A1%24smdp.example%24CODE';
    expect(androidSetupLink(lpa: 'smdp.example', matchingId: 'CODE'), link);
    expect(androidSetupLink(lpa: r'LPA:1$smdp.example$CODE'), link);
    expect(androidSetupLink(lpa: '', matchingId: ''), isNull);
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

  testWidgets('Install eSIM opens the Android setup link', (tester) async {
    final seen = <String>[];
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
}) {
  return OwnedEsim(
    id: id,
    status: status,
    locationTitle: title,
    packageTitle: '',
    countryCode: 'HR',
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
