import 'dart:convert';
import 'dart:io';

import 'catalog.dart';

class SignupTokens {
  const SignupTokens({required this.access, required this.refresh});

  final String access;
  final String refresh;
}

class SignupFailure implements Exception {
  SignupFailure(this.message, {this.fields = const {}});

  final String message;
  final Map<String, String> fields;

  @override
  String toString() => message;
}

const _fieldErrorKeys = {'first_name', 'last_name', 'email', 'password'};

const _requiredFieldHints = {
  'first_name': 'Enter your first name.',
  'email': 'Enter your email.',
  'password': 'Enter a password.',
};

Future<void> startSignup({
  required String firstName,
  required String lastName,
  required String email,
  required String password,
}) {
  return _post('/api/v1/auth/signup/', {
    'first_name': firstName.trim(),
    'last_name': lastName.trim(),
    'email': email.trim(),
    'password': password,
  });
}

Future<void> resendSignupCode(String email) {
  return _post('/api/v1/auth/signup/resend/', {'email': email.trim()});
}

Future<SignupTokens> confirmSignup({
  required String email,
  required String code,
}) async {
  final body = await _post('/api/v1/auth/signup/confirm/', {
    'email': email.trim(),
    'code': code,
  });
  return SignupTokens(
    access: body['access'] as String? ?? '',
    refresh: body['refresh'] as String? ?? '',
  );
}

Future<SignupTokens> logIn({
  required String email,
  required String password,
  String? turnstileToken,
}) async {
  final payload = <String, String>{'email': email.trim(), 'password': password};
  final token = turnstileToken?.trim() ?? '';
  if (token.isNotEmpty) {
    payload['turnstile_token'] = token;
  }
  final body = await _post(
    '/api/v1/auth/token/',
    payload,
    unauthorizedMessage: 'Email or password is incorrect.',
  );
  return SignupTokens(
    access: body['access'] as String? ?? '',
    refresh: body['refresh'] as String? ?? '',
  );
}

Future<String> currentDisplayName(String accessToken) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse('$catalogApiBase/api/v1/auth/me/'),
    );
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
    final response = await request.close();
    final raw = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      return '';
    }
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      final name = decoded['display_name'];
      if (name is String) {
        return name.trim();
      }
    }
    return '';
  } catch (_) {
    return '';
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, dynamic>> _post(
  String path,
  Map<String, String> payload, {
  String? unauthorizedMessage,
}) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse('$catalogApiBase$path'));
    final bytes = utf8.encode(jsonEncode(payload));
    request.contentLength = bytes.length;
    request.headers.set(
      HttpHeaders.contentTypeHeader,
      'application/json; charset=utf-8',
    );
    request.add(bytes);
    final response = await request.close();
    final raw = await response.transform(utf8.decoder).join();
    if (response.statusCode == 401 && unauthorizedMessage != null) {
      throw SignupFailure(unauthorizedMessage);
    }
    if (response.statusCode != 200) {
      throw signupFailureFromBody(raw);
    }
    if (raw.trim().isEmpty) {
      return const {};
    }
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    return const {};
  } on SignupFailure {
    rethrow;
  } catch (_) {
    throw SignupFailure('Could not reach RoamKit.');
  } finally {
    client.close(force: true);
  }
}

SignupFailure signupFailureFromBody(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      final fields = <String, String>{};
      final banner = <String>[];
      for (final entry in decoded.entries) {
        final key = entry.key.toString();
        final text = _messages(entry.value)
            .map((message) => _rewriteFieldMessage(key, message))
            .where((message) => message.isNotEmpty)
            .join(' ');
        if (text.isEmpty) {
          continue;
        }
        if (_fieldErrorKeys.contains(key)) {
          fields[key] = text;
        } else {
          banner.add(text);
        }
      }
      if (fields.isNotEmpty || banner.isNotEmpty) {
        return SignupFailure(banner.join(' '), fields: fields);
      }
    }
  } catch (_) {
    return SignupFailure('Could not sign up.');
  }
  return SignupFailure('Could not sign up.');
}

List<String> _messages(Object? value) {
  if (value is List) {
    return value.map((item) => item.toString()).toList();
  }
  if (value is String) {
    return [value];
  }
  return const [];
}

String _rewriteFieldMessage(String key, String message) {
  final hint = _requiredFieldHints[key];
  if (hint != null && message.trim() == 'This field is required.') {
    return hint;
  }
  return message;
}
