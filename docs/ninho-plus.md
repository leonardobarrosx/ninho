# Ninho Plus

Plano da assinatura do Ninho. Nada disto está implementado; este documento registra as decisões propostas e a ordem de trabalho. O que existe hoje continua gratuito, com o anúncio de abertura. O Plus é uma assinatura **por família**: uma pessoa paga e todos os membros daquela família recebem os benefícios.

## Resumo

| Item | Proposta |
| --- | --- |
| Modelo | Gratuito com anúncio + Plus por família |
| Preço | R$ 9,90/mês ou R$ 69,90/ano, com 7 dias grátis no plano anual |
| Cobrança | Google Play Billing pelo RevenueCat, só no Android no começo |
| Quem recebe | A família escolhida na compra; quem pagou precisa ser membro dela |
| Fonte da verdade | Tabela `public.subscriptions` no banco, preenchida pelo servidor |
| Atualização | Webhook do RevenueCat e uma sincronização logo depois da compra |
| Onde roda o webhook | Edge Function do Supabase, que serve com ou sem a API Go |

## 1. O que é grátis e o que é Plus

**Grátis, para sempre:** tudo o que o app faz hoje. Finanças, dívidas, metas e enxoval, bebês e medidas, saúde, família com até 4 pessoas, até 5 famílias por pessoa, demonstração, temas e exclusão de conta. A exportação completa dos dados, quando existir, também fica grátis: acesso e portabilidade são direitos do titular (LGPD, art. 18) e não podem ser cobrados.

**Plus:**

| Recurso | Para quem paga | Onde a regra é garantida | Esforço |
| --- | --- | --- | --- |
| Sem anúncios | Todos os membros da família | App | Pequeno |
| Lembretes de vacinas, consultas, medicamentos e contas a vencer | Notificações no Android, configuradas por pessoa | App | Médio |
| Família maior: até 8 pessoas (avós, babá) | A família toda | Banco (`accept_invite`) | Pequeno |
| Relatórios em PDF: saúde do bebê para o pediatra, gastos do mês e do enxoval | Quem gera o relatório | App | Médio |
| Anexos: fotos e PDFs de exames, receitas e carteira de vacinação, com cota por família | A família toda | Banco e Storage | Grande |

Ordem de lançamento:

- **v1:** sem anúncios, lembretes e família maior. Só "sem anúncios" vale pouco, porque o app mostra no máximo um anúncio a cada 4 horas. Os lembretes são o motivo principal para assinar.
- **v2:** relatórios.
- **v3:** anexos, que trazem custo de armazenamento.

**Quando o Plus termina, nada é apagado nem bloqueado:**

- os anúncios voltam;
- os lembretes param, mas ficam salvos e desligados;
- os anexos continuam visíveis e podem ser baixados, só não dá para enviar novos;
- quem já está na família continua nela, mas não entram novos membros acima de 4.

## 2. Preço

- **Mensal:** R$ 9,90.
- **Anual:** R$ 69,90. Equivale a R$ 5,83 por mês, 41% menos que o mensal ("menos de R$ 6 por mês para a família toda"). O anual combina com o uso do app, da gravidez aos primeiros anos do bebê.
- **Teste grátis:** 7 dias, só no anual e só para quem nunca assinou. Testes mais longos convertem mais, mas atrasam a receita; dá para testar 14 dias depois.
- **Taxas:** o Google fica com 15% das assinaturas. O RevenueCat é grátis até US$ 2,5 mil por mês de receita e cobra 1% acima disso; confirme os termos no site antes de contratar.
- **Moeda:** preço em reais. Se o app for liberado em outros países, a Play converte.
- **Revisão:** reavalie depois de 3 meses, com a conversão da tela de assinatura, a conversão do teste grátis e os cancelamentos.

## 3. Como a cobrança funciona

```text
App Android ── RevenueCat SDK ──> Google Play (compra)
Google Play ── notificações em tempo real ──> RevenueCat
RevenueCat ── webhook ──> Edge Function revenuecat-webhook ──> public.subscriptions
App ── logo após comprar ou restaurar ──> Edge Function plus-sync ──> public.subscriptions
Todos os membros ── RPC household_plans ──> plano de cada família
```

**Identidade.** No RevenueCat, o ID do cliente é o ID do usuário no Supabase: `Purchases.logIn(userId)` depois do login e `Purchases.logOut()` ao sair.

- Antes da compra, o app grava o atributo `household_id` com a família ativa. O servidor confere que quem pagou é membro dela.
- A partir da primeira compra, o vínculo entre assinatura e família fica no banco. Mudar o atributo depois não move o Plus; mover será uma ação explícita, se for preciso.
- Usar o ID da família como cliente do RevenueCat foi descartado. A mesma conta Google pode estar em várias famílias, e o RevenueCat transfere compras entre clientes quando a pessoa troca de família.

### Banco (nova migração)

**`public.subscriptions`.** Colunas:

