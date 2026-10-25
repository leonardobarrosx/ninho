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

Montados aqui com esses vetores:

- `feature-graphic.svg` e `feature-graphic.png`: a imagem de destaque da Google Play (1024 × 500). Veja [Imagem de destaque](#imagem-de-destaque).

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

## Imagem de destaque

`feature-graphic.svg` é a fonte, e `feature-graphic.png` é o arquivo enviado à Play: 1024 × 500, PNG RGB de 24 bits, sem canal alfa, como a Play exige.

- **Fundo:** laranja de ponta a ponta. A Play pede cores vivas e desaconselha fundos quase brancos, que se confundem com a loja. Por isso o pêssego ficou de fora.
- **Logo:** a horizontal `reverse` (símbolo creme, nome branco) a 90%, centralizada.
- **Frase:** a da tela de entrada, "Mais clareza nas contas. Mais espaço para viver essa fase.", em Roboto Bold 44 px, a fonte do app. Ela é ameixa, como o texto sobre o laranja no app, com contraste de 5,2:1. Branco e creme sobre o laranja ficam em 2,3:1 e 2,2:1, e por isso só aparecem na logo.
- **Cantos de baixo:** só fundo. É o braço direito do símbolo, ampliado e espelhado, em `#FF9A71`, o creme a 15% sobre o laranja. Ele estende o ícone sem repeti-lo, como a Play recomenda.
- **Sem personagens nem rostos:** a ficha não pode parecer voltada a crianças, porque o app é para maiores de 18 anos.

A logo e a frase ficam a pelo menos 120 px das bordas, que a Play corta ou cobre em alguns formatos. A frase continua legível com a imagem reduzida a 360 px de largura.

A frase está em curvas, como o lettering, para o SVG não depender de fonte instalada. As curvas saíram da Roboto Bold do SDK do Flutter (`bin/cache/artifacts/material_fonts/roboto-bold.ttf`), com kerning, pela PyMuPDF: `Page.insert_htmlbox` e depois `get_svg_image(text_as_path=True)`. Para mudar ou traduzir a frase, gere as curvas de novo do mesmo jeito.

Para exportar o PNG, rode no PowerShell, na raiz do repositório. O `Out-Null` faz o PowerShell esperar o Edge terminar:

```powershell
& "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=1 --window-size=1024,500 --screenshot="$PWD\branding\feature-graphic.png" "file:///$PWD/branding/feature-graphic.svg" | Out-Null
```

O Edge grava direto um PNG RGB, sem canal alfa. O PNG desta pasta saiu desse comando.
