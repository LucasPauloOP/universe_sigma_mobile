import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Guarda os tokens. Interface própria para poder trocar por uma versão em memória nos testes.
abstract class TokenStore {
  Future<String?> get access;
  Future<String?> get refresh;
  Future<void> save({required String access, String? refresh});
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
      : _s = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _s;
  static const _kAccess = 'universe-sigma:token';
  static const _kRefresh = 'universe-sigma:refresh';

  @override
  Future<String?> get access => _s.read(key: _kAccess);
  @override
  Future<String?> get refresh => _s.read(key: _kRefresh);

  @override
  Future<void> save({required String access, String? refresh}) async {
    await _s.write(key: _kAccess, value: access);
    if (refresh != null) await _s.write(key: _kRefresh, value: refresh);
  }

  @override
  Future<void> clear() async {
    await _s.delete(key: _kAccess);
    await _s.delete(key: _kRefresh);
  }
}

class MemoryTokenStore implements TokenStore {
  String? _a;
  String? _r;
  @override
  Future<String?> get access async => _a;
  @override
  Future<String?> get refresh async => _r;
  @override
  Future<void> save({required String access, String? refresh}) async {
    _a = access;
    if (refresh != null) _r = refresh;
  }

  @override
  Future<void> clear() async {
    _a = null;
    _r = null;
  }
}
