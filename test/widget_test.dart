import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roamkit_mobile/auth_sheet.dart';
import 'package:roamkit_mobile/catalog.dart';
import 'package:roamkit_mobile/google_auth.dart';
import 'package:roamkit_mobile/location_screen.dart';
import 'package:roamkit_mobile/orders_api.dart';
import 'package:roamkit_mobile/session.dart';
import 'package:roamkit_mobile/signup_api.dart';
import 'package:roamkit_mobile/store_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSession.instance.signOut();
  });
  testWidgets('Store shows the catalog price in USDT', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: StoreScreen(
          initialDisplay: BillingDisplay(symbol: 'USDT', displayDecimals: 2),
          initialLocations: [
            CatalogLocation(
              slug: 'croatia',
              title: 'Croatia',
              countryCode: '',
              coverageType: 'local',
              imageUrl: '',
              isPopular: true,
              minPriceUsd: '4.00',
              coveredCountryCodes: [],
            ),
          ],
        ),
      ),
    );

    expect(find.text('Store'), findsWidgets);
    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Croatia'), findsOneWidget);
    expect(find.text('4.00 USDT'), findsOneWidget);
    expect(find.textContaining('€'), findsNothing);
  });

  testWidgets('tapping a country opens its packages', (tester) async {
    const display = BillingDisplay(symbol: 'USDT', displayDecimals: 2);
    await tester.pumpWidget(
      MaterialApp(
        home: StoreScreen(
          initialDisplay: display,
          initialLocations: const [
            CatalogLocation(
              slug: 'croatia',
              title: 'Croatia',
              countryCode: '',
              coverageType: 'local',
              imageUrl: '',
              isPopular: true,
              minPriceUsd: '4.00',
              coveredCountryCodes: [],
            ),
          ],
          detailLoader: (slug) async {
            return LocationDetailData(
              coverageType: 'local',
              coverages: const [
                LocationCoverage(
                  code: 'HR',
                  name: 'Croatia',
                  networks: [
                    CoverageNetwork(name: 'Telemach', types: ['5G']),
                    CoverageNetwork(name: 'A1', types: ['5G']),
                  ],
                ),
              ],
              packages: [
                _plan(id: '1gb', allowance: '1 GB', days: 7, price: '4.00'),
                _plan(
                  id: 'unl',
                  allowance: 'Unlimited',
                  days: 3,
                  price: '6.40',
                  listPrice: '9.50',
                  unlimited: true,
                ),
              ],
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Croatia'));
    await tester.pumpAndSettle();

    expect(find.text('Choose your package'), findsOneWidget);
    expect(find.text('Fixed data'), findsOneWidget);
    expect(find.text('Telemach'), findsOneWidget);
    expect(find.text('1 other'), findsOneWidget);
    expect(find.text('1 GB'), findsOneWidget);
    expect(find.text('4.00 USDT'), findsWidgets);
    expect(find.text('9.50 USDT'), findsNothing);
    expect(find.textContaining('€'), findsNothing);

    await tester.tap(find.text('Unlimited'));
    await tester.pumpAndSettle();
    expect(find.text('1 GB'), findsNothing);
    expect(find.text('6.40 USDT'), findsOneWidget);
    expect(find.text('9.50 USDT'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('9.50 USDT')).style?.decoration,
      TextDecoration.lineThrough,
    );

    await tester.tap(find.text('6.40 USDT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buy now'));
    await tester.pumpAndSettle();
    expect(find.text('Log in with'), findsOneWidget);
    expect(find.text('Confirm purchase'), findsNothing);
  });

  testWidgets('Profile shows Log in and Sign up when logged out', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: StoreScreen(
          initialLocations: [
            CatalogLocation(
              slug: 'croatia',
              title: 'Croatia',
              countryCode: '',
              coverageType: 'local',
              imageUrl: '',
              isPopular: true,
              minPriceUsd: '4.00',
              coveredCountryCodes: [],
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    expect(find.text('Sign up'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Croatia'), findsNothing);

    await tester.tap(find.text('Store'));
    await tester.pumpAndSettle();
    expect(find.text('Croatia'), findsOneWidget);
    expect(find.text('Sign up'), findsNothing);
  });

  testWidgets('auth sheet shows login and sign-up fields', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: StoreScreen(initialLocations: [])),
    );

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    expect(find.text('Log in with'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Forgot password'), findsOneWidget);
    expect(find.text('Log in with SSO'), findsOneWidget);
    expect(find.bySemanticsLabel('Google'), findsOneWidget);
    expect(find.bySemanticsLabel('Facebook'), findsOneWidget);
    expect(find.textContaining('Airalo'), findsNothing);

    await tester.tap(find.text('Sign up').last);
    await tester.pumpAndSettle();

    expect(find.text('First name'), findsOneWidget);
    expect(find.text('Last name (Optional)'), findsOneWidget);
    expect(find.text('Minimum 8 characters'), findsNothing);
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Minimum 8 characters'), findsNothing);
    expect(find.text('Referral or voucher code'), findsOneWidget);
    expect(
      find.text("I'd like to receive promotional emails."),
      findsOneWidget,
    );
    expect(find.text('Agree and sign up'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'a');
    await tester.pumpAndSettle();
    expect(find.text('Minimum 8 characters'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('Continue with SSO'), findsOneWidget);
    expect(find.textContaining('RoamKit account'), findsOneWidget);
  });

  test('signup errors stay on the field that failed', () {
    final failure = signupFailureFromBody(
      '{"first_name":["This field is required."],"email":["This field is required."],"password":["This field is required."]}',
    );

    expect(failure.message, isEmpty);
    expect(failure.fields['first_name'], 'Enter your first name.');
    expect(failure.fields['email'], 'Enter your email.');
    expect(failure.fields['password'], 'Enter a password.');
  });

  test('signup detail stays a single banner', () {
    final failure = signupFailureFromBody(
      '{"detail":"Check your email.","email":["Enter a valid email address."]}',
    );

    expect(failure.message, 'Check your email.');
    expect(failure.fields['email'], 'Enter a valid email address.');
  });

  testWidgets('auth sheet sits above the system navigation bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(bottom: 80);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewPadding);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AuthSheet(signUp: true))),
    );
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Padding &&
            widget.padding == const EdgeInsets.only(bottom: 80),
      ),
      findsOneWidget,
    );
  });

  testWidgets('invalid email shows a hint after leaving the field', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AuthSheet(signUp: true))),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Email'), '');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(find.text('Enter a valid email.'), findsNothing);

    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'antevitalgroupsa.com',
    );
    await tester.pump();
    expect(find.text('Enter a valid email.'), findsNothing);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(find.text('Enter a valid email.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'ante@vitalgroupsa.com',
    );
    await tester.pump();
    expect(find.text('Enter a valid email.'), findsNothing);
  });

  testWidgets('Google sign-in shows the API error on the sheet', (
    tester,
  ) async {
    final originalReader = readGoogleAccount;
    final originalExchange = exchangeGoogleCredential;
    addTearDown(() {
      readGoogleAccount = originalReader;
      exchangeGoogleCredential = originalExchange;
    });
    readGoogleAccount = () async => const GoogleAccountCredential(
      idToken: 'google-id-token',
      displayName: 'Ada',
    );
    exchangeGoogleCredential = (_) async {
      throw SignupFailure('This account is disabled.');
    };

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AuthSheet(signUp: false))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Google'));
    await tester.pump();

    expect(find.text('This account is disabled.'), findsOneWidget);
    expect(AppSession.instance.isSignedIn, isFalse);
  });

  testWidgets('log in stays disabled until email and password are filled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AuthSheet(signUp: false))),
    );
    await tester.pumpAndSettle();

    InkWell button() =>
        tester.widget<InkWell>(find.widgetWithText(InkWell, 'Log in'));

    expect(button().onTap, isNull);

    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'ante@vitalgroupsa.com',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'secret',
    );
    await tester.pump();

    expect(button().onTap, isNotNull);
  });

  testWidgets('signed-in store shows the balance instead of Log in', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'roamkit_access_token': 'access',
      'roamkit_refresh_token': 'refresh',
      'roamkit_display_name': 'Ante',
      'roamkit_balance': '12.50',
    });
    await AppSession.instance.restore(refreshBalance: false);

    await tester.pumpWidget(
      const MaterialApp(
        home: StoreScreen(
          initialDisplay: BillingDisplay(symbol: 'USDT', displayDecimals: 2),
          initialLocations: [],
        ),
      ),
    );

    expect(find.text('12.50 USDT'), findsOneWidget);
    expect(find.text('Log in'), findsNothing);

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Ante'), findsOneWidget);
    expect(find.text('Logout'), findsOneWidget);

    await tester.tap(find.text('Logout'));
    await tester.pumpAndSettle();
    expect(find.text('Sign up'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
    expect(AppSession.instance.isSignedIn, isFalse);
  });

  group('purchase', () {
    const display = BillingDisplay(symbol: 'USDT', displayDecimals: 2);

    Future<void> signIn() async {
      SharedPreferences.setMockInitialValues({
        'roamkit_access_token': 'access',
        'roamkit_refresh_token': 'refresh',
        'roamkit_display_name': 'Ante',
        'roamkit_balance': '100.00',
      });
      await AppSession.instance.restore(refreshBalance: false);
    }

    Future<void> openSheet(WidgetTester tester, OrderSender sender) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LocationScreen(
            slug: 'croatia',
            title: 'Croatia',
            display: display,
            orderSender: sender,
            preview: LocationDetailData(
              coverageType: 'local',
              coverages: const [],
              packages: [
                _plan(id: '1gb', allowance: '1 GB', days: 7, price: '2.65'),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('1 GB'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Buy now'));
      await tester.pumpAndSettle();
    }

    testWidgets('confirm sheet shows the plan and Cancel sends nothing', (
      tester,
    ) async {
      await signIn();
      var calls = 0;
      await openSheet(tester, (id, key) async {
        calls += 1;
        return const OrderOutcome.success();
      });

      expect(find.text('Confirm purchase'), findsNWidgets(2));
      expect(find.text('1 GB - 7 days'), findsOneWidget);
      expect(find.text('7 days'), findsWidgets);
      expect(find.text('2.65 USDT'), findsWidgets);
      expect(find.text('100.00 USDT'), findsOneWidget);
      expect(
        find.textContaining('Balance is shown for reference.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('1 GB - 7 days'), findsNothing);
      expect(calls, 0);
    });

    testWidgets('confirm buys the plan and shows Purchase complete', (
      tester,
    ) async {
      await signIn();
      final keys = <String>[];
      await openSheet(tester, (id, key) async {
        keys.add(key);
        return const OrderOutcome.success();
      });

      await tester.tap(find.text('Confirm purchase').last);
      await tester.pumpAndSettle();

      expect(keys, hasLength(1));
      expect(keys.single, startsWith('order-'));
      expect(find.text('1 GB - 7 days'), findsNothing);
      expect(find.text('Purchase complete.'), findsOneWidget);
    });

    testWidgets('402 shows the missing balance and blocks Confirm', (
      tester,
    ) async {
      await signIn();
      var calls = 0;
      await openSheet(tester, (id, key) async {
        calls += 1;
        return const OrderOutcome.insufficient(missing: '14.5');
      });

      await tester.tap(find.text('Confirm purchase').last);
      await tester.pumpAndSettle();
      expect(
        find.text('Not enough balance. You need 14.50 USDT more.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Confirm purchase').last);
      await tester.pumpAndSettle();
      expect(calls, 1);
    });

    testWidgets('a retry after an error reuses the same key', (tester) async {
      await signIn();
      final keys = <String>[];
      await openSheet(tester, (id, key) async {
        keys.add(key);
        return keys.length == 1
            ? const OrderOutcome.failed('Unable to complete purchase.')
            : const OrderOutcome.success();
      });

      await tester.tap(find.text('Confirm purchase').last);
      await tester.pumpAndSettle();
      expect(find.text('Unable to complete purchase.'), findsOneWidget);

      await tester.tap(find.text('Confirm purchase').last);
      await tester.pumpAndSettle();
      expect(keys, hasLength(2));
      expect(keys[1], keys[0]);
      expect(find.text('Purchase complete.'), findsOneWidget);
    });
  });
}

CatalogPackage _plan({
  required String id,
  required String allowance,
  required int days,
  required String price,
  bool unlimited = false,
  String listPrice = '',
}) {
  return CatalogPackage(
    id: id,
    dataAllowance: allowance,
    validityDays: days,
    priceUsd: price,
    listPriceUsd: listPrice,
    isUnlimited: unlimited,
    planType: 'data',
  );
}
