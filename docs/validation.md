# Estado da validação — 14/10/2026

## Executado

- API Go: `go vet ./...` e `go test ./...` passaram no Windows com Go 1.26.3, sem `-race`, porque a máquina não tem cgo. O CI está configurado com Go 1.27.2 e `-race`.
- Banco: `npm run test:db` passou com PGlite 0.5.10 (PostgreSQL 18.6). O teste aplica todas as migrações em ordem, simula os default privileges que o Supabase dá a `anon` e `authenticated`, usa papéis autenticados e contexto JWT simulado.
- O teste do banco cobre isolamento entre famílias, acesso negado entre tenants, campos e colunas protegidos, vínculos compostos, convites (uso único, limite de membros, limite de famílias, código colado por quem já é membro), datas de recorrência, snapshots de pagamentos, compras atômicas, despesa de saúde sem duplicação, exclusão de bebê ou de despesa vinculados a registros de saúde, privilégios residuais do Supabase e membros (listar com e-mail, só o dono remove, o dono não sai, quem foi removido perde o acesso e convites pendentes deixam de valer). Sem a migração `202610140002_review_fixes.sql`, o teste falha.
- Revisão de 14/10/2026: o app não compilava, porque o `typedef Row` de `domain.dart` colidia com o widget `Row` do Flutter. A correção foi feita por leitura de código. As linhas alteradas foram mantidas dentro de 80 colunas para não mudar a saída do `dart format`, mas nenhuma ferramenta Flutter foi executada.
- Repositório: https://github.com/leonardobarrosx/ninho (privado).

## Pendente

- `dart format`, `flutter analyze`, `flutter test`, build web e APK. O Flutter não está instalado na máquina da revisão, e o GitHub Actions não inicia em repositórios privados desta conta: todos os runs terminam em `startup_failure` sem nenhum job, inclusive os do Dependabot, enquanto os repositórios públicos rodam. Verifique a cobrança e o limite de gastos do Actions na conta do GitHub.
- Resolver as dependências do aplicativo, gerar e versionar `app/pubspec.lock`.
- Inspeção visual em navegador e dispositivo Android.
- Aplicar as migrações em Supabase e verificar RLS, grants e Auth no projeto real. Os testes locais não cobrem configurações do serviço hospedado.
- Provisionar Supabase, Render e Vercel, configurar URLs e verificar cadastro, e-mail, recuperação de senha e compartilhamento entre duas contas.

## Ambiente original

O ambiente em que o projeto foi gerado interrompeu a execução do Flutter por detectar uma tentativa de acesso ao serviço de metadados da máquina; ela não foi repetida nem contornada. Os arquivos de plataforma Android foram preparados a partir dos templates oficiais do Flutter 3.35.7, com ajustes de assinatura e permissão de internet. O Flutter fornece os arquivos do Gradle wrapper ausentes durante o build.

O workflow executa banco, API, análise Flutter, testes de domínio/interface e builds de demonstração. Os avisos de estilo do analyzer são informativos; erros e warnings continuam bloqueando a etapa. Após a primeira resolução, o lockfile deve ser incorporado ao repositório.

## Critério para disponibilizar a famílias reais

Concluir os itens pendentes, validar isolamento no ambiente publicado e implementar os controles operacionais descritos no README. A existência dos arquivos e dos testes escritos não comprova que o frontend ou a operação SaaS estão prontos para produção.
