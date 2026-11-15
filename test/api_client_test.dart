import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universe_sigma_mobile/core/api/api_client.dart';
import 'package:universe_sigma_mobile/core/api/api_exception.dart';
import 'package:universe_sigma_mobile/core/api/token_store.dart';

/// Servidor falso: valida o Bearer e conta as chamadas de refresh.
class FakeServer implements HttpClientAdapter {
  String validAccess = 'access-2';
  bool refreshOk = true;
  int refreshCalls = 0;
  final calls = <String>[];

  ResponseBody _json(int status, Object body) => ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    calls.add('${o.method} ${o.path}');
    if (o.path.endsWith('/auth/refresh')) {
      refreshCalls++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return refreshOk
          ? _json(200, {'token': validAccess, 'refreshToken': 'refresh-2'})
          : _json(401, {'success': false, 'message': 'Refresh token inválido'});
    }
    if (o.headers['Authorization'] != 'Bearer $validAccess') {
      return _json(401, {'success': false, 'message': 'Token inválido ou expirado'});
    }
    if (o.path.endsWith('/wrestlers')) {
      return _json(200, {
        'data': [
          {'id': 'a'}
        ],
        'total': 1,
        'limit': 500,
        'offset': 0,
      });
    }
    if (o.path.endsWith('/boom')) {
      return _json(422, {'success': false, 'message': 'Dados inválidos', 'details': ['"name" é obrigatório']});
    }
    return _json(200, {'ok': true});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late FakeServer server;
  late MemoryTokenStore tokens;
  late ApiClient api;
  var expired = 0;

  setUp(() async {
    server = FakeServer();
    tokens = MemoryTokenStore();
    await tokens.save(access: 'access-1', refresh: 'refresh-1');
    expired = 0;
    Dio fake() => Dio(BaseOptions(baseUrl: 'http://fake/api'))..httpClientAdapter = server;
    api = ApiClient(
      tokens: tokens,
      dio: fake(),
      refreshDio: fake(),
      onSessionExpired: () => expired++,
    )..universeId = 'u1';
  });

  test('401 → refresh → repete a chamada com o token novo', () async {
    final all = await api.all('wrestlers');
    expect(all.single['id'], 'a');
    expect(server.refreshCalls, 1);
    expect(await tokens.access, 'access-2');
    expect(await tokens.refresh, 'refresh-2');
    expect(expired, 0);
  });

  test('várias chamadas com token vencido disparam um único refresh', () async {
    final results = await Future.wait([
      api.all('wrestlers'),
      api.all('wrestlers'),
      api.count('wrestlers').then((n) => [<String, dynamic>{'n': n}]),
    ]);
    expect(results.length, 3);
    expect(server.refreshCalls, 1);
    expect(await tokens.access, 'access-2');
  });

  test('refresh que falha limpa a sessão e avisa a UI', () async {
    server.refreshOk = false;
    await expectLater(api.get('wrestlers'), throwsA(isA<ApiException>()));
    expect(expired, 1);
    expect(await tokens.access, isNull);
    expect(await tokens.refresh, isNull);
  });

  test('sem refresh token guardado: 401 encerra a sessão sem tentar refresh', () async {
    await tokens.clear();
    await expectLater(api.get('wrestlers'), throwsA(isA<ApiException>()));
    expect(server.refreshCalls, 0);
    expect(expired, 1);
  });

  test('erro 422 vira ApiException com details', () async {
    await tokens.save(access: 'access-2');
    try {
      await api.get('boom');
      fail('deveria lançar');
    } on ApiException catch (e) {
      expect(e.status, 422);
      expect(e.message, 'Dados inválidos');
      expect(e.details, ['"name" é obrigatório']);
      expect(e.full, contains('obrigatório'));
    }
  });

  test('rota do universe usa /universes/{id}/; rota absoluta não', () async {
    await tokens.save(access: 'access-2');
    await api.get('wrestlers');
    await api.get('/auth/me');
    expect(server.calls, ['GET /universes/u1/wrestlers', 'GET /auth/me']);
  });

  test('sem universe selecionado lança erro claro', () async {
    api.universeId = null;
    expect(() => api.get('wrestlers'), throwsA(isA<ApiException>()));
  });

  test('all() pagina até o total', () async {
    await tokens.save(access: 'access-2');
    expect((await api.all('wrestlers')).length, 1);
    expect(await api.count('wrestlers'), 1);
  });
}
