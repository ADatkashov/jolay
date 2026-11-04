import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiConfig {
  /// Override with --dart-define=JOLAY_API=https://api.example.kz (Android emulator reaches the host at 10.0.2.2).
  static const baseUrl = String.fromEnvironment('JOLAY_API', defaultValue: 'http://10.0.2.2:8080');
  static String get wsUrl => '${baseUrl.replaceFirst('http', 'ws')}/ws';
}

class ApiException implements Exception {
  final int status;
  final String code;
  final String message;
  final Map<String, dynamic>? fields;
  ApiException(this.status, this.code, this.message, [this.fields]);
  bool get isNetwork => status == 0;
  @override
  String toString() => 'ApiException($status,$code)';
}

class TokenPair {
  final String access, refresh;
  const TokenPair(this.access, this.refresh);
}

/// Secure token storage (Keychain / EncryptedSharedPreferences). Tokens are never logged.
class TokenStore {
  final FlutterSecureStorage _s;
  TokenStore([FlutterSecureStorage? s]) : _s = s ?? const FlutterSecureStorage();
  Future<TokenPair?> read() async {
    try {
      final a = await _s.read(key: 'access'), r = await _s.read(key: 'refresh');
      return a == null || r == null ? null : TokenPair(a, r);
    } catch (_) { return null; }
  }
  Future<void> write(TokenPair t) async { await _s.write(key: 'access', value: t.access); await _s.write(key: 'refresh', value: t.refresh); }
  Future<void> clear() async { await _s.delete(key: 'access'); await _s.delete(key: 'refresh'); }
}

class ApiClient {
  final Dio _dio;
  final TokenStore tokens;
  Future<bool>? _refreshing;
  void Function()? onSessionExpired;

  ApiClient({Dio? dio, TokenStore? tokens})
      : _dio = dio ?? Dio(BaseOptions(baseUrl: '${ApiConfig.baseUrl}/api/v1', connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 20))),
        tokens = tokens ?? TokenStore();

  Future<dynamic> request(String method, String path, {Object? body, Map<String, dynamic>? query, Map<String, String>? headers, bool auth = true, bool retry = true}) async {
    try {
      final h = <String, String>{...?headers};
      if (auth) {
        final t = await tokens.read();
        if (t != null) h['Authorization'] = 'Bearer ${t.access}';
      }
      final r = await _dio.request<dynamic>(path, data: body, queryParameters: query, options: Options(method: method, headers: h));
      return r.data;
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      if (status == 401 && auth && retry && await _refresh()) return request(method, path, body: body, query: query, headers: headers, auth: auth, retry: false);
      if (status == 401 && auth) onSessionExpired?.call();
      final data = e.response?.data;
      if (data is Map) throw ApiException(status, (data['code'] ?? 'error').toString(), (data['message'] ?? '').toString(), (data['fields'] as Map?)?.cast<String, dynamic>());
      if (data is String && data.isNotEmpty) {
        try { final m = jsonDecode(data) as Map; throw ApiException(status, (m['code'] ?? 'error').toString(), (m['message'] ?? '').toString()); } catch (_) {}
      }
      throw ApiException(status, status == 0 ? 'network' : 'error', e.message ?? '');
    }
  }

  Future<bool> _refresh() => _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<bool> _doRefresh() async {
    final t = await tokens.read();
    if (t == null) return false;
    try {
      final r = await _dio.post<dynamic>('/auth/refresh', data: {'refreshToken': t.refresh});
      final m = r.data as Map;
      await tokens.write(TokenPair(m['accessToken'] as String, m['refreshToken'] as String));
      return true;
    } catch (_) {
      await tokens.clear();
      return false;
    }
  }

  Future<dynamic> get(String p, {Map<String, dynamic>? query, bool auth = true}) => request('GET', p, query: query, auth: auth);
  Future<dynamic> post(String p, {Object? body, Map<String, String>? headers, bool auth = true}) => request('POST', p, body: body, headers: headers, auth: auth);
  Future<dynamic> put(String p, {Object? body}) => request('PUT', p, body: body);
  Future<dynamic> delete(String p) => request('DELETE', p);
}
