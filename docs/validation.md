# Estado da validação — 14/10/2026

## Executado

- API Go: `go vet ./...` e `go test -race ./...` passaram nesta sessão de desenvolvimento, antes da retomada do trabalho. O backend não foi alterado após essa execução.
- Banco: `npm run test:db` passou usando PostgreSQL em PGlite 0.5.10, com a migração real, papéis autenticados e contexto JWT simulado.
- O teste do banco cobre isolamento entre famílias, acesso negado entre tenants, campos protegidos, vínculos compostos, convites de uso único, datas de recorrência, snapshots de pagamentos, compras atômicas e prevenção de despesas de saúde duplicadas.
- `dart format app/lib app/test` concluiu sem erro de sintaxe. Isso não substitui análise de tipos ou testes Flutter.

## Pendente

- Resolver as dependências do aplicativo, gerar e versionar `app/pubspec.lock`.
- `flutter analyze`, `flutter test`, build web e APK. Nenhum binário foi gerado ou validado nesta entrega.
- Inspeção visual em navegador e dispositivo Android.
- Aplicar migração em Supabase e verificar RLS e Auth no projeto real. Os testes locais não cobrem configurações do serviço hospedado.
- Criar/conectar repositório GitHub e executar o workflow; confirmar os artefatos e corrigir qualquer falha antes de publicar.
- Provisionar Supabase, Render e Vercel, configurar URLs e verificar cadastro, e-mail, recuperação de senha e compartilhamento entre duas contas.

## Bloqueio do ambiente de desenvolvimento

A revisão automática interrompeu a execução do Flutter por detectar uma tentativa de acesso ao serviço de metadados da máquina. A execução não foi repetida nem contornada. Os arquivos de plataforma Android foram preparados a partir dos templates oficiais do Flutter 3.35.7, com ajustes de assinatura e permissão de internet. O Flutter fornece os arquivos do Gradle wrapper ausentes durante o build.

O workflow preparado executa banco, API, análise Flutter, testes de domínio/interface e builds de demonstração. Os avisos de estilo do analyzer são informativos; erros e warnings continuam bloqueando a etapa. Após a primeira resolução, o lockfile deve ser incorporado ao repositório.

## Critério para disponibilizar a famílias reais

Concluir os itens pendentes, validar isolamento no ambiente publicado e implementar os controles operacionais descritos no README. A existência dos arquivos e dos testes escritos não comprova que o frontend ou a operação SaaS estão prontos para produção.
