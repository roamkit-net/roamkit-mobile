import 'dart:convert';
import 'dart:io';

import 'popular_ranking.dart';

const catalogApiBase = String.fromEnvironment(
  'ROAMKIT_API_BASE',
  defaultValue: 'https://api.staging.roamkit.net',
);

/// Set by [AppSession] so package requests can send the signed-in token.
String? Function() catalogAccessToken = () => null;

/// Set by [AppSession]. Returns true when a new access token was stored.
Future<bool> Function() catalogRefreshAuth = () async => false;

class CatalogLocation {
  const CatalogLocation({
    required this.slug,
    required this.title,
    required this.countryCode,
    required this.coverageType,
    required this.imageUrl,
    required this.isPopular,
    required this.minPriceUsd,
    required this.coveredCountryCodes,
  });

  final String slug;
  final String title;
  final String countryCode;
  final String coverageType;
  final String imageUrl;
  final bool isPopular;
  final String? minPriceUsd;
  final List<String> coveredCountryCodes;

  factory CatalogLocation.fromJson(Map<String, dynamic> json) {
    final covered = json['covered_country_codes'];
    return CatalogLocation(
      slug: json['slug'] as String? ?? '',
      title: json['title'] as String? ?? '',
      countryCode: json['country_code'] as String? ?? '',
      coverageType: json['coverage_type'] as String? ?? '',
      imageUrl: json['image_url'] as String? ?? '',
      isPopular: json['is_popular'] as bool? ?? false,
      minPriceUsd: json['min_price_usd'] as String?,
      coveredCountryCodes: covered is List
          ? covered.map((code) => code.toString()).toList()
          : const [],
    );
  }

  String? get imageSrc {
    if (imageUrl.isNotEmpty) {
      return imageUrl;
    }
    if (countryCode.isNotEmpty) {
      return 'https://flagcdn.com/w80/${countryCode.toLowerCase()}.png';
    }
    return null;
  }
}

class BillingDisplay {
  const BillingDisplay({required this.symbol, required this.displayDecimals});

  final String symbol;
  final int displayDecimals;

  static const fallback = BillingDisplay(symbol: 'credits', displayDecimals: 2);
}

class LocationSearchResults {
  const LocationSearchResults({required this.primary, required this.broader});

  final List<CatalogLocation> primary;
  final List<CatalogLocation> broader;
}

bool locationTextMatches(CatalogLocation location, String normalizedQuery) {
  if (location.title.toLowerCase().contains(normalizedQuery)) {
    return true;
  }
  if (location.slug.toLowerCase().contains(normalizedQuery)) {
    return true;
  }
  final code = location.countryCode.toLowerCase();
  return code.isNotEmpty &&
      (code == normalizedQuery || code.contains(normalizedQuery));
}

bool coversCountry(CatalogLocation location, String countryCode) {
  final normalized = countryCode.toUpperCase();
  if (normalized.isEmpty) {
    return false;
  }
  return location.coveredCountryCodes.any(
    (code) => code.toUpperCase() == normalized,
  );
}

int _byTitle(CatalogLocation a, CatalogLocation b) =>
    a.title.toLowerCase().compareTo(b.title.toLowerCase());

/// Same split as the web `matchLocations` helper: local hits first, then
/// regional and global plans that cover those countries.
LocationSearchResults matchLocations(
  List<CatalogLocation> locations,
  String query,
) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) {
    return const LocationSearchResults(primary: [], broader: []);
  }

  final primary =
      locations
          .where(
            (location) =>
                location.coverageType == 'local' &&
                locationTextMatches(location, normalizedQuery),
          )
          .toList()
        ..sort(_byTitle);

  final primarySlugs = primary.map((location) => location.slug).toSet();
  final matchedCountryCodes = primary
      .map((location) => location.countryCode.toUpperCase())
      .where((code) => code.isNotEmpty)
      .toSet();

  final List<CatalogLocation> broader;
  if (matchedCountryCodes.isNotEmpty) {
    broader = locations.where((location) {
      if (location.coverageType == 'local') {
        return false;
      }
      if (primarySlugs.contains(location.slug)) {
        return false;
      }
      return matchedCountryCodes.any((code) => coversCountry(location, code));
    }).toList();
  } else {
    broader = locations
        .where(
          (location) =>
              location.coverageType != 'local' &&
              locationTextMatches(location, normalizedQuery),
        )
        .toList();
  }

  broader.sort((a, b) {
    final coverageDiff =
        (a.coverageType == 'regional' ? 0 : 1) -
        (b.coverageType == 'regional' ? 0 : 1);
    if (coverageDiff != 0) {
      return coverageDiff;
    }
    return _byTitle(a, b);
  });

  return LocationSearchResults(primary: primary, broader: broader);
}

