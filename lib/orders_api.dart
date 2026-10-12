import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'catalog.dart';
import 'session.dart';

enum OrderStatus { success, insufficient, failed }

class OrderOutcome {
  const OrderOutcome._(this.status, {this.message = '', this.missing});

  const OrderOutcome.success() : this._(OrderStatus.success);

  const OrderOutcome.insufficient({String? missing})
    : this._(OrderStatus.insufficient, missing: missing);

  const OrderOutcome.failed(String message)
    : this._(OrderStatus.failed, message: message);

  final OrderStatus status;
  final String message;

  /// Credits still needed, from the 402 body.
  final String? missing;
}

typedef OrderSender =
    Future<OrderOutcome> Function(String packageId, String idempotencyKey);

const purchaseFallbackMessage = 'Unable to complete purchase.';
const purchaseInProgressMessage = 'Purchase already in progress.';
const purchaseSignInMessage = 'Log in again to buy this plan.';

/// Same shape as the web `newSpendIdempotencyKey("order")`.
String newOrderIdempotencyKey([Random? random]) {
  final source = random ?? Random.secure();
  final hex = List<String>.generate(
    16,
    (_) => source.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  return 'order-$hex';
}

/// POST /api/v1/orders/. Credits are debited by the API, never here.
Future<OrderOutcome> createOrder(
  String packageId,
  String idempotencyKey,
) async {
  final session = AppSession.instance;
  try {
    var response = await _send(packageId, idempotencyKey, session.accessToken);
    if (response.status == 401) {
      if (!await session.refreshAccess()) {
        return const OrderOutcome.failed(purchaseSignInMessage);
      }
      response = await _send(packageId, idempotencyKey, session.accessToken);
      if (response.status == 401) {
        await session.signOut();
        return const OrderOutcome.failed(purchaseSignInMessage);
      }
    }
    return orderOutcomeFrom(response.status, response.body);
  } catch (_) {
    return const OrderOutcome.failed('Could not reach RoamKit.');
  }
}

OrderOutcome orderOutcomeFrom(int status, String raw) {
  if (status == 200 || status == 201) {
    return const OrderOutcome.success();
  }
  final body = _decode(raw);
  if (status == 402) {
    final missing = body['missing'];
    return OrderOutcome.insufficient(missing: missing?.toString());
  }
  if (status == 409) {
    return const OrderOutcome.failed(purchaseInProgressMessage);
  }
  final detail = body['detail'];
  if (detail is String && detail.trim().isNotEmpty) {
    return OrderOutcome.failed(detail.trim());
  }
  return const OrderOutcome.failed(purchaseFallbackMessage);
}

class _Response {
  const _Response(this.status, this.body);

  final int status;
  final String body;
}

Future<_Response> _send(
  String packageId,
  String idempotencyKey,
  String? token,
) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri.parse('$catalogApiBase/api/v1/orders/'),
    );
    final bytes = utf8.encode(
      jsonEncode({'package_id': packageId, 'idempotency_key': idempotencyKey}),
    );
    request.contentLength = bytes.length;
    request.headers.set(
      HttpHeaders.contentTypeHeader,
      'application/json; charset=utf-8',
    );
    if (token != null && token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    request.add(bytes);
    final response = await request.close();
    final raw = await response.transform(utf8.decoder).join();
    return _Response(response.statusCode, raw);
  } finally {
    client.close(force: true);
  }
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
