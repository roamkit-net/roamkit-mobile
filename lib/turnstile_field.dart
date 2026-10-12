import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'catalog.dart';

/// Public production widget. Hostname must stay on `roamkit.net`.
const productionTurnstileSiteKey = '0x4AAAAAAD-ZjsP2mKFXIrsY';
const productionTurnstileBaseUrl = 'https://roamkit.net/';

/// Public staging widget. Hostname must stay `staging.roamkit.net`.
const stagingTurnstileSiteKey = '0x4AAAAAAD-YN3lSkfPOTGKE';
const stagingTurnstileBaseUrl = 'https://staging.roamkit.net/';

class TurnstileWidgetConfig {
  const TurnstileWidgetConfig({required this.siteKey, required this.baseUrl});

  final String siteKey;
  final String baseUrl;
}

/// Production API uses the production widget. Every other API stays on staging.
TurnstileWidgetConfig turnstileWidgetFor(String apiBase) {
  final host = Uri.tryParse(apiBase)?.host;
  if (host == 'api.roamkit.net') {
    return const TurnstileWidgetConfig(
      siteKey: productionTurnstileSiteKey,
      baseUrl: productionTurnstileBaseUrl,
    );
  }
  return const TurnstileWidgetConfig(
    siteKey: stagingTurnstileSiteKey,
    baseUrl: stagingTurnstileBaseUrl,
  );
}

TurnstileWidgetConfig get activeTurnstile => turnstileWidgetFor(catalogApiBase);

/// Widget tests have no WebView. The device always has to send a token.
bool get turnstileRequired =>
    !WidgetsBinding.instance.runtimeType.toString().contains('Test');

class TurnstileField extends StatelessWidget {
  const TurnstileField({super.key, required this.onToken});

  final ValueChanged<String?> onToken;

  @override
  Widget build(BuildContext context) {
    if (!turnstileRequired) {
      return const SizedBox.shrink();
    }
    return _TurnstileWebView(onToken: onToken);
  }
}

class _TurnstileWebView extends StatefulWidget {
  const _TurnstileWebView({required this.onToken});

  final ValueChanged<String?> onToken;

  @override
  State<_TurnstileWebView> createState() => _TurnstileWebViewState();
}

class _TurnstileWebViewState extends State<_TurnstileWebView> {
  late final WebViewController _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(Colors.white)
    ..addJavaScriptChannel(
      'TurnstileToken',
      onMessageReceived: (message) {
        final token = message.message.trim();
        widget.onToken(token.isEmpty ? null : token);
      },
    )
    ..loadHtmlString(_html, baseUrl: activeTurnstile.baseUrl);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: WebViewWidget(
        controller: _controller,
        gestureRecognizers: {
          Factory<TapGestureRecognizer>(() => TapGestureRecognizer()),
          Factory<VerticalDragGestureRecognizer>(
            () => VerticalDragGestureRecognizer(),
          ),
        },
      ),
    );
  }
}

String get _html =>
    '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    html, body { margin: 0; background: #fff; }
  </style>
  <script src="https://challenges.cloudflare.com/turnstile/v0/api.js?onload=onTurnstileLoad&render=explicit" async defer></script>
</head>
<body>
  <div id="cf"></div>
  <script>
    function onTurnstileLoad() {
      turnstile.render('#cf', {
        sitekey: '${activeTurnstile.siteKey}',
        theme: 'light',
        callback: function (token) { TurnstileToken.postMessage(token); },
        'error-callback': function () { TurnstileToken.postMessage(''); },
        'expired-callback': function () { TurnstileToken.postMessage(''); }
      });
    }
  </script>
</body>
</html>
''';
