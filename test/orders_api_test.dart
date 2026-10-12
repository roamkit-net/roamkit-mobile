import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:roamkit_mobile/orders_api.dart';

void main() {
  test('order key has the spend prefix and 128 random bits', () {
    final key = newOrderIdempotencyKey(Random(7));
    expect(key, startsWith('order-'));
    expect(key.length, 'order-'.length + 32);
    expect(newOrderIdempotencyKey(), isNot(newOrderIdempotencyKey()));
  });

  test('API status maps to the purchase outcome', () {
    expect(orderOutcomeFrom(201, '{}').status, OrderStatus.success);

    final short = orderOutcomeFrom(
      402,
      '{"code":"INSUFFICIENT_CREDITS","missing":"14.500000"}',
    );
    expect(short.status, OrderStatus.insufficient);
    expect(short.missing, '14.500000');

    expect(orderOutcomeFrom(409, '{}').message, purchaseInProgressMessage);
    expect(
      orderOutcomeFrom(404, '{"detail":"Package not found."}').message,
      'Package not found.',
    );
    expect(orderOutcomeFrom(500, 'oops').message, purchaseFallbackMessage);
  });
}
