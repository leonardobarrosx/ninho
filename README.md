# Ninho

Planejamento financeiro e acompanhamento familiar em Flutter, com API Go no Render e Supabase Auth/Postgres. O mesmo aplicativo atende Android e web. A publicação web usa Vercel.

## O que está implementado

- Cadastro, confirmação de e-mail, login, recuperação e atualização de senha.
- Família compartilhada por convite de uso único, com validade de 72 horas. Até quatro membros por família.
- Receitas, salários, despesas únicas e contas mensais com início e encerramento.
- Baixa por ocorrência mensal, com valor pago preservado. Vencimentos em dias 29–31 são ajustados ao último dia do mês.
- Saldo previsto e realizado, despesas por categoria e pendências mensais.
- Cadastro de dívidas com credor, saldo devedor e parcela de referência.
- Metas e enxoval por prioridade: essencial, conforto ou opcional. Reservas, quantidades, presentes e compras efetivas.
- Compra de meta e registro financeiro na mesma transação do banco.
- Múltiplos bebês, data prevista/nascimento, peso em gramas e comprimento em milímetros. Gráficos descritivos por data.
- Consultas, exames, vacinas, medicamentos e outros registros. Custos vinculados às despesas sem duplicação.
- Layout responsivo, estados vazios, erros recuperáveis, formulários e demonstração fictícia separada dos dados reais.

## Limites atuais

Esta é a primeira versão para validação do produto. O frontend ainda precisa passar pela análise, pelos testes de interface e pelos builds; consulte `docs/validation.md`. Ainda não é uma operação comercial completa: cobrança de assinatura, webhooks de pagamento, emissão fiscal, atendimento, auditoria de alterações, revogação de membros pela interface, exportação/exclusão de conta, notificações push e anexos não estão implementados. Não há integração bancária ou sincronização offline. Escolha o provedor de pagamentos antes de implementar planos pagos; o campo de plano não é editável pelo cliente.

O saldo da dívida é informado manualmente. As parcelas devem ser cadastradas como despesas em Finanças. O app não infere amortização, juros ou evolução do saldo devedor. A baixa financeira não altera automaticamente o saldo cadastrado da dívida.

O saldo previsto é um resultado mensal (receitas menos despesas), não um saldo bancário. A reserva de uma meta é um valor separado manualmente, não uma transferência bancária. Registros médicos são informativos e não produzem diagnóstico, recomendação de dose ou interpretação de exames.

## Estrutura

```text
app/                  Aplicativo Flutter Android + web
backend/              API Go com biblioteca padrão
supabase/migrations/  Schema, políticas de acesso e operações atômicas
supabase/tests/       Testes de isolamento e regras do banco
scripts/              Build web para Vercel
.github/workflows/    Testes e artefatos web/APK de demonstração
render.yaml           Serviço da API
vercel.json           Publicação web
```

## Desenvolvimento

Requisitos: Flutter **3.35.7**, Go **1.27.2**, Java 17/Android SDK para APK e um projeto Supabase. A versão de Flutter fica fixada no build e na integração contínua. `pubspec.lock` deve acompanhar o código.

1. Aplique `supabase/migrations/202610140001_initial.sql` em um projeto Supabase **novo e dedicado**. O arquivo cria tabelas no schema público e deve ser aplicado uma vez. Com a CLI autenticada: `supabase link --project-ref SEU_REF` e `supabase db push`.
2. No Supabase Auth, configure a Site URL, URLs permitidas de redirecionamento e SMTP antes de distribuir convites/cadastros. Confirmação de e-mail fica habilitada. Para testes locais use `http://localhost:3000`; para a web use sua URL da Vercel. O fluxo de senha pode ser concluído na web, inclusive para contas usadas no Android.
3. Copie `backend/.env.example` para `backend/.env` e preencha URL, chave **publishable/anon** e origens exatas. Não use a chave `service_role` na API ou no app.
4. Inicie a API:

```bash
cd backend
set -a
source .env
set +a
go run ./cmd/api
```

5. Copie `app/config.example.json` para `app/config.local.json`. Esse arquivo está ignorado pelo Git. Para web local, configure `API_URL` como `http://localhost:8080`.

```bash
cd app
flutter pub get
flutter run -d chrome --web-port 3000 --dart-define-from-file=config.local.json
```

Sem definições, a tela inicial oferece somente uma demonstração com dados fictícios em memória. Ela não salva informações reais.

## Android

```bash
cd app
flutter build apk --debug --dart-define-from-file=config.local.json
```

Saída: `app/build/app/outputs/flutter-apk/app-debug.apk`. É um instalador de testes, assinado com chave de desenvolvimento. A integração contínua também gera um APK de demonstração sem endpoints reais.

Antes da distribuição comercial, configure seu application ID definitivo e uma chave de assinatura de produção. O projeto não inclui chave privada. Consulte `docs/deploy.md` para configurar `key.properties` e gerar release. Não envie keystores ou senhas ao Git.

## Segurança e dados

A API valida a sessão no Supabase Auth e encaminha o token do usuário ao Data API. Ela usa somente a chave pública. O banco aplica Row Level Security por família, inclusive se o Data API for chamado diretamente. Chaves elevadas não são necessárias. Os RPCs de compartilhamento e operações atômicas verificam o membro/owner explicitamente. Relacionamentos compostos impedem vincular bebê, medidas e gastos entre famílias.

Números monetários são armazenados em centavos inteiros. Registros de pagamento guardam o valor da baixa. Famílias, convites, membros e snapshots de pagamentos não aceitam inserção livre do cliente. Logs da API não registram tokens, nomes, valores ou informações médicas.

Antes de disponibilizar a terceiros: validar os testes no projeto implantado, revisar configurações de Auth/SMTP, definir política de privacidade e retenção, completar os controles de exportação/exclusão e de remoção de membros, configurar backup e observabilidade. O limite de requisições é em memória por instância; para múltiplas instâncias deve ser compartilhado.

## Validação

```bash
cd backend
go vet ./...
go test -race ./...
cd ../app
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web --release
```

Consulte `docs/validation.md` para o que foi efetivamente executado nesta entrega e eventuais pendências.
