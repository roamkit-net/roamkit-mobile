import 'dart:convert';
import 'dart:io';

import 'catalog.dart';
import 'orders_api.dart';

/// Applied package on an eSIM, from GET /me/esims/{id}/packages/.
class AppliedPackage {
  const AppliedPackage({
    required this.id,
    required this.kind,
    required this.status,
    required this.dataAllowance,
    required this.validityDays,
    required this.isUnlimited,
    required this.createdAt,
    required this.activatedAt,
    required this.expiresAt,
    required this.paidUsd,
    required this.currency,
  });

  final String id;
  final String kind;
  final String status;
  final String dataAllowance;
  final int validityDays;
  final bool isUnlimited;
  final String? createdAt;
  final String? activatedAt;
  final String? expiresAt;
  final String? paidUsd;
  final String currency;

  factory AppliedPackage.fromJson(Map<String, dynamic> json) {
    return AppliedPackage(
      id: json['id']?.toString() ?? '',
      kind: json['kind'] as String? ?? '',
      status: json['status'] as String? ?? '',
      dataAllowance: json['data_allowance'] as String? ?? '',
      validityDays: json['validity_days'] as int? ?? 0,
      isUnlimited: json['is_unlimited'] as bool? ?? false,
      createdAt: json['created_at'] as String?,
      activatedAt: json['activated_at'] as String?,
      expiresAt: json['expires_at'] as String?,
      paidUsd: json['paid_usd']?.toString(),
      currency: json['currency'] as String? ?? '',
    );
  }
}

class EsimUsage {
  const EsimUsage({
    required this.remainingMb,
    required this.totalMb,
    required this.isUnlimited,
  });

  final int? remainingMb;
  final int? totalMb;
  final bool isUnlimited;

  factory EsimUsage.fromJson(Map<String, dynamic> json) {
    return EsimUsage(
      remainingMb: _asInt(json['remaining_mb']),
      totalMb: _asInt(json['total_mb']),
      isUnlimited: json['is_unlimited'] as bool? ?? false,
    );
  }
}

/// Top-up package offered for an eSIM, from GET /me/esims/{id}/topups/.
class TopupOffer {
  const TopupOffer({
    required this.id,
    required this.title,
    required this.dataAllowance,
    required this.validityDays,
    required this.priceUsd,
    required this.isUnlimited,
    required this.planType,
    this.listPriceUsd = '',
  });

  final String id;
  final String title;
  final String dataAllowance;
  final int validityDays;
  final String priceUsd;
  final String listPriceUsd;
  final bool isUnlimited;
  final String planType;

  factory TopupOffer.fromJson(Map<String, dynamic> json) {
    return TopupOffer(
      id: json['id']?.toString() ?? '',
      title: json['title'] as String? ?? '',
      dataAllowance: json['data_allowance'] as String? ?? '',
      validityDays: json['validity_days'] as int? ?? 0,
      priceUsd: json['price_usd']?.toString() ?? '',
      listPriceUsd: json['list_price_usd']?.toString() ?? '',
      isUnlimited: json['is_unlimited'] as bool? ?? false,
      planType: json['plan_type'] as String? ?? 'topup',
    );
  }

  CatalogPackage toCatalogPackage() {
    return CatalogPackage(
      id: id,
      dataAllowance: dataAllowance,
      validityDays: validityDays,
      priceUsd: priceUsd,
      listPriceUsd: listPriceUsd,
      isUnlimited: isUnlimited,
      planType: planType,
    );
  }
}

class AutoTopupPolicy {
  const AutoTopupPolicy({
    required this.packageId,
    required this.enabled,
    required this.status,
    required this.reason,
    required this.expiryEnabled,
    required this.usageMode,
    required this.thresholdMb,
    required this.renewMode,
    required this.remainingCount,
    required this.activeUntil,
    required this.version,
  });

  final String packageId;
  final bool enabled;
  final String status;
  final String reason;
  final bool expiryEnabled;
  final String usageMode;
  final int? thresholdMb;
  final String renewMode;
  final int? remainingCount;
  final String? activeUntil;
  final int version;

  factory AutoTopupPolicy.fromJson(Map<String, dynamic> json) {
    return AutoTopupPolicy(
      packageId: json['package_id']?.toString() ?? '',
      enabled: json['enabled'] as bool? ?? false,
      status: json['status'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      expiryEnabled: json['expiry_enabled'] as bool? ?? false,
      usageMode: json['usage_mode'] as String? ?? 'disabled',
      thresholdMb: _asInt(json['threshold_mb']),
      renewMode: json['renew_mode'] as String? ?? 'until_funds',
      remainingCount: _asInt(json['remaining_count']),
      activeUntil: json['active_until'] as String?,
      version: _asInt(json['version']) ?? 0,
    );
  }
}

class AutoTopupLoad {
  const AutoTopupLoad({this.policy, this.unavailable});

  final AutoTopupPolicy? policy;

  /// Set when the API refuses auto top-up for this account.
  final String? unavailable;
}

class DetailApiException implements Exception {
  const DetailApiException(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => message;
}

/// API calls used by the eSIM detail screen. Tests replace the functions.
class EsimDetailApi {
  const EsimDetailApi({
    this.packages = fetchEsimPackages,
    this.usage = fetchEsimUsage,
    this.topups = fetchEsimTopups,
    this.buyTopup = purchaseEsimTopup,
    this.autoTopup = fetchAutoTopup,
    this.saveAutoTopup = putAutoTopup,
    this.deleteAutoTopup = removeAutoTopup,
    this.saveNote = patchEsimNote,
    this.display = fetchBillingDisplay,
  });

