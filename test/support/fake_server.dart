import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universe_sigma_mobile/core/api/api_client.dart';
import 'package:universe_sigma_mobile/core/api/token_store.dart';
import 'package:universe_sigma_mobile/core/providers.dart';

typedef Handler = (int, Object?) Function(RequestOptions o);

/// Servidor falso para testes de widget: rotas por "METHOD /path" (sem o prefixo da base).
class FakeServer implements HttpClientAdapter {
  FakeServer(this.routes);
  final Map<String, Handler> routes;
  final calls = <String>[];
  final bodies = <String, Object?>{};

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    final key = '${o.method} ${o.path}';
    calls.add(key);
    bodies[key] = o.data;
    final h = routes[key];
    final (status, data) = h != null ? h(o) : (404, {'success': false, 'message': 'Rota não encontrada: $key'});
    return ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {Headers.contentTypeHeader: ['application/json']},
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> page(List<Map<String, dynamic>> data) =>
    {'data': data, 'total': data.length, 'limit': 500, 'offset': 0};

/// Monta o `ProviderScope` de teste: prefs vazias (ou com [prefs]), tokens em memória e a API falsa.
Future<List<Override>> testOverrides(
  FakeServer server, {
  Map<String, Object> prefs = const {},
  String? token,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final tokens = MemoryTokenStore();
  if (token != null) await tokens.save(access: token, refresh: 'r');
  return [
    sharedPrefsProvider.overrideWithValue(sp),
    tokenStoreProvider.overrideWithValue(tokens),
    apiProvider.overrideWith((ref) {
      final api = ApiClient(
        tokens: tokens,
        dio: Dio(BaseOptions(baseUrl: 'http://fake/api'))..httpClientAdapter = server,
        refreshDio: Dio(BaseOptions(baseUrl: 'http://fake/api'))..httpClientAdapter = server,
      );
      api.universeId = ref.read(selectedUniverseProvider);
      ref.listen<String?>(selectedUniverseProvider, (_, id) => api.universeId = id);
      api.onSessionExpired = () => ref.read(authProvider.notifier).sessionExpired();
      return api;
    }),
  ];
}
