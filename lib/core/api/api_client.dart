import 'dart:async';

import 'package:dio/dio.dart';

import '../config.dart';
import '../models.dart';
import 'api_exception.dart';
import 'token_store.dart';

/// Cliente HTTP da API. Equivale ao `api.ts` + `auth.interceptor.ts` do web:
///  - Bearer em toda chamada (menos login/registro/refresh);
///  - 401 → tenta `POST /auth/refresh` UMA vez (concorrentes esperam o mesmo refresh)
///    e repete a chamada; se falhar, limpa a sessão e avisa [onSessionExpired];
///  - erros viram [ApiException] com a mensagem em português.
class ApiClient {
  ApiClient({
    required this.tokens,
    Dio? dio,
    Dio? refreshDio,
    String? baseUrl,
    this.onSessionExpired,
  })  : dio = dio ?? Dio(BaseOptions(baseUrl: baseUrl ?? AppConfig.apiBase)),
        // ignore: prefer_initializing_formals
        _refreshDio = refreshDio {
    this.dio.options.connectTimeout = const Duration(seconds: 20);
    this.dio.options.receiveTimeout = const Duration(seconds: 60);
    this.dio.interceptors.add(_AuthInterceptor(this));
  }

  final Dio dio;
  // Dio sem interceptor para o refresh (evita laço com o 401); injetável nos testes.
  Dio? _refreshDio;
  final TokenStore tokens;
  void Function()? onSessionExpired;

  /// Universe selecionado: as rotas do universe viram `/universes/{id}/...`.
  String? universeId;

  Completer<bool>? _refreshing;

  static const _noAuth = ['/auth/login', '/auth/register', '/auth/refresh', '/auth/forgot-password', '/auth/reset-password'];

  /// Troca o refresh token por um novo par. Chamadas simultâneas compartilham o mesmo refresh.
  Future<bool> refreshSession() {
    final running = _refreshing;
    if (running != null) return running.future;
    final c = _refreshing = Completer<bool>();
    () async {
      try {
        final rt = await tokens.refresh;
        if (rt == null) return c.complete(false);
        final clean = _refreshDio ??= Dio(BaseOptions(baseUrl: dio.options.baseUrl));
        final res = await clean.post('/auth/refresh', data: {'refreshToken': rt});
        await tokens.save(
          access: res.data['token'] as String,
          refresh: res.data['refreshToken'] as String?,
        );
        c.complete(true);
      } catch (_) {
        c.complete(false);
      } finally {
        _refreshing = null;
      }
    }();
    return c.future;
  }

  String _scoped(String path) {
    if (path.startsWith('/')) return path; // rota absoluta (auth, universes)
    final id = universeId;
    if (id == null) throw ApiException('Nenhum universe selecionado.');
    return '/universes/$id/$path';
  }

  Future<T> _run<T>(Future<Response<dynamic>> Function() call, T Function(dynamic data) map) async {
    try {
      final res = await call();
      return map(res.data);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// GET de uma rota do universe (ou absoluta, se começar com `/`).
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _run(() => dio.get(_scoped(path), queryParameters: query), (d) => d);

  Future<dynamic> post(String path, {Object? body, Map<String, dynamic>? query}) =>
      _run(() => dio.post(_scoped(path), data: body, queryParameters: query), (d) => d);

  Future<dynamic> put(String path, {Object? body}) =>
      _run(() => dio.put(_scoped(path), data: body), (d) => d);

  Future<void> delete(String path) =>
      _run(() => dio.delete(_scoped(path)), (_) {});

  /// Lista paginada (`{data,total}`).
  Future<Page> page(String path, {Map<String, dynamic>? query, int limit = 500, int offset = 0}) async {
    final d = await get(path, query: {...?query, 'limit': limit, 'offset': offset});
    return Page(
      (d['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      (d['total'] as num).toInt(),
    );
  }

  /// Todos os registros (pagina de 500 em 500).
  Future<List<Entity>> all(String path, {Map<String, dynamic>? query}) async {
    final out = <Entity>[];
    var offset = 0;
    while (true) {
      final p = await page(path, query: query, offset: offset);
      out.addAll(p.data);
      offset += p.data.length;
      if (p.data.isEmpty || offset >= p.total) return out;
    }
  }

  Future<int> count(String path, {Map<String, dynamic>? query}) async =>
      (await page(path, query: query, limit: 1)).total;

  /// Upload de imagem (`POST uploads`). Devolve `{imageUrl, url}`.
  Future<({String imageUrl, String url})> uploadImage(String filePath) async {
    final form = FormData.fromMap({'file': await MultipartFile.fromFile(filePath)});
    final d = await _run(() => dio.post(_scoped('uploads'), data: form), (d) => d);
    return (imageUrl: d['imageUrl'] as String, url: d['url'] as String);
  }

  /// Upload de arquivo genérico (planilha) em [path] com campos extras.
  Future<dynamic> upload(
    String path,
    String filePath, {
    Map<String, dynamic>? fields,
    Map<String, dynamic>? query,
  }) async {
    final form = FormData.fromMap({
      ...?fields,
      'file': await MultipartFile.fromFile(filePath),
    });
    return _run(() => dio.post(_scoped(path), data: form, queryParameters: query), (d) => d);
  }
}

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this.c);
  final ApiClient c;

  bool _isNoAuth(RequestOptions o) =>
      ApiClient._noAuth.any((p) => o.path.endsWith(p));

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (!_isNoAuth(options)) {
      final t = await c.tokens.access;
      if (t != null) options.headers['Authorization'] = 'Bearer $t';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final req = err.requestOptions;
    final is401 = err.response?.statusCode == 401;
    if (!is401 || _isNoAuth(req) || req.extra['retried'] == true) {
      return handler.next(err);
    }
    if (await c.refreshSession()) {
      try {
        req.extra['retried'] = true;
        req.headers['Authorization'] = 'Bearer ${await c.tokens.access}';
        return handler.resolve(await c.dio.fetch(req));
      } on DioException catch (e) {
        return handler.next(e);
      }
    }
    await c.tokens.clear();
    c.onSessionExpired?.call();
    handler.next(err);
  }
}
