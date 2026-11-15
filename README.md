# Universe Sigma — app mobile (Flutter)

Cliente mobile do **Universe Sigma** (gerenciador do Universe mode do WWE 2K). Fala com a mesma API do
web (`../universe_sigma_backend`) e reproduz as telas do `../universe_sigma_frontend`, em pt-BR, com tema
claro/escuro.

## Rodando

```bash
export PATH="$HOME/flutter/bin:$PATH"
flutter pub get

# API local (emulador Android enxerga o host em 10.0.2.2) — é o padrão
flutter run

# Homologação / produção: sempre HTTPS
flutter run --dart-define=API_BASE=https://SUA-API/api --dart-define=APP_ENV=homolog
flutter build apk --release --dart-define=API_BASE=https://SUA-API/api --dart-define=APP_ENV=prod
```

| Variável | Padrão | Para quê |
|---|---|---|
| `API_BASE` | `http://10.0.2.2:3000/api` | URL base da API (termina em `/api`) |
| `APP_ENV` | `dev` | `dev`, `homolog` ou `prod` |

Em aparelho físico com API local, use o IP da máquina na rede (`http://192.168.x.x:3000/api`). HTTP só é
liberado no build **debug** (Android); release exige HTTPS.

## Testes

```bash
flutter analyze
flutter test
```

Contra uma API real (cria um usuário descartável `live.<timestamp>@example.com` com o universe padrão):

```bash
flutter test test/live_api_test.dart --dart-define=LIVE_API=http://localhost:3100/api
```

Sem `LIVE_API` esse arquivo é ignorado. A suíte tem testes unitários (calendário do jogo, resultado de luta, chave de torneio, divisões, reinados,
importação, `buildBody`, cliente HTTP com refresh de token) e de widget com uma API falsa
(`test/support/`): login, menu, listas/formulários genéricos, episódios, card, torneio, divisões e
estatísticas.

## Como está organizado

```
lib/
  core/        config, API (dio + refresh automático), estado (Riverpod), tema e as regras portadas do web:
               format.dart (calendário/rodadas), segment_result.dart, segment_logic.dart,
               episodes_logic.dart, tournament_logic.dart, division_logic.dart, reign_logic.dart ...
  resources/   definições declarativas dos 16 recursos (porte de core/resources.ts do web) + buildBody
  features/    telas: auth, universes, home (painel), resources (lista/form genéricos), episodes,
               tournaments, divisions, stats, import
  shared/      scaffold/menu, componentes, imagens
```

- **CRUD genérico**: `resources/resources.dart` descreve campos/colunas/filtros de cada recurso; as telas
  `ResourceListPage` e `ResourceFormPage` renderizam qualquer um deles. Para um recurso novo, basta uma
  entrada nesse mapa (e no menu, pelo `group`).
- **Sessão**: JWT de acesso + refresh token (rotativo) em `flutter_secure_storage`. Um 401 dispara um único
  `POST /auth/refresh` (chamadas simultâneas esperam o mesmo) e a requisição é repetida; se falhar, volta ao login.
- **Imagens**: a API entrega URLs assinadas que expiram em 1h; o cache usa a URL sem a query string. Ao salvar,
  o app manda a chave `storage:...` devolvida pelo upload.
- **Regras duplicadas do web**: `format.dart`, `segment_result.dart` e `resources.dart` espelham
  `core/format.ts`, `core/segment-result.ts` e `core/resources.ts`. Mudou lá, mude aqui (os testes reproduzem
  os casos dos specs do web).

## Pendências conhecidas

- O recuperar senha do backend ainda não usa e-mail/token (fluxo temporário) e a API não tem rate limit.
- Não há ícone/splash próprios (usa os padrões do Flutter).
- iOS precisa de macOS para buildar (a configuração de permissões de câmera/galeria já está no `Info.plist`).