- `household_id`, ligado à família e apagado junto com ela;
- `purchaser_id`, que fica nulo se a conta de quem pagou for excluída;
- `store`, `product_id` e `original_transaction_id` (único);
- `period` (`monthly` ou `annual`) e `status` (`active`, `grace`, `cancelled`, `expired` ou `refunded`);
- `will_renew`, `expires_at` e `updated_at`.

Membros podem ler a assinatura da própria família, e o cliente não tem permissão de escrita.

**`private.billing_events`.** Guarda o ID de cada evento recebido para descartar repetições, além do tipo, do cliente e da hora. Não guarda o corpo inteiro.

**`private.household_plus_until(h uuid)`.** Devolve até quando a família tem Plus, considerando `expires_at` e o período de carência. A decisão sempre usa a data, então uma família volta ao gratuito mesmo se um webhook se perder.

**`public.household_plans()`.** RPC que devolve, para cada família de quem chama: se tem Plus, até quando, se renova, qual o plano e se foi a própria pessoa que pagou.

**`accept_invite`.** O limite passa a ser 8 com Plus e 4 sem.

**Coluna `households.plan`.** O app e a API não a leem; só o teste do banco a usa, para garantir que o cliente não consegue se dar o Plus. Ela sai, para não existirem duas fontes de verdade, e essa verificação passa para `public.subscriptions`.

**Testes (PGlite):**

- quem é membro lê a assinatura e quem não é não lê;
- o cliente não consegue gravar na tabela;
- o limite de membros é 4 sem Plus e 8 com;
- uma assinatura vencida ou reembolsada volta a família ao gratuito na hora.

### Webhook

Fica em `supabase/functions/revenuecat-webhook`, uma Edge Function em TypeScript. Ela precisa de `verify_jwt = false`, porque quem chama é o RevenueCat e não um usuário. Se a API Go continuar e você preferir, a mesma lógica cabe numa rota fora do `/v1/` em `backend/internal/api/server.go`, usando `SUPABASE_SECRET_KEY`.

1. Compara o cabeçalho `Authorization` com o segredo configurado no painel do RevenueCat, em tempo constante. Se não bater, responde 401.
2. Registra o ID do evento em `private.billing_events`. Se ele já foi visto, responde 200 e para.
3. Consulta `GET https://api.revenuecat.com/v1/subscribers/{app_user_id}` com a chave secreta do RevenueCat. É o que o RevenueCat recomenda depois de qualquer webhook: o estado vem completo e num formato só, mesmo que os eventos cheguem fora de ordem.
4. Para o direito `plus`, lê produto, vencimento, carência, cancelamento da renovação, problema de cobrança e reembolso.
5. Acha a família pelo `original_transaction_id`. Se for a primeira vez, usa o atributo `household_id` e confere que o cliente é membro. Se não for, não concede o Plus e registra o motivo.
6. Grava a linha em `public.subscriptions` e responde 200. Qualquer outro código é tratado como falha, e o RevenueCat tenta de novo até 5 vezes (depois de 5, 10, 20, 40 e 80 minutos).

`plus-sync` é a mesma rotina, chamada pelo app com o token do usuário, para os passos 3 a 6 do próprio usuário. Ela libera o Plus na hora, sem esperar o webhook, e também atende ao "Restaurar compras".

Eventos esperados: `INITIAL_PURCHASE`, `RENEWAL`, `CANCELLATION`, `UNCANCELLATION`, `BILLING_ISSUE`, `EXPIRATION`, `PRODUCT_CHANGE`, `TRANSFER` e `TEST`. Como o passo 3 busca o estado completo, não há lógica por evento; o tipo só vai para o registro.

`REVENUECAT_WEBHOOK_AUTH` e `REVENUECAT_SECRET_KEY` ficam nos segredos do Supabase (`supabase secrets set`), nunca no app, na Vercel ou no Git.

### App

- **SDK:** `purchases_flutter`, com a chave pública do Google fornecida pelo RevenueCat em `REVENUECAT_GOOGLE_KEY`, pelo `config.local.json`. Essa chave é pública e pode ir no app.
- **Tela "Ninho Plus"** (Família › Plano):
  - benefícios;
  - mensal e anual com os preços vindos da Play, já na moeda local;
  - o teste grátis;
  - o texto de renovação automática e de como cancelar;
  - "Assinar", "Restaurar compras", "Gerenciar assinatura" (abre a página de assinaturas da Play), Termos e Privacidade.
- **Onde oferecer:** em Família › Sua conta e quando a pessoa toca num recurso Plus. Nunca no meio de um lançamento de finanças ou de saúde, e nunca em tela cheia por cima do app.
- **Estado:** vem do banco pela `household_plans()`. Quem pagou vê "Plus até 12/03/2027 · renova automaticamente". Os outros membros veem "Sua família tem o Plus".
- **Anúncio:** `blocked()` em `app/lib/ads.dart` passa a considerar o Plus. O app guarda no aparelho até quando alguma família da pessoa tem Plus, porque a abertura não pode esperar a rede. Num aparelho novo, a primeira abertura ainda pode mostrar um anúncio antes de o app saber do Plus.
- **Web:** mostra o estado e os benefícios e orienta a assinar pelo app Android. Uma compra na web, com Stripe ou o Web Billing do RevenueCat, fica para depois. No app Android, assinaturas digitais precisam usar o Google Play Billing.
- **Sair da família ou excluir a conta:** a assinatura da Play continua cobrando até ser cancelada na Play.
  - Quem pagou e sai da família é avisado de que o Plus segue valendo para ela até o cancelamento.
  - A exclusão de conta avisa para cancelar antes e apaga o cliente no RevenueCat (`DELETE /v1/subscribers/{id}`).