List<CatalogLocation> locationsForTab(
  List<CatalogLocation> locations,
  String tab, {
  String? viewerCountry,
}) {
  switch (tab) {
    case 'popular':
      return rankPopularLocations(locations, viewerCountry);
    case 'local':
    case 'regional':
    case 'global':
      return locations
          .where((location) => location.coverageType == tab)
          .toList();
    default:
      return locations;
  }
}

String formatCatalogPrice(String? amount, BillingDisplay display) {
  if (amount == null || amount.trim().isEmpty) {
    return '';
  }
  final value = double.tryParse(amount);
  if (value == null) {
    return '';
  }
  return '${value.toStringAsFixed(display.displayDecimals)} ${display.symbol}';
}

/// List price to strike when it differs from the customer charge.
/// Render-only: never derived from a discount percent.
String? struckListPrice(
  String listPriceUsd,
  String priceUsd,
  BillingDisplay display,
) {
  final list = formatCatalogPrice(listPriceUsd, display);
  final charge = formatCatalogPrice(priceUsd, display);
  if (list.isEmpty || list == charge) {
    return null;
  }
  return list;
}

Future<String> _getString(Uri uri, {bool authorize = false}) async {
  final client = HttpClient();
  try {
    Future<HttpClientResponse> send() async {
      final request = await client.getUrl(uri);
      if (authorize) {
        final token = catalogAccessToken();
        if (token != null && token.isNotEmpty) {
          request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        }
      }
      return request.close();
    }

    var response = await send();
    if (response.statusCode == 401 && authorize) {
      await response.transform(utf8.decoder).join();
      await catalogRefreshAuth();
      response = await send();
    }
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode} for $uri', uri: uri);
    }
    return body;
  } finally {
    client.close(force: true);
  }
}

