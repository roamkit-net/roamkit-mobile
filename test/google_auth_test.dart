import 'package:flutter_test/flutter_test.dart';
import 'package:roamkit_mobile/catalog.dart';
import 'package:roamkit_mobile/google_auth.dart';
import 'package:roamkit_mobile/signup_api.dart';

void main() {
  final originalReader = readGoogleAccount;
  final originalExchange = exchangeGoogleCredential;
  final originalName = readSignedInDisplayName;

  tearDown(() {
    readGoogleAccount = originalReader;
    exchangeGoogleCredential = originalExchange;
    readSignedInDisplayName = originalName;
  });

  test('staging API uses the staging Google audience', () {
    expect(catalogApiBase, 'https://api.staging.roamkit.net');
    expect(
      googleServerClientId,
      '1077069744172-tdjo47kd9r7u5vkecldr53vctecdmnue.apps.googleusercontent.com',
    );
  });

  test('maps Google auth error codes', () {
    expect(
      googleAuthMessageFromBody('{"code":"google_account_disabled"}'),
      'This account is disabled.',
    );
    expect(
      googleAuthMessageFromBody('{"code":"google_sub_conflict"}'),
      'This Google account is already linked to another user.',
    );
    expect(googleAuthMessageFromBody('not-json'), googleSignInFailedMessage);
  });

  test('a closed account picker does not sign in', () async {
    readGoogleAccount = () async => null;
    var exchanged = false;
    exchangeGoogleCredential = (_) async {
      exchanged = true;
      return const SignupTokens(access: 'a', refresh: 'r');
    };

    expect(await signInWithGoogle(), isNull);
    expect(exchanged, isFalse);
  });

  test('exchanges the Google token and keeps the profile name', () async {
    readGoogleAccount = () async => const GoogleAccountCredential(
      idToken: 'google-id-token',
      displayName: 'Ada',
    );
    String? sent;
    exchangeGoogleCredential = (idToken) async {
      sent = idToken;
      return const SignupTokens(access: 'access', refresh: 'refresh');
    };
    readSignedInDisplayName = (_) async => 'Ada Lovelace';

    final session = await signInWithGoogle();

    expect(sent, 'google-id-token');
    expect(session?.access, 'access');
    expect(session?.refresh, 'refresh');
    expect(session?.displayName, 'Ada Lovelace');
  });
}
