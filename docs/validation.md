# Estado da validação — 17/10/2026

## Executado

- App Flutter, com Flutter 3.47.7 (stable, Dart 3.13.5) no Windows:
  - `flutter pub get` resolve as dependências; o `app/pubspec.lock` está versionado.
  - `dart format --output=none --set-exit-if-changed lib test` não altera nenhum arquivo.
  - `flutter analyze` termina sem nenhum aviso.
  - `flutter test` passa os 34 testes:
    - 7 de domínio.
    - 4 de interface: a demonstração percorre as seis abas no celular nos temas claro e escuro, a visão geral no desktop, e o seletor troca o tema e o salva.
    - 16 do anúncio de abertura, com um substituto dos SDKs do Google: consentimento a cada abertura, instalação nova sem anúncio, limite de 4 horas, anúncio personalizado só com resposta atualizada na mensagem do Google, só não personalizado onde não há mensagem (como no Brasil), mensagem de consentimento no lugar do anúncio, falha e atraso do anúncio, consulta de consentimento sem resposta, recuperação de senha, opções de privacidade (inclusive quando o Google não responde) e erro do SDK. Três regras quebradas de propósito (ignorar a recuperação de senha, ignorar o prazo e personalizar sem consentimento atualizado) fizeram os testes correspondentes falharem.
    - 7 de conta e abertura: a capa segura o app até o fim do fluxo do anúncio; a demonstração não exclui conta; a exclusão só é confirmada com a senha, num campo oculto, e a senha chega ao `Store`, nos temas claro e escuro; cancelar mantém a conta; uma senha errada mostra o motivo.
  - `flutter build web --release` gera o build de demonstração com `privacidade.html`, `excluir-conta.html` e `pages.css`.
- `scripts/build_web.sh`, rodado numa cópia com um `flutter` falso, para não alterar a configuração global:
  - Falha sem `PRIVACY_EMAIL` fora do modo demo e com um `ADMOB_PUBLISHER_ID` malformado.
  - Preenche o responsável e o contato com escape de HTML (testado com `&`, `<`, `>`, aspas, `|` e `\`) e publica o `app-ads.txt`.
  - No modo demo, marca o responsável e o contato como "a definir".
- Inspeção visual da política de privacidade e da página de exclusão de conta no navegador, em 375 px nos temas claro e escuro, sem rolagem horizontal. No painel do navegador, a captura do canvas do Flutter não funcionou nesta sessão: o painel "Sua conta" foi conferido pelos testes de interface, sem estouro de layout nos dois temas.
- API Go: `go vet ./...` e `go test ./...` passaram no Windows com Go 1.26.3, sem `-race`, porque a máquina não tem cgo. O CI está configurado com Go 1.27.2 e `-race`. Os testes novos cobrem `DELETE /v1/account`:
  - A chamada admin leva a chave secreta e nunca o token do usuário.
  - As chamadas de dados nunca levam a chave secreta.
  - Respostas: 401 sem sessão ou com token forjado, 403 quando o último login com senha tem mais de 10 minutos ou o token não informa quando foi (o app faz um login novo com a senha logo antes), 405 com outro método, 503 sem a chave ou com falha do Auth, e 204 também quando o usuário já não existe.
  - A configuração recusa chaves trocadas.
- Banco: `npm run test:db` passou com PGlite 0.5.10 (PostgreSQL 18.6) numa cópia temporária. O teste aplica todas as migrações em ordem, simula os default privileges que o Supabase dá a `anon` e `authenticated`, usa papéis autenticados e contexto JWT simulado.
- O teste do banco cobre isolamento entre famílias, acesso negado entre tenants, campos e colunas protegidos, vínculos compostos, convites (uso único, limite de membros, limite de famílias, código colado por quem já é membro), datas de recorrência, snapshots de pagamentos, compras atômicas, despesa de saúde sem duplicação, exclusão de bebê ou de despesa vinculados a registros de saúde, privilégios residuais do Supabase e membros (listar com e-mail, só o dono remove, o dono não sai, quem foi removido perde o acesso e convites pendentes deixam de valer). Sem a migração `202610140002_review_fixes.sql`, o teste falha.
- Exclusão de conta no banco, apagando a linha de `auth.users` como faz a API admin do Auth:
  - Uma família em que a pessoa estava sozinha some com todos os registros.
  - Uma família compartilhada passa para quem entrou primeiro e perde o convite pendente.
  - Numa terceira família, a pessoa só deixa de participar.
  - O novo dono gera convites e remove pessoas. Quando ele exclui a própria conta sozinho na família, ela é apagada.
  - Sem a migração `202610170001_account_deletion.sql`, a exclusão falha em `households_owner_id_fkey`.
- Repositório: https://github.com/leonardobarrosx/ninho (privado).

## Pendente

- Build do AAB e teste em dispositivo Android. A máquina não tem Android SDK nem Java. Os arquivos Gradle seguem os templates do Flutter 3.47.7 (Gradle 9.3.1, AGP 9.1.0, Kotlin 2.4.0), mas nunca foram compilados aqui.
- O AdMob e o UMP reais (mensagem de consentimento, anúncio de teste, botão de privacidade dos anúncios) só rodaram com o substituto dos testes.
- CI: o GitHub Actions não inicia em repositórios privados desta conta. Todos os runs terminam em `startup_failure` sem nenhum job, inclusive os do Dependabot, enquanto os repositórios públicos rodam. Verifique a cobrança e o limite de gastos do Actions na conta do GitHub.
- Uso com backend real: o app só foi exercitado na demonstração, sem API nem Supabase.
- Aplicar as migrações em Supabase e verificar RLS, grants, o gatilho em `auth.users` e Auth no projeto real. Os testes locais não cobrem configurações do serviço hospedado.
- Provisionar Supabase, Render e Vercel, configurar URLs e verificar cadastro, e-mail, recuperação de senha, compartilhamento entre duas contas e exclusão de conta.
- Os itens da Google Play em `docs/play-store.md`.

## Ambiente original

O ambiente em que o projeto foi gerado interrompeu a execução do Flutter por detectar uma tentativa de acesso ao serviço de metadados da máquina; ela não foi repetida nem contornada. Os arquivos de plataforma Android vieram dos templates oficiais do Flutter 3.35.7, com ajustes de assinatura e permissão de internet, e depois foram atualizados para os do Flutter 3.47.7. O Flutter fornece os arquivos do Gradle wrapper ausentes durante o build.

O workflow executa banco, API, análise Flutter, testes de domínio/interface e builds de demonstração. Os avisos de estilo do analyzer são informativos; erros e warnings continuam bloqueando a etapa.

## Critério para disponibilizar a famílias reais

Concluir os itens pendentes, validar isolamento no ambiente publicado e implementar os controles operacionais descritos no README. A existência dos arquivos e dos testes escritos não comprova que o frontend ou a operação SaaS estão prontos para produção.
