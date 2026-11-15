/// Configuração por ambiente. Passe na hora de rodar/buildar:
///   flutter run --dart-define=API_BASE=https://sua-api.exemplo.com/api --dart-define=APP_ENV=homolog
/// Padrão: emulador Android falando com a API local (10.0.2.2 = máquina host).
class AppConfig {
  static const apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://10.0.2.2:3000/api',
  );
  static const env = String.fromEnvironment('APP_ENV', defaultValue: 'dev');
  static bool get isProd => env == 'prod';
}
