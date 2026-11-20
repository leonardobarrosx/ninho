# Publicação

## Supabase

Use um projeto dedicado. Aplique as migrações, em ordem, e execute os testes antes de inserir dados reais. Configure confirmação de e-mail, SMTP, Site URL e as URLs de redirecionamento autorizadas. Crie dois usuários de teste em famílias diferentes para verificar isolamento no ambiente publicado.

As tabelas usadas pelo aplicativo precisam estar expostas no Data API. A migração concede permissões explícitas a `authenticated` e habilita RLS. Não desabilite RLS para resolver erros de permissão.

A migração `202610170001_account_deletion.sql` cria um gatilho em `auth.users` que decide o destino das famílias de quem exclui a conta: as que têm outras pessoas passam para quem entrou primeiro, e as demais são apagadas com seus registros. Depois de aplicá-la, confira em Database › Triggers que `before_user_deleted` existe em `auth.users`. Sem ele, excluir quem criou uma família falha em vez de apagar dados compartilhados.

### Enxoval e lista de presentes

Aplique as migrações antes de publicar uma versão nova do app: o app lê as tabelas novas ao abrir e falha se elas ainda não existem.

- `202611190001_layette_options.sql`: opções por item, preço principal e histórico. A conferência diária de preços é chamada pelo `pg_cron` com `pg_net`. No SQL Editor, guarde o segredo no Vault e agende:

  ```sql
  create extension if not exists pg_cron;
  create extension if not exists pg_net;
  select vault.create_secret('VALOR_DO_CRON_SECRET', 'cron_secret');
  select cron.schedule('conferir-precos', '0 9 * * *', $$
    select net.http_post(
      url := 'https://SUA_API/internal/refresh-prices',
      headers := jsonb_build_object('Authorization', 'Bearer ' ||
        (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret'))
    );
  $$);
  ```

  O horário é em UTC (9h UTC = 6h em Brasília). A API responde 202 e confere os links em segundo plano.
- `202611200001_gift_list.sql`: lista de presentes com Pix, liberada pelo Ninho Plus (R$ 10, pago uma vez por conta). Para dar o Plus a uma conta sem compra, como a sua, use o SQL Editor:

  ```sql
  insert into public.plus_accounts(user_id, source)
  select id, 'liberado à mão' from auth.users where email = 'EMAIL_DA_CONTA';
  ```

  A página pública fica em `/lista/<endereço>` e chama a API; `/lista/exemplo` mostra uma lista de exemplo, sem API.
- `202611210001_plus_purchase.sql`: compra do Plus pela Google Play. Guarda cada compra e libera ou retira o Plus da conta. Veja "Google Play Billing" abaixo.

## Render

Crie um serviço a partir deste repositório usando o blueprint `render.yaml`, ou um serviço Docker com:

- Dockerfile: `backend/Dockerfile`
- Contexto: `backend`
- Health check: `/healthz`
- `SUPABASE_URL`: URL do projeto dedicado.
- `SUPABASE_PUBLISHABLE_KEY`: chave publishable ou anon, nunca service role.
- `SUPABASE_SECRET_KEY`: chave secreta (ou service role) do projeto. A API a usa para excluir, pela API admin do Auth, o usuário da sessão verificada, para a conferência diária de preços e para as páginas públicas das listas de presentes. Sem ela, essas três respondem que estão indisponíveis; a exclusão de conta é exigida pela Google Play. Ela nunca vai para o app nem para a Vercel.
- `CRON_SECRET`: um valor aleatório longo (por exemplo, `openssl rand -hex 32`), o mesmo guardado no Vault acima. Sem ele, `/internal/refresh-prices` responde 404.
- `GOOGLE_PLAY_SERVICE_ACCOUNT` e `GOOGLE_PLAY_PACKAGE`: compra do Plus, descrita em "Google Play Billing" abaixo. Sem a conta de serviço, a compra responde que ainda não está disponível.
- `ALLOWED_ORIGINS`: URLs web exatas, separadas por vírgula, sem barra final. Inclua só o domínio de produção e as prévias que forem necessárias.

O blueprint usa o plano gratuito como ponto de partida. Confirme limites e custos na conta antes de criar o serviço. O processo lê `PORT`, aceita encerramento gracioso e roda como usuário sem privilégios no contêiner.

## Google Play Billing

O Plus é vendido só no app Android, pelo Google Play Billing. Ele vale para a conta, então quem compra no Android tem o Plus na web também; a web só indica a compra pelo app. Com o Plus, a família não vê o anúncio de abertura do app.

1. No Play Console, conclua o perfil de pagamentos (Configuração › Perfil de pagamentos). Sem ele, não é possível criar produtos.
2. Envie um build com o Billing (este) para uma faixa de teste, mesmo que interna. A Play só libera produtos depois disso.
3. Em Monetizar › Produtos › Produtos no app, crie o produto `ninho_plus`, com o preço em reais, e ative-o.
4. No Google Cloud, no projeto vinculado ao Play Console, ative a "Google Play Android Developer API". Crie uma conta de serviço sem papéis e baixe uma chave JSON.
5. No Play Console, em Usuários e permissões, convide o e-mail da conta de serviço com acesso ao app e as permissões "Ver dados financeiros" e "Gerenciar pedidos e assinaturas".
6. No Render, cole o conteúdo inteiro do JSON em `GOOGLE_PLAY_SERVICE_ACCOUNT` e `br.com.ninho.app` em `GOOGLE_PLAY_PACKAGE`. O JSON nunca vai para o app, para a Vercel nem para o repositório.
7. Em Configuração › Teste de licença, adicione as contas Google que vão testar: elas compram sem cobrança.

O app envia o token da compra para a API, que confere a compra na Google Play com a conta de serviço e só então registra e libera o Plus. O app conclui (reconhece) a compra só depois disso; se a API não registrar, a Google estorna em três dias. Cada compra leva um identificador derivado da conta do Ninho, e a API recusa uma compra feita por outra conta. Uma vez por dia, na mesma chamada da conferência de preços, a API lê as compras anuladas (reembolsos e contestações) e retira o Plus delas. As compras ficam em `public.plus_purchases`.

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

A raiz do site é a página de apresentação (`site/`), e o app fica em `/app/`. O link `/app/?demo` abre direto a demonstração. O script monta tudo em `dist/`, a pasta de saída da Vercel.

Depois de obter o domínio da Vercel, configure a origem na API e o redirecionamento no Supabase Auth. Use `https://SEU_DOMINIO/app/` como Site URL e nas URLs de redirecionamento. Se um link de e-mail antigo cair na raiz com `?code=` ou um token, a página de apresentação o repassa para `/app/`. Em `ALLOWED_ORIGINS` nada muda: a origem continua sendo o domínio, sem caminho. Verifique cadastro, confirmação, login, recuperação de senha e acesso de duas famílias distintas.

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
