# Estado da validação — 17/10/2026

## Executado

- App Flutter, com Flutter 3.47.7 (stable, Dart 3.13.5) no Windows:
  - `flutter pub get` resolve as dependências; o `app/pubspec.lock` está versionado.
  - `dart format --output=none --set-exit-if-changed lib test` não altera nenhum arquivo.
  - `flutter analyze` termina sem nenhum aviso.
  - `flutter test` passa os 11 testes: 7 de domínio e 4 de interface. A demonstração percorre as seis abas no celular nos temas claro e escuro, a visão geral no desktop, e o seletor troca o tema e o salva.
  - `flutter build web --release` gera o build de demonstração.
- Inspeção visual do build web de demonstração no navegador, em 800 e 1280 px de largura: as seis abas, a barra lateral do desktop, o registro de medidas com gráficos e o painel de membros. Depois da identidade visual nova, a tela de entrada, a visão geral, o Enxoval e a Família foram conferidos em 328 px nos temas claro e escuro.
- API Go: `go vet ./...` e `go test ./...` passaram no Windows com Go 1.26.3, sem `-race`, porque a máquina não tem cgo. O CI está configurado com Go 1.27.2 e `-race`.
- Banco: `npm run test:db` passou com PGlite 0.5.10 (PostgreSQL 18.6). O teste aplica todas as migrações em ordem, simula os default privileges que o Supabase dá a `anon` e `authenticated`, usa papéis autenticados e contexto JWT simulado.
- O teste do banco cobre isolamento entre famílias, acesso negado entre tenants, campos e colunas protegidos, vínculos compostos, convites (uso único, limite de membros, limite de famílias, código colado por quem já é membro), datas de recorrência, snapshots de pagamentos, compras atômicas, despesa de saúde sem duplicação, exclusão de bebê ou de despesa vinculados a registros de saúde, privilégios residuais do Supabase e membros (listar com e-mail, só o dono remove, o dono não sai, quem foi removido perde o acesso e convites pendentes deixam de valer). Sem a migração `202610140002_review_fixes.sql`, o teste falha.
- Repositório: https://github.com/leonardobarrosx/ninho (privado).

## Pendente

- Build do APK e teste em dispositivo Android. A máquina não tem Android SDK nem Java. Os arquivos Gradle vieram dos templates do Flutter 3.35.7 (AGP 8.9.1, Kotlin 2.1.0, Gradle 8.12); o Flutter 3.47.7 pode pedir versões mais novas no primeiro build.
- CI: o GitHub Actions não inicia em repositórios privados desta conta. Todos os runs terminam em `startup_failure` sem nenhum job, inclusive os do Dependabot, enquanto os repositórios públicos rodam. Verifique a cobrança e o limite de gastos do Actions na conta do GitHub.
- Uso com backend real: o app só foi exercitado na demonstração, sem API nem Supabase.
- Aplicar as migrações em Supabase e verificar RLS, grants e Auth no projeto real. Os testes locais não cobrem configurações do serviço hospedado.
- Provisionar Supabase, Render e Vercel, configurar URLs e verificar cadastro, e-mail, recuperação de senha e compartilhamento entre duas contas.

## Ambiente original

O ambiente em que o projeto foi gerado interrompeu a execução do Flutter por detectar uma tentativa de acesso ao serviço de metadados da máquina; ela não foi repetida nem contornada. Os arquivos de plataforma Android foram preparados a partir dos templates oficiais do Flutter 3.35.7, com ajustes de assinatura e permissão de internet. O Flutter fornece os arquivos do Gradle wrapper ausentes durante o build.

O workflow executa banco, API, análise Flutter, testes de domínio/interface e builds de demonstração. Os avisos de estilo do analyzer são informativos; erros e warnings continuam bloqueando a etapa.

## Critério para disponibilizar a famílias reais

Concluir os itens pendentes, validar isolamento no ambiente publicado e implementar os controles operacionais descritos no README. A existência dos arquivos e dos testes escritos não comprova que o frontend ou a operação SaaS estão prontos para produção.
