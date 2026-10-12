import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog.dart';

const _accessKey = 'roamkit_access_token';
const _refreshKey = 'roamkit_refresh_token';
const _nameKey = 'roamkit_display_name';
const _balanceKey = 'roamkit_balance';

/// Session kept for the signed-in user. Tokens survive a process restart.
class AppSession extends ChangeNotifier {
  AppSession._() {
    catalogAccessToken = () => accessToken;
    catalogRefreshAuth = refreshAccess;
  }

  static final instance = AppSession._();

  String? displayName;
  String? accessToken;
  String? refreshToken;
  String? balance;

  bool get isSignedIn => accessToken != null && accessToken!.isNotEmpty;

  Future<void> restore({bool refreshBalance = true}) async {
    final prefs = await SharedPreferences.getInstance();
    accessToken = _nonEmpty(prefs.getString(_accessKey));
    refreshToken = _nonEmpty(prefs.getString(_refreshKey));
    displayName = _nonEmpty(prefs.getString(_nameKey));
    balance = _nonEmpty(prefs.getString(_balanceKey));
    notifyListeners();
    if (isSignedIn && refreshBalance) {
      await loadBalance();
    }
  }

  Future<void> signIn({
    required String displayName,
    required String accessToken,
    required String refreshToken,
  }) async {
    this.displayName = displayName;
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
    await _write();
    notifyListeners();
    await loadBalance();
  }

  Future<void> signOut() async {
    displayName = null;
    accessToken = null;
    refreshToken = null;
    balance = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessKey);
    await prefs.remove(_refreshKey);
    await prefs.remove(_nameKey);
    await prefs.remove(_balanceKey);
    notifyListeners();
  }

  /// Exchange the refresh token once. Clears the session when that fails.
  Future<bool> refreshAccess() async {
    final refresh = refreshToken;
    if (refresh == null || refresh.isEmpty) {
      await signOut();
      return false;
    }
    final client = HttpClient();
    try {
      final request = await client.postUrl(
        Uri.parse('$catalogApiBase/api/v1/auth/token/refresh/'),
      );
      final bytes = utf8.encode(jsonEncode({'refresh': refresh}));
      request.contentLength = bytes.length;
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json; charset=utf-8',
      );
      request.add(bytes);
      final response = await request.close();
      final raw = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        await signOut();
        return false;
      }
      final decoded = jsonDecode(raw);
      final access = decoded is Map ? decoded['access'] : null;
      if (access is! String || access.isEmpty) {
        await signOut();
        return false;
      }
      accessToken = access;
      await _write();
      notifyListeners();
      return true;
    } catch (_) {
      await signOut();
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> loadBalance() async {
    if (!isSignedIn) {
      return;
    }
    try {
      final amount = await _readBalance();
      if (amount == null) {
        final refreshed = await refreshAccess();
        if (!refreshed) {
          return;
        }
        final retry = await _readBalance();
        if (retry == null) {
          return;
        }
        balance = retry;
      } else {
        balance = amount;
      }
      await _write();
      notifyListeners();
    } catch (_) {
      // Keep the last saved balance when the network call fails.
    }
  }

  Future<String?> _readBalance() async {
    final token = accessToken;
    if (token == null || token.isEmpty) {
      return null;
    }
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri.parse('$catalogApiBase/api/v1/billing/balance/'),
      );
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final response = await request.close();
      final raw = await response.transform(utf8.decoder).join();
      if (response.statusCode == 401) {
        return null;
      }
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['balance'] != null) {
        return decoded['balance'].toString();
      }
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _write() async {
    final prefs = await SharedPreferences.getInstance();
    await _put(prefs, _accessKey, accessToken);
    await _put(prefs, _refreshKey, refreshToken);
    await _put(prefs, _nameKey, displayName);
    await _put(prefs, _balanceKey, balance);
  }

  Future<void> _put(SharedPreferences prefs, String key, String? value) async {
    if (value == null || value.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }
}

String? _nonEmpty(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  return value;
}
