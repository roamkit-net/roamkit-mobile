import 'dart:convert';
import 'dart:io';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

const viewerCountryTtl = Duration(minutes: 5);

const _traceUrl = 'https://www.cloudflare.com/cdn-cgi/trace';
const _invalidCountryCodes = {'XX', 'T1'};

typedef CountryLookup = Future<String?> Function();

class _CacheEntry {
  const _CacheEntry({required this.value, required this.expiresAt});

  final String? value;
  final DateTime expiresAt;
}

_CacheEntry? _cache;
Future<String?>? _inflight;

/// ISO2, or null when the value is missing or not a real country.
String? normalizeCountryCode(String? value) {
  if (value == null) {
    return null;
  }
  final code = value.trim().toUpperCase();
  if (!RegExp(r'^[A-Z]{2}$').hasMatch(code) ||
      _invalidCountryCodes.contains(code)) {
    return null;
  }
  return code;
}

/// Read `loc=` from a Cloudflare trace body.
String? parseCloudflareTraceCountry(String body) {
  for (final line in body.split('\n')) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('loc=')) {
      continue;
    }
    return normalizeCountryCode(trimmed.substring('loc='.length));
  }
  return null;
}

void resetViewerCountryCache() {
  _cache = null;
  _inflight = null;
}

/// GPS country, then the device's public IP. Both misses stay cached.
Future<String?> resolveViewerCountry({
  CountryLookup? readGpsCountry,
  CountryLookup? readIpCountry,
  DateTime Function()? now,
}) {
  final clock = now ?? DateTime.now;
  final cached = _cache;
  if (cached != null && cached.expiresAt.isAfter(clock())) {
    return Future<String?>.value(cached.value);
  }
  final pending = _inflight;
  if (pending != null) {
    return pending;
  }
  final future = _lookup(
    readGpsCountry: readGpsCountry ?? readGpsCountryFromDevice,
    readIpCountry: readIpCountry ?? readIpCountryFromTrace,
    now: clock,
  );
  _inflight = future;
  return future.whenComplete(() {
    if (identical(_inflight, future)) {
      _inflight = null;
    }
  });
}

Future<String?> _lookup({
  required CountryLookup readGpsCountry,
  required CountryLookup readIpCountry,
  required DateTime Function() now,
}) async {
  String? value;
  try {
    value = normalizeCountryCode(await readGpsCountry());
  } catch (_) {
    value = null;
  }
  if (value == null) {
    try {
      value = normalizeCountryCode(await readIpCountry());
    } catch (_) {
      value = null;
    }
  }
  _cache = _CacheEntry(value: value, expiresAt: now().add(viewerCountryTtl));
  return value;
}

Future<String?> readGpsCountryFromDevice() async {
  try {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      return null;
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 8),
      ),
    );
    final marks = await placemarkFromCoordinates(
      position.latitude,
      position.longitude,
    ).timeout(const Duration(seconds: 8));
    if (marks.isEmpty) {
      return null;
    }
    return normalizeCountryCode(marks.first.isoCountryCode);
  } catch (_) {
    return null;
  }
}

Future<String?> readIpCountryFromTrace() async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(_traceUrl));
    final response = await request.close().timeout(const Duration(seconds: 2));
    if (response.statusCode != 200) {
      return null;
    }
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 2));
    return parseCloudflareTraceCountry(body);
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}
