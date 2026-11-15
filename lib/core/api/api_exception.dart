import 'package:dio/dio.dart';

/// Erro da API já em português: `message` + `details[]` (422 do Joi).
class ApiException implements Exception {
  ApiException(this.message, {this.details = const [], this.status});

  final String message;
  final List<String> details;
  final int? status;

  bool get isUnauthorized => status == 401;

  factory ApiException.fromDio(DioException e) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    if (data is Map && data['message'] is String) {
      return ApiException(
        data['message'] as String,
        details: (data['details'] as List? ?? const []).map((d) => '$d').toList(),
        status: status,
      );
    }
    if (status == null) {
      return ApiException('Não foi possível conectar ao servidor.');
    }
    return ApiException('Erro $status ao falar com o servidor.', status: status);
  }

  /// Mensagem + detalhes, para mostrar num snackbar/diálogo.
  String get full => details.isEmpty ? message : '$message\n• ${details.join('\n• ')}';

  @override
  String toString() => full;
}
