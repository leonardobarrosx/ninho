# Identidade do Ninho

A logo é a **proposta A, Abraço**, escolhida em 17/10/2026 entre as propostas A, B e C: um ninho que abraça o ovo. Ela substitui o ovo sorridente da primeira identidade.

## Arquivos desta pasta

Vetores do designer, sem fonte externa (o lettering está em curvas):

- `ninho-A-simbolo-*.svg`: só o símbolo.
- `ninho-A-horizontal-*.svg` e `ninho-A-vertical-*.svg`: símbolo com o nome "ninho".
- `ninho-A-lettering.svg`: só o nome.
- `app-icon.svg`: o ícone quadrado, com o símbolo creme sobre o laranja.
- `app-icon-maskable.svg`: o mesmo ícone com margem maior, para máscaras redondas.
- `play-icon-512.png`: o ícone da Google Play (512 × 512, PNG de 32 bits). Ele é quadrado e sem cantos arredondados, porque a Play aplica a máscara.

Versões de cor: `color` usa as cores da marca, `plum` é a versão de uma cor em ameixa, `white` é branca e `reverse` é a versão clara para fundos escuros.

| Cor | Hex | No app |
| --- | --- | --- |
| Laranja | `#FF8A5C` | `Palette.light.brand` |
| Creme | `#FFF6EA` | o ovo e o ninho |
| Ameixa | `#3A3248` | `Palette.light.ink` |

## Onde a logo aparece

- **App:**
  - `NinhoLogo` em `app/lib/theme.dart`, desenhada em código com os caminhos de `ninho-A-simbolo-color.svg`, num disco laranja.
  - `LaunchCover`, em `app/lib/widgets.dart`, continua a abertura do Android enquanto o anúncio decide: tem o mesmo fundo e a logo de 144 dp no meio, que respira devagar.
- **Web:**
  - a abertura em `app/web/index.html`: o símbolo no disco laranja e o nome "ninho" de `ninho-A-lettering.svg`, na cor do texto do tema, até o Flutter desenhar a primeira tela;
  - `app/web/favicon.svg`, uma versão para abas: o símbolo um pouco maior e com mais espaço ao redor do ovo, para continuar legível em 16 px;
  - `app/web/favicon.ico`;
  - os ícones de instalação em `app/web/icons/`.
- **Android:**
  - um ícone adaptativo com fundo laranja, o símbolo creme e uma camada monocromática para os ícones temáticos do Android 13+ (`res/drawable/ic_launcher_foreground.xml` e `res/mipmap-anydpi-v26/ic_launcher.xml`). Há também PNGs redondos em `res/mipmap-*` para o Android 7;
  - a abertura: `res/drawable/splash_icon.xml` (288 dp, com o disco de 144 dp dentro do círculo de 192 dp que o Android 12 mostra) sobre a cor de fundo. Ela entra em `res/drawable/launch_background.xml`, nas versões anteriores ao Android 12, e em `res/values-v31/styles.xml` e `res/values-night-v31/styles.xml`, do Android 12 em diante.
- **Google Play:** `play-icon-512.png`.

## Regras de uso

- O símbolo creme só aparece sobre o laranja. Em fundo branco ou pêssego (`#FFF2EA`), o ovo creme some: use a versão `plum`.
- Abaixo de 32 px, as linhas do abraço somem. Para tamanhos pequenos, use a versão de `favicon.svg`.
- Não aplique sombra nem cantos arredondados no ícone da Play.

Segundo o designer, os vetores são reconstruções geométricas da prancha original, e o lettering pode diferir do desenho original. Confirme com quem desenhou antes de imprimir ou ampliar muito.
