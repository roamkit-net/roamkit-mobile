import 'package:flutter_test/flutter_test.dart';
import 'package:roamkit_mobile/catalog.dart';

CatalogLocation _location({
  required String slug,
  required String title,
  required String countryCode,
  required String coverageType,
  List<String> covered = const [],
  bool popular = false,
  String? price = '4.00',
}) {
  return CatalogLocation(
    slug: slug,
    title: title,
    countryCode: countryCode,
    coverageType: coverageType,
    imageUrl: '',
    isPopular: popular,
    minPriceUsd: price,
    coveredCountryCodes: covered,
  );
}

CatalogPackage _package({
  required String id,
  required String allowance,
  required int days,
  required String price,
  bool unlimited = false,
  String planType = 'data',
}) {
  return CatalogPackage(
    id: id,
    dataAllowance: allowance,
    validityDays: days,
    priceUsd: price,
    isUnlimited: unlimited,
    planType: planType,
  );
}

void main() {
  final catalog = [
    _location(
      slug: 'croatia',
      title: 'Croatia',
      countryCode: 'HR',
      coverageType: 'local',
      popular: true,
    ),
    _location(
      slug: 'europe',
      title: 'Europe',
      countryCode: '',
      coverageType: 'regional',
      covered: ['HR', 'DE'],
      price: '11.00',
    ),
    _location(
      slug: 'global',
      title: 'Global',
      countryCode: '',
      coverageType: 'global',
      covered: ['HR'],
      price: '20.00',
    ),
  ];

  test('popular tab keeps is_popular rows only', () {
    final rows = locationsForTab(catalog, 'popular');
    expect(rows.map((row) => row.slug), ['croatia']);
  });

  test('popular tab ranks Croatia like the web', () {
    final locations = [
      _location(
        slug: 'germany',
        title: 'Germany',
        countryCode: 'DE',
        coverageType: 'local',
        popular: true,
      ),
      _location(
        slug: 'croatia',
        title: 'Croatia',
        countryCode: 'HR',
        coverageType: 'local',
        popular: true,
      ),
      _location(
        slug: 'bosnia-and-herzegovina',
        title: 'Bosnia and Herzegovina',
        countryCode: 'BA',
        coverageType: 'local',
        popular: true,
      ),
      _location(
        slug: 'montenegro',
        title: 'Montenegro',
        countryCode: 'ME',
        coverageType: 'local',
      ),
      _location(
        slug: 'serbia',
        title: 'Serbia',
        countryCode: 'RS',
        coverageType: 'local',
        popular: true,
      ),
      _location(
        slug: 'asia',
        title: 'Asia',
        countryCode: '',
        coverageType: 'regional',
        covered: ['HR'],
      ),
      _location(
        slug: 'europe',
        title: 'Europe',
        countryCode: '',
        coverageType: 'regional',
        covered: ['HR'],
      ),
      _location(
        slug: 'global',
        title: 'Global',
        countryCode: '',
        coverageType: 'global',
        covered: ['HR'],
      ),
    ];

    final rows = locationsForTab(locations, 'popular', viewerCountry: 'HR');

    expect(rows.map((row) => row.slug), [
      'croatia',
      'bosnia-and-herzegovina',
      'montenegro',
      'serbia',
      'europe',
      'global',
      'germany',
    ]);
    expect(
      locationsForTab(
        locations,
        'local',
        viewerCountry: 'HR',
      ).map((row) => row.slug),
      ['germany', 'croatia', 'bosnia-and-herzegovina', 'montenegro', 'serbia'],
    );
  });

  test('search returns the local hit then broader plans that cover it', () {
    final results = matchLocations(catalog, 'cro');
    expect(results.primary.map((row) => row.slug), ['croatia']);
    expect(results.broader.map((row) => row.slug), ['europe', 'global']);
  });

  test('fixed data keeps limited plans and groups them by days', () {
    final packages = [
      _package(
        id: 'u3',
        allowance: 'Unlimited',
        days: 3,
        price: '9.50',
        unlimited: true,
      ),
      _package(id: 'g7', allowance: '1 GB', days: 7, price: '4.00'),
      _package(id: 'g15', allowance: '2 GB', days: 15, price: '6.00'),
      _package(id: 'g7b', allowance: '3 GB', days: 7, price: '5.00'),
    ];
    final data = packagesForService(packages, 'data');
    final fixed = filterPackagesByAmount(data, 'fixed', 'data');
    final groups = groupPackagesByValidity(fixed);
    expect(fixed.map((package) => package.id), ['g7', 'g15', 'g7b']);
    expect(groups.map((group) => group.days), [7, 15]);
    expect(groups.first.packages.map((package) => package.id), ['g7', 'g7b']);
    expect(packageDataLabel(packages.first), 'Unlimited');
    expect(validityHeading(1), '1 day');
  });

  test('calls and texts stay off the data tab', () {
    final packages = [
      _package(id: 'data', allowance: '1 GB', days: 7, price: '4.00'),
      _package(
        id: 'voice',
        allowance: '1 GB',
        days: 7,
        price: '8.00',
        planType: 'data-voice-text',
      ),
    ];
    expect(packagesForService(packages, 'data').map((package) => package.id), [
      'data',
    ]);
    expect(
      shouldShowAmountFilter(packagesForService(packages, 'data'), 'data'),
      isFalse,
    );
    expect(highestNetworkType(['LTE', '5G']), '5G');
  });

  test('catalog and signup use the staging API', () {
    expect(catalogApiBase, 'https://api.staging.roamkit.net');
  });

  test('price uses the billing symbol and never a bare amount', () {
    expect(
      formatCatalogPrice(
        '4.5',
        const BillingDisplay(symbol: 'USDT', displayDecimals: 2),
      ),
      '4.50 USDT',
    );
    expect(formatCatalogPrice(null, BillingDisplay.fallback), '');
  });
}
