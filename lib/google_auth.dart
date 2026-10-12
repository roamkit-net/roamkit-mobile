import 'dart:convert';
import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';

import 'catalog.dart';
import 'signup_api.dart';

const _productionServerClientId =
    '1077069744172-2fggulf6olc93i102e2d6gfok808u3t7.apps.googleusercontent.com';
const _stagingServerClientId =
    '1077069744172-tdjo47kd9r7u5vkecldr53vctecdmnue.apps.googleusercontent.com';

const _serverClientOverride = String.fromEnvironment(
  'ROAMKIT_GOOGLE_SERVER_CLIENT_ID',
);

/// Web client whose ID token audience the API already accepts.
String get googleServerClientId {
  if (_serverClientOverride.isNotEmpty) {
    return _serverClientOverride;
  }
  if (catalogApiBase.contains('api.staging.roamkit.net')) {
    return _stagingServerClientId;
  }
  return _productionServerClientId;
}

class GoogleAccountCredential {
  const GoogleAccountCredential({
    required this.idToken,
    required this.displayName,
  });

  final String idToken;
  final String displayName;
}

class GoogleSession {
  const GoogleSession({
    required this.access,
    required this.refresh,
    required this.displayName,
  });

  final String access;
  final String refresh;
  final String displayName;
}

typedef GoogleAccountReader = Future<GoogleAccountCredential?> Function();
typedef GoogleCredentialExchanger =
    Future<SignupTokens> Function(String idToken);
typedef DisplayNameReader = Future<String> Function(String accessToken);

GoogleAccountReader readGoogleAccount = readGoogleAccountFromDevice;
GoogleCredentialExchanger exchangeGoogleCredential =
    exchangeGoogleCredentialWithApi;
DisplayNameReader readSignedInDisplayName = currentDisplayName;

const _googleMessages = {
  'google_invalid_token': 'Google sign-in failed. Please try again.',
  'google_email_not_verified':
      'Your Google account email is not verified. Verify it with Google, or use email sign-in.',
  'google_account_disabled': 'This account is disabled.',
  'google_sub_conflict':
      'This Google account is already linked to another user.',
  'google_feature_disabled': 'Google sign-in is not available.',
  'google_verify_unavailable':
      'Google sign-in is temporarily unavailable. Please try again.',
};

const googleSignInFailedMessage = 'Google sign-in failed. Please try again.';
const googleSignInUnavailableMessage = 'Google sign-in is not available.';

String googleAuthMessageFromBody(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      final code = decoded['code'];
      if (code is String && _googleMessages.containsKey(code)) {
        return _googleMessages[code]!;
      }
      final detail = decoded['detail'];
      if (detail is String && detail.trim().isNotEmpty) {
        return detail.trim();
      }
    }
  } catch (_) {
    return googleSignInFailedMessage;
  }
  return googleSignInFailedMessage;
}

/// Returns null when the user closes the Google account picker.
Future<GoogleSession?> signInWithGoogle() async {
  final account = await readGoogleAccount();
  if (account == null || account.idToken.isEmpty) {
    return null;
  }
  final tokens = await exchangeGoogleCredential(account.idToken);
  final name = await readSignedInDisplayName(tokens.access);
  final fallback = account.displayName.trim();
  return GoogleSession(
    access: tokens.access,
    refresh: tokens.refresh,
    displayName: name.trim().isEmpty ? fallback : name.trim(),
  );
}

bool _googleReady = false;

Future<GoogleAccountCredential?> readGoogleAccountFromDevice() async {
  if (!_googleReady) {
    await GoogleSignIn.instance.initialize(
      serverClientId: googleServerClientId,
    );
    _googleReady = true;
  }
  try {
    await GoogleSignIn.instance.signOut();
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw SignupFailure('Google sign-in did not return a credential.');
    }
    final name = account.displayName?.trim();
    return GoogleAccountCredential(
      idToken: idToken,
      displayName: (name == null || name.isEmpty) ? account.email : name,
    );
  } on GoogleSignInException catch (error) {
    if (error.code == GoogleSignInExceptionCode.canceled) {
      return null;
    }
    if (error.code == GoogleSignInExceptionCode.clientConfigurationError ||
        error.code == GoogleSignInExceptionCode.providerConfigurationError ||
        error.code == GoogleSignInExceptionCode.uiUnavailable) {
      throw SignupFailure(googleSignInUnavailableMessage);
    }
    throw SignupFailure(googleSignInFailedMessage);
  }
}

Future<SignupTokens> exchangeGoogleCredentialWithApi(String idToken) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri.parse('$catalogApiBase/api/v1/auth/google/'),
    );
    final bytes = utf8.encode(jsonEncode({'credential': idToken}));
    request.contentLength = bytes.length;
    request.headers.set(
      HttpHeaders.contentTypeHeader,
      'application/json; charset=utf-8',
    );
    request.add(bytes);
    final response = await request.close();
    final raw = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw SignupFailure(googleAuthMessageFromBody(raw));
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw SignupFailure(googleSignInFailedMessage);
    }
    final access = decoded['access'];
    final refresh = decoded['refresh'];
    if (access is! String ||
        access.isEmpty ||
        refresh is! String ||
        refresh.isEmpty) {
      throw SignupFailure(googleSignInFailedMessage);
    }
    return SignupTokens(access: access, refresh: refresh);
  } on SignupFailure {
    rethrow;
  } catch (_) {
    throw SignupFailure('Could not reach RoamKit.');
  } finally {
    client.close(force: true);
  }
}