Future<List<CatalogLocation>> fetchAllLocations() async {
  final locations = <CatalogLocation>[];
  var next = '$catalogApiBase/api/v1/locations/';
  var page = 0;

  while (next.isNotEmpty && page < 40) {
    page += 1;
    final body = await _getString(Uri.parse(next));
    final json = jsonDecode(body) as Map<String, dynamic>;
    final results = json['results'];
    if (results is List) {
      for (final item in results) {
        if (item is Map<String, dynamic>) {
          locations.add(CatalogLocation.fromJson(item));
        } else if (item is Map) {
          locations.add(
            CatalogLocation.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    final rawNext = json['next'];
    next = rawNext is String ? rawNext : '';
  }

  return locations;
}

class CoverageNetwork {
  const CoverageNetwork({required this.name, required this.types});

  final String name;
  final List<String> types;

  factory CoverageNetwork.fromJson(Map<String, dynamic> json) {
    final types = json['types'];
    return CoverageNetwork(
      name: json['name'] as String? ?? '',
      types: types is List
          ? types.map((type) => type.toString()).toList()
          : const [],
    );
  }
}

class LocationCoverage {
  const LocationCoverage({
    required this.code,
    required this.name,
    required this.networks,
  });

  final String code;
  final String name;
  final List<CoverageNetwork> networks;

  factory LocationCoverage.fromJson(Map<String, dynamic> json) {
    final networks = json['networks'];
    return LocationCoverage(
      code: json['code'] as String? ?? '',
      name: json['name'] as String? ?? '',
      networks: networks is List
          ? networks
                .map(_jsonMap)
                .whereType<Map<String, dynamic>>()
                .map(CoverageNetwork.fromJson)
                .toList()
          : const [],
    );
  }
}

class CatalogPackage {
  const CatalogPackage({
    required this.id,
    required this.dataAllowance,
    required this.validityDays,
    required this.priceUsd,
    required this.isUnlimited,
    required this.planType,
    this.listPriceUsd = '',
    this.voiceMinutes,
    this.textSms,
  });

  final String id;
  final String dataAllowance;
  final int validityDays;
  final String priceUsd;
  final String listPriceUsd;
  final bool isUnlimited;
  final String planType;
  final int? voiceMinutes;
  final int? textSms;

  factory CatalogPackage.fromJson(Map<String, dynamic> json) {
    return CatalogPackage(
      id: json['id'] as String? ?? '',
      dataAllowance: json['data_allowance'] as String? ?? '',
      validityDays: json['validity_days'] as int? ?? 0,
      priceUsd: json['price_usd'] as String? ?? '',
      listPriceUsd: json['list_price_usd'] as String? ?? '',
      isUnlimited: json['is_unlimited'] as bool? ?? false,
      planType: json['plan_type'] as String? ?? 'data',
      voiceMinutes: json['voice_minutes'] as int?,
      textSms: json['text_sms'] as int?,
    );
  }
}

class LocationDetailData {
  const LocationDetailData({
    required this.coverageType,
    required this.coverages,
    required this.packages,
  });

  final String coverageType;
  final List<LocationCoverage> coverages;
  final List<CatalogPackage> packages;
}

class PackageDayGroup {
  const PackageDayGroup({required this.days, required this.packages});

  final int days;
  final List<CatalogPackage> packages;
}

Map<String, dynamic>? _jsonMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return null;
}

bool packageIsDataCallsTexts(CatalogPackage package) {
  if ((package.voiceMinutes ?? 0) > 0 || (package.textSms ?? 0) > 0) {
    return true;
  }
  final planType = package.planType.toLowerCase();
  if (planType == 'data' || planType == 'topup') {
    return false;
  }
  return planType.contains('voice') ||
      planType.contains('text') ||
      planType.contains('call');
}

const _networkTypeRank = {'5G': 3, 'LTE': 2, '4G': 2, '3G': 1};

String? highestNetworkType(List<String> types) {
  String? best;
  var bestRank = -1;
  for (final type in types) {
    final normalized = type.trim().toUpperCase();
    final rank = _networkTypeRank[normalized] ?? 0;
    if (rank > bestRank) {
      bestRank = rank;
      best = normalized == '4G' ? 'LTE' : normalized;
    }
  }
  return best;
}

List<CoverageNetwork> flattenNetworks(List<LocationCoverage> coverages) {
  return [for (final coverage in coverages) ...coverage.networks];
}

List<CatalogPackage> packagesForService(
  List<CatalogPackage> packages,
  String service,
) {
  if (service == 'data_calls_texts') {
    return packages.where(packageIsDataCallsTexts).toList();
  }
  return packages
      .where((package) => !packageIsDataCallsTexts(package))
      .toList();
}

bool shouldShowAmountFilter(
  List<CatalogPackage> servicePackages,
  String service,
) {
  if (service != 'data') {
    return false;
  }
  final hasFixed = servicePackages.any((package) => !package.isUnlimited);
  final hasUnlimited = servicePackages.any((package) => package.isUnlimited);
  return hasFixed && hasUnlimited;
}

/// `fixed` is the screenshot's "Fixed data" pill. It maps to the web Standard filter.
String resolveAmountFilter(
  String filter,
  List<CatalogPackage> servicePackages,
) {
  final hasFixed = servicePackages.any((package) => !package.isUnlimited);
  final hasUnlimited = servicePackages.any((package) => package.isUnlimited);
  if (filter == 'fixed' && !hasFixed && hasUnlimited) {
    return 'unlimited';
  }
  if (filter == 'unlimited' && !hasUnlimited && hasFixed) {
    return 'fixed';
  }
  return filter;
}

List<CatalogPackage> filterPackagesByAmount(
  List<CatalogPackage> servicePackages,
  String filter,
  String service,
) {
  if (service != 'data') {
    return servicePackages;
  }
  if (filter == 'unlimited') {
    return servicePackages.where((package) => package.isUnlimited).toList();
  }
  return servicePackages.where((package) => !package.isUnlimited).toList();
}

List<PackageDayGroup> groupPackagesByValidity(List<CatalogPackage> packages) {
  final sorted = [...packages]
    ..sort((a, b) {
      if (a.validityDays != b.validityDays) {
        return a.validityDays.compareTo(b.validityDays);
      }
      return (double.tryParse(a.priceUsd) ?? 0).compareTo(
        double.tryParse(b.priceUsd) ?? 0,
      );
    });
  final groups = <PackageDayGroup>[];
  for (final package in sorted) {
    if (groups.isNotEmpty && groups.last.days == package.validityDays) {
      groups.last.packages.add(package);
    } else {
      groups.add(
        PackageDayGroup(days: package.validityDays, packages: [package]),
      );
    }
  }
  return groups;
}

String validityHeading(int days) => days == 1 ? '1 day' : '$days days';

String packageDataLabel(CatalogPackage package) {
  if (package.isUnlimited) {
    final allowance = package.dataAllowance.trim();
    if (allowance.isEmpty || allowance.toLowerCase() == 'unlimited') {
      return 'Unlimited';
    }
    return allowance;
  }
  return package.dataAllowance;
}

Future<String?> fetchLocationImage(String slug) async {
  final body = await _getString(
    Uri.parse('$catalogApiBase/api/v1/locations/${Uri.encodeComponent(slug)}/'),
  );
  final json = jsonDecode(body);
  if (json is! Map<String, dynamic>) {
    return null;
  }
  return CatalogLocation.fromJson(json).imageSrc;
}

Future<LocationDetailData> fetchLocationDetail(String slug) async {
  final locationBody = await _getString(
    Uri.parse('$catalogApiBase/api/v1/locations/${Uri.encodeComponent(slug)}/'),
  );
  final locationJson = jsonDecode(locationBody) as Map<String, dynamic>;
  final rawCoverages = locationJson['coverages'];
  final coverages = rawCoverages is List
      ? rawCoverages
            .map(_jsonMap)
            .whereType<Map<String, dynamic>>()
            .map(LocationCoverage.fromJson)
            .toList()
      : const <LocationCoverage>[];
  return LocationDetailData(
    coverageType: locationJson['coverage_type'] as String? ?? '',
    coverages: coverages,
    packages: await _fetchPackagesForLocation(slug),
  );
}

Future<List<CatalogPackage>> _fetchPackagesForLocation(String slug) async {
  final packages = <CatalogPackage>[];
  var next =
      '$catalogApiBase/api/v1/packages/?location=${Uri.encodeQueryComponent(slug)}';
  var page = 0;

  while (next.isNotEmpty && page < 40) {
    page += 1;
    final body = await _getString(Uri.parse(next), authorize: true);
    final json = jsonDecode(body) as Map<String, dynamic>;
    final results = json['results'];
    if (results is List) {
      for (final item in results) {
        final map = _jsonMap(item);
        if (map != null) {
          packages.add(CatalogPackage.fromJson(map));
        }
      }
    }
    final rawNext = json['next'];
    next = rawNext is String ? rawNext : '';
  }

  return packages;
}

Future<BillingDisplay> fetchBillingDisplay() async {
  try {
    final body = await _getString(
      Uri.parse('$catalogApiBase/api/v1/billing/config/'),
    );
    final json = jsonDecode(body) as Map<String, dynamic>;
    final symbol = (json['token_symbol'] as String?)?.trim();
    final decimals = json['display_decimals'];
    return BillingDisplay(
      symbol: symbol == null || symbol.isEmpty ? 'credits' : symbol,
      displayDecimals: decimals is int ? decimals : 2,
    );
  } catch (_) {
    return BillingDisplay.fallback;
  }
}
