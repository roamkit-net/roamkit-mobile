import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'esim.dart';

/// Opens the platform eSIM setup link. Returns null on success, or a message.
typedef EsimInstaller = Future<String?> Function(String setupLink);

/// Apple link on iOS, Android link everywhere else.
String? esimSetupLink({String? lpa, String? matchingId}) {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return appleSetupLink(lpa: lpa, matchingId: matchingId);
  }
  return androidSetupLink(lpa: lpa, matchingId: matchingId);
}

const _channel = MethodChannel('net.roamkit.mobile/euicc');

/// Device install. Tests replace this so they never touch the channel.
EsimInstaller installEsim = _openSetupLink;

Future<String?> _openSetupLink(String setupLink) {
  return _channel.invokeMethod<String>('openSetupLink', {'url': setupLink});
}
