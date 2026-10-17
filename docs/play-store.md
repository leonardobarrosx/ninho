# Publicação na Google Play

O Ninho vai para a Play como app gratuito, com um anúncio do AdMob na abertura. Este roteiro reúne o que o código já atende, as respostas dos formulários do Play Console e o que só pode ser feito nas contas do Google, do AdMob e dos provedores. Ele complementa o `docs/deploy.md`.

## Situação

| Item | Situação |
| --- | --- |
| Build Android no padrão do Flutter 3.47.7 (Gradle 9.3.1, AGP 9.1.0, Kotlin 2.4.0, Java 17) | No código. Nunca foi compilado: esta máquina não tem Android SDK nem Java |
| `targetSdk` 36, exigido desde 31/08/2026 | No código |
| Assinatura de release por `key.properties` | No código; falta criar a chave |
| Anúncio de abertura (App Open Ad) com consentimento do Google (UMP) | No código, com IDs de teste; nunca rodou em aparelho |
| Exclusão de conta no app e por link web | No código e nos testes; o endpoint precisa de `SUPABASE_SECRET_KEY` no Render |
| Política de privacidade na web | `/privacidade`, publicada com o build da Vercel |
| Application ID definitivo | `br.com.ninho.app`, confirmado em 17/10/2026 |
| Contas Play, AdMob, Supabase, Render e Vercel | A criar ou configurar |

## 1. Antes de começar

- **Android Studio:** instale-o (ele traz o Android SDK e um JDK 17 ou mais novo) e rode `flutter doctor` até a linha do Android ficar verde. Só depois dá para gerar o AAB e testar em aparelho ou emulador.
- **Conta de desenvolvedor na Play:** contas pessoais criadas depois de 13/11/2023 só liberam a produção depois de um **teste fechado com pelo menos 12 testadores, inscritos por 14 dias seguidos**. Contas de organização não têm essa exigência. Reúna os testadores cedo, com folga para desistências.
- **Infraestrutura:** Supabase, Render e Vercel configurados conforme o `docs/deploy.md`, inclusive a migração `202610170001_account_deletion.sql`, `SUPABASE_SECRET_KEY` no Render e `PRIVACY_CONTROLLER`/`PRIVACY_EMAIL` na Vercel.

## 2. Identidade do app

- **Application ID:** `br.com.ninho.app`, em `app/android/app/build.gradle.kts`, o mesmo nome do redirecionamento `br.com.ninho.app://login-callback/` do `supabase/config.toml`. O namespace e o pacote da `MainActivity` seguem o mesmo nome. Ele identifica o app na Play e **não pode mudar depois do primeiro envio**.
- **Versão:** `version:` em `app/pubspec.yaml` (hoje `0.1.0+1`). O número depois do `+` é o `versionCode`, e cada envio precisa de um maior.
- **SDKs:** `minSdk` 24 (do Flutter e do `google_mobile_ads`), `compileSdk` 36 e `targetSdk` 36, fixado em `build.gradle.kts` para não mudar sem querer numa atualização do Flutter.
- **Permissões:** só `INTERNET` e `AD_ID`, esta última adicionada pelo SDK de anúncios.
- **Ícone:** `branding/play-icon-512.png` (512 × 512, PNG de 32 bits), com a logo Abraço sobre o laranja. Ele é quadrado e sem cantos arredondados, porque a Play aplica a máscara. No aparelho, o ícone é adaptativo: tem fundo laranja, o símbolo creme e uma camada monocromática para os ícones temáticos do Android 13+. O Android 7 recebe PNGs redondos.

## 3. Assinatura e build

1. Crie a chave de envio fora do repositório e guarde uma cópia segura:

   ```bash
   keytool -genkeypair -v -keystore ~/ninho-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

2. Crie `app/android/key.properties` (ignorado pelo Git). `storeFile` é relativo a `app/android/` ou absoluto:

   ```properties
   storeFile=C:/Users/SEU_USUARIO/ninho-upload.jks
   storePassword=...
   keyAlias=upload
   keyPassword=...
   ```

3. Ative o **Play App Signing** no primeiro envio. O Google guarda a chave que assina o app instalado; a sua chave serve só para enviar versões.
4. Preencha `app/config.local.json` (ignorado pelo Git) a partir de `app/config.example.json`: `API_URL`, `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `SITE_URL` (o endereço `https://` da Vercel, para os links da política e da exclusão de conta; o build de release falha sem ele), `ADMOB_APP_ID` e `ADMOB_APP_OPEN_ID`.
5. Gere o pacote:

   ```bash
   cd app
   flutter build appbundle --release --dart-define-from-file=config.local.json
   ```

   Saída: `app/build/app/outputs/bundle/release/app-release.aab`. O build de release falha sem `key.properties` completo e quando só um dos dois IDs do AdMob é informado. Sem nenhum deles, ele avisa que o app não terá anúncios.

## 4. AdMob

