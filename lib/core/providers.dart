import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/api_client.dart';
import 'api/api_exception.dart';
import 'api/token_store.dart';
import 'models.dart';

/// Sobrescrito no `main()` com a instância real.
final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

// ───────────────────────────── universe selecionado ─────────────────────────────

const _kUniverse = 'universe-sigma:universe';

class SelectedUniverse extends Notifier<String?> {
  @override
  String? build() => ref.read(sharedPrefsProvider).getString(_kUniverse);

  Future<void> select(String? id) async {
    state = id;
    final p = ref.read(sharedPrefsProvider);
    if (id == null) {
      await p.remove(_kUniverse);
    } else {
      await p.setString(_kUniverse, id);
    }
  }
}

final selectedUniverseProvider =
    NotifierProvider<SelectedUniverse, String?>(SelectedUniverse.new);

// ─────────────────────────────────── cliente HTTP ───────────────────────────────────

final apiProvider = Provider<ApiClient>((ref) {
  final api = ApiClient(tokens: ref.watch(tokenStoreProvider));
  api.universeId = ref.read(selectedUniverseProvider);
  ref.listen<String?>(selectedUniverseProvider, (_, id) => api.universeId = id);
  api.onSessionExpired = () => ref.read(authProvider.notifier).sessionExpired();
  return api;
});

// ──────────────────────────────────── sessão ────────────────────────────────────

enum AuthStatus { loading, loggedOut, loggedIn }

class AuthState {
  const AuthState(this.status, {this.user, this.message});
  final AuthStatus status;
  final Entity? user;

  /// Aviso para a tela de login (ex.: "Sessão expirada").
  final String? message;
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    Future.microtask(bootstrap);
    return const AuthState(AuthStatus.loading);
  }

  ApiClient get _api => ref.read(apiProvider);
  TokenStore get _tokens => ref.read(tokenStoreProvider);

  /// Restaura a sessão: token guardado + `GET /auth/me` (o interceptor renova se preciso).
  Future<void> bootstrap() async {
    if (await _tokens.access == null && await _tokens.refresh == null) {
      state = const AuthState(AuthStatus.loggedOut);
      return;
    }
    try {
      final me = Map<String, dynamic>.from(await _api.get('/auth/me') as Map);
      state = AuthState(AuthStatus.loggedIn, user: me);
    } on ApiException catch (e) {
      // 401 já limpou a sessão (sessionExpired); falha de rede mantém os tokens
      if (state.status == AuthStatus.loading) {
        state = AuthState(AuthStatus.loggedOut, message: e.status == null ? e.message : null);
      }
    }
  }

  Future<void> _enter(dynamic d) async {
    await _tokens.save(access: d['token'] as String, refresh: d['refreshToken'] as String?);
    state = AuthState(AuthStatus.loggedIn, user: Map<String, dynamic>.from(d['user'] as Map));
  }

  Future<void> login(String email, String password) async =>
      _enter(await _api.post('/auth/login', body: {'email': email, 'password': password}));

  Future<void> register(String email, String password, {String? name, bool useTemplate = true}) async {
    final d = await _api.post('/auth/register', body: {
      'email': email,
      'password': password,
      if (name != null && name.isNotEmpty) 'name': name,
      'useTemplate': useTemplate,
    });
    // o registro já cria o universe padrão: seleciona
    final universe = d['universe'];
    if (universe is Map) {
      await ref.read(selectedUniverseProvider.notifier).select(universe['id'] as String);
    }
    await _enter(d);
  }

  Future<void> logout() async {
    final rt = await _tokens.refresh;
    if (rt != null) {
      try {
        await _api.post('/auth/logout', body: {'refreshToken': rt});
      } on ApiException {
        // sem rede/expirado: segue limpando localmente
      }
    }
    await _tokens.clear();
    await ref.read(selectedUniverseProvider.notifier).select(null);
    state = const AuthState(AuthStatus.loggedOut);
  }

  void sessionExpired() {
    state = const AuthState(AuthStatus.loggedOut, message: 'Sessão expirada. Entre novamente.');
  }
}

final authProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

// ──────────────────────────────── universes do usuário ────────────────────────────────

/// Lista de universes; se o salvo não existe mais, seleciona o primeiro.
final universesProvider = FutureProvider<List<Entity>>((ref) async {
  final auth = ref.watch(authProvider);
  if (auth.status != AuthStatus.loggedIn) return const [];
  final api = ref.watch(apiProvider);
  final raw = await api.get('/universes') as List;
  final list = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final sel = ref.read(selectedUniverseProvider);
  if (list.isNotEmpty && !list.any((u) => u.id == sel)) {
    await ref.read(selectedUniverseProvider.notifier).select(list.first.id);
  } else if (list.isEmpty && sel != null) {
    await ref.read(selectedUniverseProvider.notifier).select(null);
  }
  return list;
});

// ───────────────────────────── listas por recurso (cache) ─────────────────────────────

/// Todos os registros de um recurso do universe atual. Faz o papel do `Refs` do web:
/// alimenta selects, nomes de colunas e as próprias listagens. Invalide depois de gravar.
final itemsProvider = FutureProvider.family<List<Entity>, String>((ref, key) {
  ref.watch(selectedUniverseProvider); // trocou de universe: recarrega
  return ref.watch(apiProvider).all(key);
});

/// Atualiza várias listas de uma vez após uma mudança.
void invalidateItems(WidgetRef ref, Iterable<String> keys) {
  for (final k in keys) {
    ref.invalidate(itemsProvider(k));
  }
}