## 4. Configuração nas contas (você)

1. **Perfil de pagamentos** no Play Console, com conta bancária e dados fiscais. Sem ele não dá para vender.
2. **Envie um AAB com a biblioteca de cobrança** para o teste interno. A Play costuma exigir isso antes de deixar criar assinaturas.
3. **Crie a assinatura `ninho_plus`:**
   - planos-base `mensal` (R$ 9,90) e `anual` (R$ 69,90);
   - a oferta de 7 dias grátis no anual, só para quem nunca assinou;
   - período de carência e suspensão da conta ativados, e pausa desativada.
4. **Conta de serviço** com acesso à API do Google Play Developer, cadastrada no RevenueCat, e as **notificações em tempo real** (tópico do Pub/Sub) apontando para o RevenueCat.
5. **No RevenueCat:**
   - o projeto e o app Android;
   - o direito `plus`;
   - os dois produtos e a oferta `default`, com os pacotes mensal e anual;
   - o webhook com a URL da Edge Function e o valor do cabeçalho `Authorization`.
6. **Testadores licenciados** no Play Console. A liberação pode demorar algumas horas.

## 5. Testes

Com testadores licenciados, a Play acelera os prazos: o mês renova em 5 minutos, o ano em 30, o teste grátis dura 3, a carência 5 e a suspensão 10. Uma assinatura de teste renova no máximo 6 vezes. Os cartões de teste aprovam ou recusam sempre, o que permite simular falha de cobrança.

Confira:

- quem pagou e outro membro da família veem o Plus, e os dois ficam sem anúncio;
- a família aceita até 8 pessoas;
- depois de cancelar, o Plus vale até o vencimento e então a família volta ao gratuito;
- um reembolso tira o Plus na hora;
- "Restaurar compras" funciona num aparelho novo;
- um webhook repetido não muda nada;
- os avisos de sair da família e de excluir a conta aparecem.

Testes automáticos:

- o teste do banco;
- testes do webhook com exemplos de resposta do RevenueCat;
- testes de interface da tela Plus: carregando, erro ao buscar os planos, compra pendente, assinada e restaurada, nos dois temas.

## 6. Documentos e formulários

- **Termos de uso** (o app ainda não tem): assinatura, renovação automática, cancelamento e reembolso, com link na tela do Plus.
- **Política de privacidade:** o RevenueCat entra como operador, tratando ID do usuário, histórico de compras e país, ao lado do Google Play.
- **Segurança dos dados no Play Console:** acrescentar "Informações financeiras › Histórico de compras", com a finalidade de funcionalidade do app e gerenciamento da conta.
- **Política de assinaturas da Play:** a tela precisa deixar claros o preço, o período, o teste grátis e a renovação.
- **Direito de arrependimento** (Código de Defesa do Consumidor, art. 49): confirme com o advogado como ele se aplica. Reembolsos são feitos pelo Play Console.

## 7. Ordem de trabalho

1. Aprovar este plano e configurar a Play e o RevenueCat (seção 4).
2. Banco: tabela, funções, limite de membros e testes.
3. Webhook e `plus-sync`, com testes.
4. App: SDK, tela Plus, estado do plano, anúncio desligado, restauração e avisos.
5. Recursos da v1: lembretes e família maior.
6. Teste fechado com testadores licenciados e publicação.
7. v2 (relatórios) e v3 (anexos).

Os passos 2 e 3 não dependem da decisão entre manter a API Go ou falar direto com o Supabase. O passo 4 depende só em parte: a tela e o SDK são os mesmos, e muda só a forma de chamar `household_plans()`.

## 8. Métricas

- Visitas à tela do Plus.
- Testes grátis iniciados.
- Conversão do teste grátis em assinatura.
- Proporção entre mensal e anual.
- Cancelamentos e seus motivos.
- Fração das famílias ativas com Plus.

O painel do RevenueCat mostra quase tudo isso.

## 9. Riscos e pontos em aberto

- A conversão no Brasil pode ficar abaixo de 1%. O gratuito precisa continuar bom para o app crescer.
- O RevenueCat adiciona uma dependência e custo acima de US$ 2,5 mil por mês. A alternativa é integrar o Google Play Billing direto, o que exige Pub/Sub, confirmação das compras em até 3 dias e a API do Google Play Developer no servidor.
- No Android, economia de bateria e restrições a alarmes exatos podem atrasar os lembretes. É preciso testar em aparelhos reais e explicar na tela de permissões.
- Os anexos geram custo de armazenamento. Defina uma cota por família, por exemplo 1 GB.
