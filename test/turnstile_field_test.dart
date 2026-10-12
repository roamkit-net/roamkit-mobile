import 'package:flutter_test/flutter_test.dart';
import 'package:roamkit_mobile/turnstile_field.dart';

void main() {
  test('production API uses the production Turnstile widget', () {
    final widget = turnstileWidgetFor('https://api.roamkit.net');

    expect(widget.siteKey, productionTurnstileSiteKey);
    expect(widget.baseUrl, 'https://roamkit.net/');
    expect(widget.siteKey, isNot(stagingTurnstileSiteKey));
  });

  test('staging and other APIs keep the staging Turnstile widget', () {
    final staging = turnstileWidgetFor('https://api.staging.roamkit.net');
    final local = turnstileWidgetFor('http://127.0.0.1:8000');

    expect(staging.siteKey, stagingTurnstileSiteKey);
    expect(staging.baseUrl, 'https://staging.roamkit.net/');
    expect(local.siteKey, stagingTurnstileSiteKey);
    expect(local.baseUrl, 'https://staging.roamkit.net/');
  });
}
