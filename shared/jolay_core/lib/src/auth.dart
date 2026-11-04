import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';

class AuthUser {
  final String id, fullName, phone;
  final String? email;
  final List<String> roles;
  final String locale;
  const AuthUser({required this.id, required this.fullName, required this.phone, this.email, required this.roles, required this.locale});
  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
        id: j['id'] as String, fullName: j['fullName'] as String, phone: j['phone'] as String, email: j['email'] as String?,
        roles: (j['roles'] as List).cast<String>(), locale: (j['locale'] ?? 'kk') as String);
}

enum AuthStatus { unknown, signedOut, signedIn }

class AuthState {
  final AuthStatus status;
  final AuthUser? user;
  const AuthState(this.status, [this.user]);
}

final apiProvider = Provider<ApiClient>((ref) {
  final c = ApiClient();
  c.onSessionExpired = () => ref.read(authProvider.notifier).expire();
  return c;
});

/// Required role for this app ("CUSTOMER" or "DRIVER"); overridden in each app's main().
final requiredRoleProvider = Provider<String>((ref) => 'CUSTOMER');

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState(AuthStatus.unknown);

  ApiClient get _api => ref.read(apiProvider);

  /// Called from the splash screen: restores a session from secure storage if the stored token still works.
  Future<void> restore() async {
    final t = await _api.tokens.read();
    if (t == null) { state = const AuthState(AuthStatus.signedOut); return; }
    try {
      final me = await _api.get('/customers/me') as Map<String, dynamic>;
      state = AuthState(AuthStatus.signedIn, AuthUser.fromJson(me));
    } on ApiException catch (e) {
      if (e.isNetwork) { state = const AuthState(AuthStatus.signedOut); return; }
      await _api.tokens.clear();
      state = const AuthState(AuthStatus.signedOut);
    }
  }

  Future<void> register({required String fullName, required String phone, String? email, required String password, required String locale}) async {
    await _api.post('/auth/register', auth: false, body: {
      'fullName': fullName, 'phone': phone, if (email != null && email.isNotEmpty) 'email': email, 'password': password,
      'role': ref.read(requiredRoleProvider), 'acceptTerms': true, 'locale': locale,
    });
  }

  Future<void> resendOtp(String phone) => _api.post('/auth/resend-otp', auth: false, body: {'phone': phone});

  Future<void> verifyOtp(String phone, String code) async => _accept(await _api.post('/auth/verify-otp', auth: false, body: {'phone': phone, 'code': code}) as Map<String, dynamic>);

  Future<void> login(String identifier, String password) async => _accept(await _api.post('/auth/login', auth: false, body: {'identifier': identifier, 'password': password}) as Map<String, dynamic>);

  Future<void> _accept(Map<String, dynamic> j) async {
    final user = AuthUser.fromJson(j['user'] as Map<String, dynamic>);
    if (!user.roles.contains(ref.read(requiredRoleProvider))) throw ApiException(403, 'forbidden', 'wrong app for this account');
    await _api.tokens.write(TokenPair(j['accessToken'] as String, j['refreshToken'] as String));
    state = AuthState(AuthStatus.signedIn, user);
  }

  Future<void> forgot(String identifier) => _api.post('/auth/forgot-password', auth: false, body: {'identifier': identifier});
  Future<void> reset(String identifier, String code, String newPassword) => _api.post('/auth/reset-password', auth: false, body: {'identifier': identifier, 'code': code, 'newPassword': newPassword});

  Future<void> updateProfile({String? fullName, String? email, String? locale}) async {
    final me = await _api.put('/customers/me', body: {if (fullName != null) 'fullName': fullName, if (email != null) 'email': email, if (locale != null) 'locale': locale}) as Map<String, dynamic>;
    state = AuthState(AuthStatus.signedIn, AuthUser.fromJson(me));
  }

  Future<void> logout() async {
    final t = await _api.tokens.read();
    if (t != null) { try { await _api.post('/auth/logout', auth: false, body: {'refreshToken': t.refresh}); } catch (_) {} }
    await _api.tokens.clear();
    state = const AuthState(AuthStatus.signedOut);
  }

  Future<void> deleteAccount() async {
    await _api.delete('/customers/me');
    await _api.tokens.clear();
    state = const AuthState(AuthStatus.signedOut);
  }

  void expire() { state = const AuthState(AuthStatus.signedOut); }
}

final authProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);
