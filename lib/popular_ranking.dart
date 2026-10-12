import 'catalog.dart';

/// Hard cap for geo-ranked Popular results.
const popularHardCap = 12;

/// Soft cap for the recommended-market layer. Curated fills the rest.
const popularNeighborCap = 3;

/// Soft cap for Europe / Global when they cover the viewer.
const popularBroaderCap = 2;

/// Only these slugs may appear in the broader layer.
const broaderSlugAllowlist = ['europe', 'global'];

/// Destinations travelers from that country are likely to need.
/// Unknown countries fall through to local, then Europe/Global, then curated.
const recommendedMarkets = <String, List<String>>{
  'HR': ['BA', 'ME', 'RS'],
  'DE': ['AT', 'FR', 'IT', 'NL', 'CH'],
  'GB': ['FR', 'ES', 'IT', 'DE', 'PT'],
  'US': ['CA', 'MX', 'GB', 'JP', 'FR'],
};

List<String> recommendedMarketsFor(String viewerCountry) {
  return recommendedMarkets[viewerCountry] ?? const [];
}

/// Rank Popular destinations for a viewer country.
///
/// When [viewerCountry] is missing, returns `is_popular` rows in input order.
List<CatalogLocation> rankPopularLocations(
  List<CatalogLocation> locations,
  String? viewerCountry,
) {
  final country = viewerCountry?.trim().toUpperCase();
  if (country == null || country.isEmpty) {
    return locations.where((location) => location.isPopular).toList();
  }

  final localByCountry = <String, CatalogLocation>{};
  final bySlug = <String, CatalogLocation>{};
  for (final location in locations) {
    bySlug[location.slug] = location;
    if (location.coverageType == 'local' && location.countryCode.isNotEmpty) {
      localByCountry.putIfAbsent(
        location.countryCode.toUpperCase(),
        () => location,
      );
    }
  }

  final picked = <String>{};
  final result = <CatalogLocation>[];

  bool tryAdd(CatalogLocation? location) {
    if (location == null || picked.contains(location.slug)) {
      return false;
    }
    if (result.length >= popularHardCap) {
      return false;
    }
    picked.add(location.slug);
    result.add(location);
    return true;
  }

  tryAdd(localByCountry[country]);

  var recommendedTaken = 0;
  for (final code in recommendedMarketsFor(country)) {
    if (recommendedTaken >= popularNeighborCap) {
      break;
    }
    if (tryAdd(localByCountry[code])) {
      recommendedTaken += 1;
    }
  }

  var broaderTaken = 0;
  for (final slug in broaderSlugAllowlist) {
    if (broaderTaken >= popularBroaderCap) {
      break;
    }
    final candidate = bySlug[slug];
    final covers =
        candidate?.coveredCountryCodes.any(
          (code) => code.toUpperCase() == country,
        ) ??
        false;
    if (covers && tryAdd(candidate)) {
      broaderTaken += 1;
    }
  }

  for (final location in locations) {
    if (result.length >= popularHardCap) {
      break;
    }
    if (!location.isPopular) {
      continue;
    }
    tryAdd(location);
  }

  return result;
}
