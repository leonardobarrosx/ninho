# Publicação

## Supabase

Use um projeto dedicado. Aplique as migrações, em ordem, e execute os testes antes de inserir dados reais. Configure confirmação de e-mail, SMTP, Site URL e as URLs de redirecionamento autorizadas. Crie dois usuários de teste em famílias diferentes para verificar isolamento no ambiente publicado.

As tabelas usadas pelo aplicativo precisam estar expostas no Data API. A migração concede permissões explícitas a `authenticated` e habilita RLS. Não desabilite RLS para resolver erros de permissão.

A migração `202610170001_account_deletion.sql` cria um gatilho em `auth.users` que decide o destino das famílias de quem exclui a conta: as que têm outras pessoas passam para quem entrou primeiro, e as demais são apagadas com seus registros. Depois de aplicá-la, confira em Database › Triggers que `before_user_deleted` existe em `auth.users`. Sem ele, excluir quem criou uma família falha em vez de apagar dados compartilhados.

## Render

Crie um serviço a partir deste repositório usando o blueprint `render.yaml`, ou um serviço Docker com:

- Dockerfile: `backend/Dockerfile`
- Contexto: `backend`
- Health check: `/healthz`
- `SUPABASE_URL`: URL do projeto dedicado.
- `SUPABASE_PUBLISHABLE_KEY`: chave publishable ou anon, nunca service role.
- `SUPABASE_SECRET_KEY`: chave secreta (ou service role) do projeto. A API a usa apenas para excluir, pela API admin do Auth, o usuário da sessão verificada. Sem ela, a exclusão de conta responde que está indisponível, o que não atende à Google Play. Ela nunca vai para o app nem para a Vercel.
- `ALLOWED_ORIGINS`: URLs web exatas, separadas por vírgula, sem barra final. Inclua só o domínio de produção e as prévias que forem necessárias.

O blueprint usa o plano gratuito como ponto de partida. Confirme limites e custos na conta antes de criar o serviço. O processo lê `PORT`, aceita encerramento gracioso e roda como usuário sem privilégios no contêiner.

## Vercel

Importe o repositório. A raiz do projeto é a raiz do monorepo, e não `app/`.

`vercel.json` define o build e a pasta de saída. Configure estas variáveis antes do build:

| Variável | Valor |
| --- | --- |
| `API_URL` | URL HTTPS da API no Render |
| `SUPABASE_URL` | URL do Supabase |
| `SUPABASE_PUBLISHABLE_KEY` | Chave pública do projeto |
| `PRIVACY_CONTROLLER` | Nome de quem responde pelos dados, citado na política de privacidade |
| `PRIVACY_EMAIL` | E-mail de contato para privacidade e pedidos de exclusão de conta |
| `ADMOB_PUBLISHER_ID` | Opcional: `pub-` e 16 dígitos, para publicar `/app-ads.txt` |

O script instala a versão fixada de Flutter e executa `flutter build web`. Variáveis Dart são incorporadas em tempo de compilação: ao mudar endpoints ou a chave pública, publique novamente. Nunca coloque segredos nesse build.

Para uma prévia sem backend, defina `NINHO_DEMO=true`. O botão de demonstração fica explicitamente identificado e os dados são temporários. Nesse modo, a política de privacidade sai com o responsável e o contato marcados como "a definir".

O build publica, além do app, a política de privacidade em `/privacidade` e as instruções de exclusão de conta em `/excluir-conta`. Essas são as URLs pedidas pelo Play Console.

Depois de obter o domínio da Vercel, configure a origem na API e o redirecionamento no Supabase Auth. Verifique cadastro, confirmação, login, recuperação de senha e acesso de duas famílias distintas.

## Android de produção

O APK de CI é de **debug**, apropriado para testes. Para um release, mantenha a chave sob controle do proprietário do app.

1. Gere uma chave com o Android Studio ou `keytool` e guarde uma cópia segura fora do repositório.
2. Crie `app/android/key.properties` (ignorado pelo Git) com `storeFile` (relativo a `app/android/` ou absoluto), `storePassword`, `keyAlias` e `keyPassword`.
3. O Gradle do projeto lê esse arquivo quando presente. O build de release falha se a assinatura não estiver configurada, evitando publicar uma chave de desenvolvimento por engano, e também quando só um dos IDs do AdMob é informado.
4. Para a Play Store, rode `flutter build appbundle --release --dart-define-from-file=config.local.json`. Para instalar direto num aparelho, `flutter build apk --release` com o mesmo arquivo.

O roteiro da Google Play, com AdMob, assinatura pela loja e os formulários do Play Console, está em `docs/play-store.md`.

## Operação SaaS

Esta entrega estabelece o isolamento entre famílias e a aplicação compartilhada. Pagamentos recorrentes de assinatura não foram ativados. Defina provedor, planos e limites antes de conectar cobrança. Preços ou planos pagos nunca devem ser concedidos a partir de dados enviados pelo cliente; use webhooks autenticados e idempotentes no backend.

Documentação técnica usada:

- https://docs.flutter.dev/deployment/web
- https://docs.flutter.dev/deployment/android
- https://supabase.com/docs/guides/auth
- https://supabase.com/docs/guides/database/postgres/row-level-security
- https://render.com/docs/deploy-go-nethttp
- https://vercel.com/docs/builds/configure-a-build
- https://developers.google.com/admob/flutter/quick-start
- https://developers.google.com/admob/android/privacy/play-data-disclosure
- https://developer.android.com/google/play/requirements/target-sdk
