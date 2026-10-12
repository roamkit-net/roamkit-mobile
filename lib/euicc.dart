import 'package:flutter/services.dart';

/// Opens Android eSIM setup. Returns null on success, or a message to show.
typedef EsimInstaller = Future<String?> Function(String setupLink);

const _channel = MethodChannel('net.roamkit.mobile/euicc');

/// Device install. Tests replace this so they never touch the channel.
EsimInstaller installEsim = _openSetupLink;

Future<String?> _openSetupLink(String setupLink) {
  return _channel.invokeMethod<String>('openSetupLink', {'url': setupLink});
}
