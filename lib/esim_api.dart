import 'dart:convert';
import 'dart:io';

import 'catalog.dart';
import 'esim.dart';

/// Personal eSIMs, including archived, so the list can group them.
Future<List<OwnedEsim>> fetchMyEsims() async {
  final esims = <OwnedEsim>[];
  var next = '$catalogApiBase/api/v1/me/esims/?include_archived=true';
  var page = 0;
  while (next.isNotEmpty && page < 40) {
    page += 1;
    final body = await _getAuthorized(Uri.parse(next));
    final json = jsonDecode(body);
    if (json is! Map) {
      break;
    }
    final results = json['results'];
    if (results is List) {
      for (final item in results) {
        if (item is Map) {
          esims.add(OwnedEsim.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    final rawNext = json['next'];
    next = rawNext is String ? rawNext : '';
  }
  return esims;
}

/// Presentation-only visibility. The eSIM status itself stays unchanged.
Future<void> setEsimArchived(int esimId, {required bool archive}) {
  final action = archive ? 'archive' : 'unarchive';
  return _postAuthorized(
    Uri.parse('$catalogApiBase/api/v1/me/esims/$esimId/$action/'),
  );
}

Future<void> _postAuthorized(Uri uri) async {
  final client = HttpClient();
  try {
    Future<HttpClientResponse> send() async {
      final request = await client.postUrl(uri);
      final token = catalogAccessToken();
      if (token != null && token.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      final bytes = utf8.encode('{}');
      request.contentLength = bytes.length;
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json; charset=utf-8',
      );
      request.add(bytes);
      return request.close();
    }

    var response = await send();
    if (response.statusCode == 401) {
      await response.transform(utf8.decoder).join();
      await catalogRefreshAuth();
      response = await send();
    }
    await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
  } finally {
    client.close(force: true);
  }
}

Future<String> _getAuthorized(Uri uri) async {
  final client = HttpClient();
  try {
    Future<HttpClientResponse> send() async {
      final request = await client.getUrl(uri);
      final token = catalogAccessToken();
      if (token != null && token.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      return request.close();
    }

    var response = await send();
    if (response.statusCode == 401) {
      await response.transform(utf8.decoder).join();
      await catalogRefreshAuth();
      response = await send();
    }
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    return body;
  } finally {
    client.close(force: true);
  }
}