  final Future<List<AppliedPackage>> Function(int esimId) packages;
  final Future<EsimUsage> Function(int esimId) usage;
  final Future<List<TopupOffer>> Function(int esimId) topups;
  final Future<OrderOutcome> Function(
    int esimId,
    String packageId,
    String idempotencyKey,
  )
  buyTopup;
  final Future<AutoTopupLoad> Function(int esimId) autoTopup;
  final Future<AutoTopupPolicy> Function(
    int esimId,
    Map<String, dynamic> body,
    int? version,
  )
  saveAutoTopup;
  final Future<void> Function(int esimId, int version) deleteAutoTopup;
  final Future<String> Function(int esimId, String note) saveNote;
  final Future<BillingDisplay> Function() display;
}

Future<List<AppliedPackage>> fetchEsimPackages(int esimId) async {
  final response = await _request('GET', _esimUri(esimId, 'packages/'));
  _requireOk(response, 'Could not load packages.');
  return _results(response.body).map(AppliedPackage.fromJson).toList();
}

Future<EsimUsage> fetchEsimUsage(int esimId) async {
  final response = await _request('GET', _esimUri(esimId, 'usage/'));
  _requireOk(response, 'Could not refresh usage.');
  return EsimUsage.fromJson(_decode(response.body));
}

Future<List<TopupOffer>> fetchEsimTopups(int esimId) async {
  final response = await _request('GET', _esimUri(esimId, 'topups/'));
  _requireOk(response, 'Could not load top-ups.');
  return _results(response.body).map(TopupOffer.fromJson).toList();
}

/// POST /me/esims/{id}/topups/. Credits are debited by the API, never here.
Future<OrderOutcome> purchaseEsimTopup(
  int esimId,
  String packageId,
  String idempotencyKey,
) async {
  try {
    final response = await _request(
      'POST',
      _esimUri(esimId, 'topups/'),
      body: {'package_id': packageId, 'idempotency_key': idempotencyKey},
    );
    if (response.status == 401) {
      return const OrderOutcome.failed(purchaseSignInMessage);
    }
    return orderOutcomeFrom(response.status, response.body);
  } catch (_) {
    return const OrderOutcome.failed('Could not reach RoamKit.');
  }
}

Future<AutoTopupLoad> fetchAutoTopup(int esimId) async {
  final response = await _request('GET', _esimUri(esimId, 'auto-topup/'));
  if (response.status == 404) {
    return const AutoTopupLoad();
  }
  if (response.status == 403) {
    return const AutoTopupLoad(
      unavailable: 'Auto top-up is not enabled for your account yet.',
    );
  }
  _requireOk(response, 'Unable to load auto top-up.');
  return AutoTopupLoad(
    policy: AutoTopupPolicy.fromJson(_decode(response.body)),
  );
}

Future<AutoTopupPolicy> putAutoTopup(
  int esimId,
  Map<String, dynamic> body,
  int? version,
) async {
  final response = await _request(
    'PUT',
    _esimUri(esimId, 'auto-topup/'),
    body: body,
    headers: {if (version != null) 'If-Match': '$version'},
  );
  _requireOk(response, 'Unable to save auto top-up.');
  return AutoTopupPolicy.fromJson(_decode(response.body));
}

Future<void> removeAutoTopup(int esimId, int version) async {
  final response = await _request(
    'DELETE',
    _esimUri(esimId, 'auto-topup/', query: 'version=$version'),
  );
  if (response.status == 404) {
    return;
  }
  _requireOk(response, 'Unable to save auto top-up.');
}

/// PATCH /me/esims/{id}/. Returns the saved note.
Future<String> patchEsimNote(int esimId, String note) async {
  final response = await _request(
    'PATCH',
    _esimUri(esimId, ''),
    body: {'note': note},
  );
  _requireOk(response, 'Could not save the note.');
  return _decode(response.body)['note'] as String? ?? note;
}

Uri _esimUri(int esimId, String path, {String? query}) {
  final suffix = query == null ? '' : '?$query';
  return Uri.parse('$catalogApiBase/api/v1/me/esims/$esimId/$path$suffix');
}

class _Response {
  const _Response(this.status, this.body);

  final int status;
  final String body;
}

Future<_Response> _request(
  String method,
  Uri uri, {
  Map<String, dynamic>? body,
  Map<String, String> headers = const {},
}) async {
  final client = HttpClient();
  try {
    Future<_Response> send() async {
      final request = await client.openUrl(method, uri);
      final token = catalogAccessToken();
      if (token != null && token.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      headers.forEach(request.headers.set);
      if (body != null) {
        final bytes = utf8.encode(jsonEncode(body));
        request.headers.set(
          HttpHeaders.contentTypeHeader,
          'application/json; charset=utf-8',
        );
        request.contentLength = bytes.length;
        request.add(bytes);
      }
      final response = await request.close();
      final raw = await response.transform(utf8.decoder).join();
      return _Response(response.statusCode, raw);
    }

    var response = await send();
    if (response.status == 401 && await catalogRefreshAuth()) {
      response = await send();
    }
    return response;
  } finally {
    client.close(force: true);
  }
}

void _requireOk(_Response response, String fallback) {
  if (response.status >= 200 && response.status < 300) {
    return;
  }
  final detail = _decode(response.body)['detail'];
  if (response.status == 409) {
    throw DetailApiException(
      409,
      'This changed elsewhere. Reload and try again.',
    );
  }
  throw DetailApiException(
    response.status,
    detail is String && detail.trim().isNotEmpty ? detail.trim() : fallback,
  );
}

List<Map<String, dynamic>> _results(String raw) {
  final results = _decode(raw)['results'];
  if (results is! List) {
    return const [];
  }
  return [
    for (final item in results)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}

Map<String, dynamic> _decode(String raw) {
  if (raw.trim().isEmpty) {
    return const {};
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
  } catch (_) {
    return const {};
  }
  return const {};
}

int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}
