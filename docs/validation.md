# Estado da validação — 19/10/2026

## Executado

- App Flutter, com Flutter 3.47.7 (stable, Dart 3.13.5) no Windows:
  - `flutter pub get` resolve as dependências; o `app/pubspec.lock` está versionado.
  - `dart format --output=none --set-exit-if-changed lib test` não altera nenhum arquivo.
  - `flutter analyze` termina sem nenhum aviso.
  - `flutter test` passa os 62 testes:
    - 7 de domínio.
    - 18 de interface:
      - A demonstração percorre as abas no celular nos temas claro e escuro, abre Família pelo menu da conta e volta.
      - Em 360 px, a barra de baixo tem cinco abas, sem estouro de layout.
      - Cada aba guarda a própria rolagem.
      - O botão voltar leva de Família à aba anterior e de qualquer aba à visão geral.
      - O menu da conta troca o tema e o salva, e o seletor da tela de entrada também.
      - Pagar uma conta mostra "Pago" e oferece desfazer no aviso.
      - Saúde separa os compromissos pendentes dos realizados.
      - Leitor de tela: o cartão de resumo e a linha de lançamento são lidos como um item, os títulos são cabeçalhos, o selo DEMO é texto e os botões dizem o nome do lançamento.
      - No desktop, a barra lateral mantém Família.
      - Os valores em reais dos cartões de resumo, das barras por categoria e dos lançamentos usam algarismos de largura fixa.
      - Bebê mostra uma vez só a dica "Registre ao menos duas medidas"; com duas medidas de peso, aparece a linha do peso e a dica fica só no comprimento.
      - Os ícones sobre os fundos coloridos (verde-menta, azul, lilás e amarelo) têm contraste de pelo menos 3:1 nos dois temas, também sobre o círculo do cartão de resumo, e os cartões de resumo e as linhas usam essas cores.
      - Os filtros de Finanças são opções de um grupo para o leitor de tela e continuam filtrando.
      - A página de licenças de código aberto abre em Família › Sobre esta versão e lista a Nunito.
      - As abas trocam com um fade: no meio da transição, as duas páginas estão na tela.
      - Com as animações desligadas no sistema, a página troca de uma vez.
    - 7 de formulário: datas em dd/mm/aaaa salvas em ISO, data opcional que pode ser apagada, data obrigatória, voltar com alterações pede confirmação, voltar sem alterações e Cancelar fecham na hora, um toque fora de um formulário curto não o fecha, e a tecla de ação do teclado passa para o próximo campo.
    - 2 de entrada: as mensagens de erro do Supabase Auth saem em português, e o formulário de login tem preenchimento automático, botão de mostrar a senha e erro em vermelho anunciado pelo leitor de tela.
    - Três correções quebradas de propósito (sem a rolagem por aba, sem o nome do lançamento no botão Pagar e com o toque fora fechando o formulário) fizeram os testes correspondentes falharem.
    - 16 do anúncio de abertura, com um substituto dos SDKs do Google: consentimento a cada abertura, instalação nova sem anúncio, limite de 4 horas, anúncio personalizado só com resposta atualizada na mensagem do Google, só não personalizado onde não há mensagem (como no Brasil), mensagem de consentimento no lugar do anúncio, falha e atraso do anúncio, consulta de consentimento sem resposta, recuperação de senha, opções de privacidade (inclusive quando o Google não responde) e erro do SDK. Três regras quebradas de propósito (ignorar a recuperação de senha, ignorar o prazo e personalizar sem consentimento atualizado) fizeram os testes correspondentes falharem.
    - 7 de conta e abertura: a capa cobre a tela inteira, segura o app até o fim do fluxo do anúncio e some com um fade; a demonstração não exclui conta; a exclusão só é confirmada com a senha, num campo oculto, e a senha chega ao `Store`, nos temas claro e escuro; cancelar mantém a conta; uma senha errada mostra o motivo.
    - 5 de tipografia, com a Nunito embutida carregada no teste (sem ela, o teste desenha cada letra como um quadrado):
      - Valores em reais com algarismos diferentes ocupam a mesma largura.
      - Em 360, 375, 390 e 412 px, nenhum título deixa uma palavra sozinha na última linha: entrada, as cinco abas da demonstração, Família, o início sem família e as abas sem registros.
    - Seis correções quebradas de propósito fizeram os testes correspondentes falharem: o título de Saúde sem o espaço que não quebra, os botões de texto sem a família da fonte, os valores dos lançamentos sem algarismos de largura fixa, a dica de crescimento repetida nos dois cartões, o ícone das receitas com o verde antigo e um `mintIcon` tão claro quanto o `mint`.
    - Mais duas correções quebradas de propósito (o ícone azul com o tom antigo e o chip de filtro fora do grupo de opções) fizeram os testes correspondentes falharem.
  - `flutter build web --release --no-web-resources-cdn`, como em `scripts/build_web.sh`, gera o build de demonstração com `privacidade.html`, `excluir-conta.html` e `pages.css`.
  - O build de demonstração foi conferido com o Playwright no Edge, em 390, 360 e 1280 px, nos temas claro e escuro: menu da conta, Família com voltar, contas pagas e desfazer em Finanças, formulário em tela cheia, Saúde e o gráfico por categoria. A árvore de acessibilidade do Flutter foi conferida em Finanças.
  - Itens 10 a 12 da auditoria de interface, conferidos no build de demonstração com o Playwright no Edge, em 390 e 360 px nos temas claro e escuro, e em 1280 px no claro:
    - A Nunito aparece nos textos, botões, chips, avisos e nos números do eixo do gráfico de crescimento. Os estilos de botão, chip e aviso do tema agora citam a fonte, porque substituem o estilo herdado; sem isso, ficariam na fonte padrão do sistema.
    - Os títulos quebram sem palavra sozinha na última linha, "Dívidas em aberto" cabe ao lado de "Nova dívida", os valores da demonstração não são redondos e Bebê mostra uma dica só.
    - No tema claro, os ícones verdes sobre o verde-menta ficaram mais escuros (#247f59, contraste de 4,1:1); a cor dos textos não mudou.
    - O build carrega as cinco Nunito do próprio site.
  - Recursos externos da web, conferidos com o Playwright no Edge:
    - Com `--no-web-resources-cdn`, o CanvasKit e a Roboto de reserva do Flutter saem do próprio site, e abrir a demonstração não faz nenhuma requisição a outro domínio. Antes, eles vinham de www.gstatic.com e fonts.gstatic.com.
    - Ao digitar um emoji, o navegador baixa a Noto Color Emoji de fonts.gstatic.com e o emoji aparece. A política de privacidade passou a dizer isso.
  - Abertura e animações, conferidas no build com o Playwright no Edge:
    - A abertura da web mostra a logo e o nome nos temas claro e escuro. Ela segue o tema salvo no app, mesmo contra o tema do sistema, e some com um fade quando o Flutter desenha a primeira tela.
    - As abas trocam com fade, as barras crescem, o "Pago" aparece no lugar do botão e o formulário longo sobe da parte de baixo.
    - As capturas e o GIF do README saíram desse build.
  - Abertura do Android (`res/drawable/splash_icon.xml`, `launch_background.xml` e os estilos em `values-v31` e `values-night-v31`): os XMLs estão bem formados, mas não passaram pelo aapt2 nem rodaram num aparelho, porque não há Android SDK.
  - No build, a página de licenças abre em português com o nome, o ícone e a versão do Ninho. Na web, os filtros de Finanças aparecem como opções de rádio na árvore de acessibilidade.
  - Os ícones azul, lilás e amarelo sobre os fundos claros ficaram mais escuros no tema claro (#2469de, #595fd8 e #996c0a, contraste de cerca de 4:1); no tema escuro já passavam de 6:1.
  - Nunito 3.602, do download oficial do Google Fonts (v32): os cinco arquivos estáticos (pesos 400 a 800) são TrueType válidos, com a licença SIL OFL 1.1 nos metadados e em `app/assets/fonts/OFL.txt`.
- Logo Abraço (proposta A), aplicada no app, na web e no Android:
  - Os testes de interface desenham a `NinhoLogo` nova.
  - Uma renderização do Flutter em 128, 96, 64, 38 e 30 px foi conferida nos fundos claro e escuro.
  - Prévias no Edge conferidas: o favicon de 16 a 64 px, e o ícone adaptativo com máscara redonda e arredondada, no modo temático claro e escuro e como PNG redondo do Android 7.
  - O ícone da Play tem 512 × 512 e é opaco.
  - O build web inclui `favicon.svg`, `favicon.ico` e os ícones de instalação.
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

- Build do AAB e teste em dispositivo Android. A máquina não tem Android SDK nem Java. Os arquivos Gradle seguem os templates do Flutter 3.47.7 (Gradle 9.3.1, AGP 9.1.0, Kotlin 2.4.0), mas nunca foram compilados aqui. Os recursos do ícone adaptativo também nunca passaram pelo aapt2 nem apareceram num launcher.
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
