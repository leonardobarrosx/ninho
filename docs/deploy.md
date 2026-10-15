# Publicação

## Supabase

Use um projeto dedicado. Aplique as migrações, em ordem, e execute os testes antes de inserir dados reais. Configure confirmação de e-mail, SMTP, Site URL e as URLs de redirecionamento autorizadas. Crie dois usuários de teste em famílias diferentes para verificar isolamento no ambiente publicado.

As tabelas usadas pelo aplicativo precisam estar expostas no Data API. A migração concede permissões explícitas a `authenticated` e habilita RLS. Não desabilite RLS para resolver erros de permissão.

## Render

Crie um serviço a partir deste repositório usando o blueprint `render.yaml`, ou um serviço Docker com:

- Dockerfile: `backend/Dockerfile`
- Contexto: `backend`
- Health check: `/healthz`
- `SUPABASE_URL`: URL do projeto dedicado.
- `SUPABASE_PUBLISHABLE_KEY`: chave publishable ou anon, nunca service role.
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

O script instala a versão fixada de Flutter e executa `flutter build web`. Variáveis Dart são incorporadas em tempo de compilação: ao mudar endpoints ou a chave pública, publique novamente. Nunca coloque segredos nesse build.

Para uma prévia sem backend, defina `NINHO_DEMO=true`. O botão de demonstração fica explicitamente identificado e os dados são temporários.

Depois de obter o domínio da Vercel, configure a origem na API e o redirecionamento no Supabase Auth. Verifique cadastro, confirmação, login, recuperação de senha e acesso de duas famílias distintas.

## APK de produção

O APK de CI é de **debug**, apropriado para testes. Para um release, mantenha a chave sob controle do proprietário do app.

1. Gere uma chave com o Android Studio ou `keytool` e guarde uma cópia segura fora do repositório.
2. Crie `app/android/key.properties` (ignorado pelo Git) com `storeFile`, `storePassword`, `keyAlias`, `keyPassword`.
3. O Gradle do projeto lê esse arquivo quando presente. O build de release deve falhar se a assinatura não estiver configurada, evitando publicar uma chave de desenvolvimento por engano.
4. Rode `flutter build apk --release --dart-define-from-file=config.local.json`.

Se for publicar na Play Store, use `flutter build appbundle --release` e siga a configuração de assinatura da loja.

## Operação SaaS

Esta entrega estabelece o isolamento entre famílias e a aplicação compartilhada. Pagamentos recorrentes de assinatura não foram ativados. Defina provedor, planos e limites antes de conectar cobrança. Preços ou planos pagos nunca devem ser concedidos a partir de dados enviados pelo cliente; use webhooks autenticados e idempotentes no backend.

Documentação técnica usada:

- https://docs.flutter.dev/deployment/web
- https://docs.flutter.dev/deployment/android
- https://supabase.com/docs/guides/auth
- https://supabase.com/docs/guides/database/postgres/row-level-security
- https://render.com/docs/deploy-go-nethttp
- https://vercel.com/docs/builds/configure-a-build