1. No AdMob, adicione um app Android (ainda não publicado) e crie um bloco de anúncios **Abertura de app**.
2. Copie o ID do app (`ca-app-pub-…~…`) para `ADMOB_APP_ID` e o do bloco (`ca-app-pub-…/…`) para `ADMOB_APP_OPEN_ID`, só no `config.local.json`. Os IDs reais nunca vão para o Git.
3. Em **Privacidade e mensagens**, publique a mensagem de consentimento do GDPR (Espaço Econômico Europeu, Reino Unido e Suíça). O Google exige essa mensagem para veicular anúncios nessas regiões. A mensagem para estados regulamentados dos EUA é opcional.
4. Defina `ADMOB_PUBLISHER_ID` (`pub-` e 16 dígitos) na Vercel. O build publica `/app-ads.txt`, que o AdMob procura no site do desenvolvedor informado na Play; use o domínio da Vercel como esse site.
5. Depois da publicação, vincule o app do AdMob à ficha da Play.

Como o app usa os IDs:

- **Debug e profile:** sempre o bloco de teste do Google (`ca-app-pub-3940256099942544/9257395921`), mesmo com o ID real no arquivo. Assim nenhum clique de desenvolvimento conta como tráfego inválido.
- **Release com os IDs:** anúncios reais. **Release sem eles:** nenhum anúncio, e o manifesto recebe o ID de app de exemplo do Google, sem o qual o SDK encerra o app na abertura.

Como o anúncio aparece (`app/lib/ads.dart`):

- só no Android e só no início a frio; a versão web não tem anúncios;
- no máximo uma vez a cada 4 horas, e a primeira só 4 horas depois da primeira abertura do app;
- a abertura espera no máximo 4 segundos, atrás de uma capa com a logo, pela consulta de consentimento e pelo anúncio. Se ele falhar ou atrasar, o app abre e o anúncio atrasado é descartado;
- nunca durante a recuperação de senha, nem com o app em segundo plano;
- o consentimento vem antes de qualquer anúncio. Quando a mensagem do Google aparece, nenhum anúncio é mostrado naquela abertura. Anúncios personalizados só depois de uma resposta na mensagem do Google; onde não há mensagem, como no Brasil, e sem uma resposta atualizada, só anúncios não personalizados são pedidos;
- a classificação máxima é PG, sem conteúdo adulto;
- o botão **Privacidade dos anúncios** (Família › Sua conta) aparece quando o Google exige que a escolha possa ser revista.

Para ver a mensagem de consentimento fora da Europa, cadastre o aparelho de teste em **Privacidade e mensagens** no AdMob.

## 5. Conteúdo do app no Play Console

### Política de privacidade

`https://SEU-SITE/privacidade`. A página vem de `app/web/privacidade.html` e cobre dados de saúde de crianças (LGPD, arts. 11 e 14), anúncios, compartilhamento, transferência internacional, retenção e direitos. O build da Vercel preenche o responsável e o e-mail com `PRIVACY_CONTROLLER` e `PRIVACY_EMAIL`. **Peça uma revisão jurídica do texto antes de publicar.** Ele descreve o que o código faz hoje, mas não substitui um advogado.

### Acesso ao app

O app exige login para os dados reais. Crie no Supabase de produção uma conta para a revisão do Google, com uma família de exemplo sem dados reais, e informe e-mail e senha em **Acesso ao app**. Explique que **Explorar demonstração**, na tela de entrada, mostra o app sem conta. A revisão também verifica a exclusão de conta: use uma conta descartável.

### Anúncios

**Sim**, o app contém anúncios.

### ID de publicidade

**Sim**, o app usa o ID de publicidade, para **publicidade ou marketing**. O SDK do AdMob declara a permissão `com.google.android.gms.permission.AD_ID`.

### Público-alvo e conteúdo

- Faixa etária: marque **somente 18 anos ou mais**. Sem faixas de menores, a política para Famílias não se aplica.
- "O app pode atrair crianças?": **Não**. Bebês são o assunto, não o público; o app trata de finanças e de organização familiar para adultos. Na ficha da loja, evite textos ou imagens voltados a crianças.

### Classificação de conteúdo

Responda ao questionário IARC na categoria de utilitários e produtividade, sem violência, sexo, linguagem imprópria, drogas ou jogos de azar. Em "usuários interagem ou compartilham conteúdo", responda **Sim**: pessoas convidadas para a mesma família veem os dados e o e-mail umas das outras.

### Segurança dos dados

Respostas gerais:

- Coleta ou compartilha dados de usuários? **Sim**.
- Todos os dados são criptografados em trânsito? **Sim** (HTTPS para a API e o Supabase; o SDK do AdMob usa TLS).
- Há como pedir a exclusão dos dados? **Sim**, no app (Família › Sua conta › Excluir minha conta) e em `https://SEU-SITE/excluir-conta`.
- Login: e-mail e senha.

