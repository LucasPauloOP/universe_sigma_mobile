# Universe Sigma — App mobile (Flutter)

Cliente mobile do **Universe Sigma** (gerenciador do Universe mode do WWE 2K). Consome a mesma API do web e reproduz as telas dele, em pt-BR, com tema claro/escuro.
- Backend: `../universe_sigma_backend` (ver CLAUDE.md dele). Web: `../universe_sigma_frontend` (Angular).
- Contratos da API: `../universe_sigma_backend/docs/API-CONTRACTS.md` e `api-contracts.json` (gerados por `npm run contracts` no backend).

## Ambiente
- Flutter 3.50 / Dart 3.14 em `~/flutter`, **fora do PATH**: `export PATH="$HOME/flutter/bin:$PATH"`.
- Máquina é WSL sem sudo e sem Chrome/emulador. JDK 17 em `~/jdk17` e Android SDK em `~/android-sdk` (instalados em espaço de usuário). Antes de buildar: `export JAVA_HOME=$HOME/jdk17 ANDROID_HOME=$HOME/android-sdk PATH="$HOME/jdk17/bin:$HOME/flutter/bin:$PATH"`.
- APK: `flutter build apk --release --dart-define=API_BASE=https://SUA-API/api --dart-define=APP_ENV=prod` → `build/app/outputs/flutter-apk/app-release.apk` (~60 MB, 1º build ~7 min). O lint de release está desligado em `android/app/build.gradle.kts` (bug interno do AGP). O APK sai assinado com a chave **debug** (serve para instalar/testar, não para loja). iOS só em macOS.
- `*.env` do backend têm segredos: nunca versionar nem imprimir.

## Comandos
- `flutter analyze` e `flutter test` (devem ficar limpos/verdes: hoje 124 testes + 1 ignorado).
- `flutter run --dart-define=API_BASE=https://SUA-API/api --dart-define=APP_ENV=homolog` (padrão: `http://10.0.2.2:3000/api`, `APP_ENV=dev`).
- Teste contra API real (cria usuário descartável `live.<ts>@example.com` com universe padrão):
  1. subir o backend: `cd ../universe_sigma_backend && NODE_ENV=test PORT=3100 JWT_SECRET=x node app.js` (usa o banco de teste do `test.env`);
  2. `flutter test test/live_api_test.dart --dart-define=LIVE_API=http://localhost:3100/api` (~5 min, banco remoto);
  3. parar o backend e apagar os usuários `live.*` do banco de teste (deleteMany por prefixo de e-mail).

## Arquitetura (`lib/`)
- `core/` — `config.dart` (API_BASE/APP_ENV), `api/` (dio + `ApiClient` com **refresh automático**: 401 → um único `POST /auth/refresh`, concorrentes esperam; falhou → limpa sessão), `providers.dart` (Riverpod: sessão, universe selecionado, `itemsProvider(key)` = cache de listas por recurso), `theme.dart`, e as **regras de negócio portadas do web**:
  `format.dart` (calendário do jogo, rodadas), `segment_result.dart`, `segment_logic.dart`, `episodes_logic.dart`, `tournament_logic.dart`, `division_logic.dart`, `reign_logic.dart`, `dashboard_logic.dart`, `import_logic.dart`.
- `resources/` — `resource_def.dart` + `resources.dart`: definições declarativas dos 16 recursos (campos, colunas, filtros, ações, `autofill`, `showIf`, `hiddenValue`) e `buildBody`. **CRUD genérico**: para um recurso novo basta uma entrada em `resources` (o menu usa `group`).
- `features/` — `auth`, `universes`, `home` (painel), `resources` (lista/form genéricos, ativação, stats, gerar episódios), `episodes` (lista, card, segmento), `tournaments`, `divisions`, `stats`, `import`.
- `shared/` — `app_scaffold.dart` (AppPage + menu), `ui.dart` (snackbars, confirm, AsyncBody, BusyButton), `net_image.dart`, `icons.dart`.
- `router.dart` — go_router com guardas (sessão → universe → `:resource` válido).
- Modelos são `Map<String, dynamic>` (`typedef Entity`, extensões em `core/models.dart`); classes tipadas só onde há lógica (`SegmentDraft`, `Round`...).

## Convenções
- **Lógica pura fora das telas**: regras ficam em `core/*_logic.dart` (testáveis sem UI); a tela só monta widgets.
- **Regras duplicadas do web — manter alinhadas**: `format.dart`, `segment_result.dart`, `resources.dart` espelham `core/format.ts`, `core/segment-result.ts`, `core/resources.ts`. Mudou lá (ou no backend: `services/bracket.js`, `timeline.js`), mude aqui e nos testes.
- Mudança de regra/tela ⇒ teste junto. Testes de widget usam o servidor falso de `test/support/` (`FakeServer`, `commonServer`, `testOverrides`); listas são preguiçosas, então role a tela (`drag`) antes de procurar widget fora da dobra.
- Erros da API viram `ApiException` (mensagem pt-BR + `details`); mostre com `showError`. Nunca engula erro.
- Imagens: a API manda URL assinada (expira em 1h); cache usa a URL sem query string (`NetImage`). Ao salvar, enviar a chave `storage:...` do upload; na edição só reenviar `imageUrl` se mudou (já no `buildBody`).
- Status do episódio: `UNPLANNED` (vermelho) → `PLANNED` (amarelo) → `DONE` (verde). O backend sincroniza sozinho: com segmentos vira PLANNED, sem nenhum volta a UNPLANNED, DONE nunca é mexido. Reabrir DONE: `reopenedStatus(n)`.

- Rivalidades: `core/rivalry_logic.dart` (lados, ganhador, rótulo) e `SegmentDraft` (`startsRivalry`/`endsRivalry`/`rivalryId`); o formulário de segmento busca `rivalries/match` (debounce) ao mudar os lutadores. Recurso no grupo "Shows".

## Armadilhas do Flutter 3.50 / pacotes
- O Material foi separado: importar `package:material_ui/material_ui.dart` (não `flutter/material.dart`, deprecado). `GlobalMaterialLocalizations.delegates` vem de lá.
- Riverpod 3: `Override` está em `package:flutter_riverpod/misc.dart`; `ProviderScope(retry: (_, _) => null)` desliga o retry automático (erro aparece com "Tentar de novo").
- `FilePicker.pickFiles` devolve a lista direto (sem `.files`); `ReorderableListView` usa `onReorderItem` (índice já ajustado).
- Android: `INTERNET` está no manifest principal; HTTP em texto claro só no manifest de debug. iOS: descrições de câmera/galeria já no `Info.plist`.

## Backend — o que o app assume
- `POST /auth/register|login` devolvem `token` + `refreshToken`; `POST /auth/refresh|logout`. Recuperar senha ainda é o fluxo temporário (sem e-mail) e não há rate limit — decisão do usuário, rever antes de publicar em loja.
- Listas: `{data,total,limit,offset}` (limite máx. 500; `api.all` pagina). Erros: `{message, details[]}`.

## Pendências / ideias
- Sem ícone/splash próprios; APK já compila, mas nunca foi rodado em emulador/aparelho. Falta keystore de release (assinatura para loja).
- URL da API: a do web (homologação) `https://universe-sigma-backend.onrender.com/api`; produção do web ainda vazia (passar por `--dart-define=API_BASE`).
- Usuários de teste do teste ao vivo podem ter sobrado no banco de teste (limpeza foi negada pelo classificador de permissões).
- Nada commitado ainda (o usuário faz commit/push).
