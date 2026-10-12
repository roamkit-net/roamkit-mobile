import 'package:flutter_test/flutter_test.dart';
import 'package:roamkit_mobile/viewer_country.dart';

void main() {
  setUp(resetViewerCountryCache);

  test('GPS country wins over the IP lookup', () async {
    var ipCalls = 0;
    final country = await resolveViewerCountry(
      readGpsCountry: () async => 'hr',
      readIpCountry: () async {
        ipCalls += 1;
        return 'DE';
      },
    );

    expect(country, 'HR');
    expect(ipCalls, 0);
  });

  test('a missing GPS fix falls through to the public IP', () async {
    final country = await resolveViewerCountry(
      readGpsCountry: () async => null,
      readIpCountry: () async => 'HR',
    );

    expect(country, 'HR');
  });

  test('both misses stay empty and are cached', () async {
    var calls = 0;
    Future<String?> miss() async {
      calls += 1;
      return null;
    }

    final now = DateTime.utc(2026, 10, 11, 12);
    final first = await resolveViewerCountry(
      readGpsCountry: miss,
      readIpCountry: miss,
      now: () => now,
    );
    final second = await resolveViewerCountry(
      readGpsCountry: miss,
      readIpCountry: miss,
      now: () => now.add(const Duration(minutes: 4)),
    );

    expect(first, isNull);
    expect(second, isNull);
    expect(calls, 2);
  });

  test('trace loc is an ISO country or nothing', () {
    expect(parseCloudflareTraceCountry('ip=1.2.3.4\nloc=HR\n'), 'HR');
    expect(parseCloudflareTraceCountry('loc=XX'), isNull);
    expect(parseCloudflareTraceCountry('colo=VIE'), isNull);
  });
}