Tipos de dados (operadores como Supabase, Render e Vercel, que tratam dados em nome do app, não contam como compartilhamento):

| Tipo no formulário | Coletado | Compartilhado | Obrigatório | Finalidades |
| --- | --- | --- | --- | --- |
| Informações pessoais › Endereço de e-mail | Sim | Não | Sim | Funcionalidade do app; gerenciamento da conta |
| Informações pessoais › Outras informações (nome ou apelido e datas do bebê, nome da família) | Sim | Não | Não | Funcionalidade do app |
| Informações financeiras › Outras informações financeiras (receitas, salários, despesas, dívidas, metas) | Sim | Não | Não | Funcionalidade do app |
| Saúde e condicionamento físico › Informações de saúde (consultas, exames, vacinas, medicamentos, peso, comprimento) | Sim | Não | Não | Funcionalidade do app |
| Atividade no app › Outros conteúdos gerados pelo usuário (observações) | Sim | Não | Não | Funcionalidade do app |
| Atividade no app › Interações com o app (SDK do AdMob) | Sim | Sim | Sim | Publicidade ou marketing; análises; prevenção de fraudes, segurança e conformidade |
| Local › Local aproximado (pelo IP, SDK do AdMob) | Sim | Sim | Sim | Publicidade ou marketing; análises; prevenção de fraudes, segurança e conformidade |
| Informações e desempenho do app › Diagnóstico (SDK do AdMob) | Sim | Sim | Sim | Análises; prevenção de fraudes, segurança e conformidade |
| IDs do dispositivo ou outros IDs (ID de publicidade, app set ID) | Sim | Sim | Sim | Publicidade ou marketing; análises; prevenção de fraudes, segurança e conformidade |

As linhas do AdMob seguem a divulgação oficial do Google para o SDK (developers.google.com/admob/android/privacy/play-data-disclosure). Confira essa página na hora de preencher, porque ela muda com as versões do SDK. Nenhum dado é processado só de forma efêmera.

### Apps de saúde

O formulário é obrigatório para todos os apps. Em **Medicina**, marque:

- **Gerenciamento de serviços de saúde**: agenda de consultas e exames;
- **Gerenciamento de medicamentos e tratamentos**: registro de medicamentos e vacinas;
- **Saúde reprodutiva e sexual**, se o acompanhamento do pré-natal e da data prevista do parto entrar no escopo. É uma decisão de produto; na dúvida, marque.

Não marque "suporte a decisões clínicas" nem "dispositivo médico": o app não diagnostica, não indica doses e não interpreta exames. Diga isso na descrição da loja, por exemplo: "O Ninho não é um dispositivo médico e não substitui o acompanhamento profissional."

### Recursos financeiros

Declare que o app não oferece serviços financeiros: não movimenta dinheiro, não concede crédito, não faz pagamentos nem investimentos. Ele é um controle de orçamento com lançamentos manuais. Se o formulário tiver uma opção de gestão de finanças pessoais ou orçamento, marque só ela.

### Outras declarações

App governamental, de notícias ou de COVID-19: **Não**.

## 6. Ficha da loja

- Nome: Ninho. Categoria sugerida: Criação dos filhos (Parenting).
- Descrição curta e completa em português, citando que o app tem anúncios e o aviso de que não é um dispositivo médico.
- Ícone de 512 × 512 (`branding/play-icon-512.png`), imagem de destaque de 1024 × 500 e de 2 a 8 capturas de tela de celular. A imagem de destaque ainda precisa ser feita; os vetores horizontais de `branding/` servem de base.
- E-mail de contato, site (o domínio da Vercel, por causa do `app-ads.txt`) e a URL da política de privacidade.

## 7. Lançamento

1. **Teste interno** com o AAB assinado: confira o anúncio de teste, a mensagem de consentimento, a exclusão de conta e o relatório de pré-lançamento da Play.
2. **Teste fechado** com pelo menos 12 testadores por 14 dias seguidos, quando a conta for pessoal e nova.
3. **Produção**, com os IDs reais do AdMob no build de release.
4. Vincule o app do AdMob à ficha publicada e acompanhe o status do `app-ads.txt`.

## 8. O que não foi verificado

- O AAB nunca foi gerado, e o app nunca rodou em aparelho ou emulador Android: esta máquina não tem Android SDK nem Java.
- O comportamento real do AdMob e do UMP (mensagem de consentimento, anúncio de teste, botão de privacidade) só foi exercitado com um substituto nos testes.
- O ícone adaptativo nunca foi compilado nem visto num launcher. Os recursos foram conferidos como XML e numa prévia equivalente em SVG, com máscaras redonda e arredondada e no modo temático.
- A criação do gatilho em `auth.users` no Supabase hospedado não foi testada; o teste local usa PGlite. Depois de aplicar a migração, confira em Database › Triggers.
- A exclusão pelo endpoint real do Auth admin, os deploys no Render e na Vercel e as respostas dos formulários da Play dependem das contas.
