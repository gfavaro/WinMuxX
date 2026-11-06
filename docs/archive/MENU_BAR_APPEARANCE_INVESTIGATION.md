# Aparência da menu bar — investigação de 2026-10-03

Objetivo: System deve acompanhar a aparência da menu bar; Custom é a escolha
explícita de aparência própria. O toggle local existente não demonstra equivalência
visual. Não foi alterado código de produção durante esta investigação.

## O que o toggle realmente faz

A documentação Apple descreve Show menu bar background como a escolha entre
wallpaper atrás da menu bar e fundo da menu bar. No macOS 27.2 desta máquina,
a comparação visual mostra uma faixa mais uniforme e com coloração diferente
quando ligado, preservando uma influência perceptível do wallpaper.

O binário ControlCenterSettings importa de SkyLight:

- `SLSGetMenuBarUseBlurredAppearance`
- `SLSSetMenuBarUseBlurredAppearance`
- `kSLSCoordinatedMenuBarBlurredBackgroundChangeNotificationName`

A desmontagem do setter confirma gravação da preferência global, chamada a
`__CGSSetMenuBarUseBlurredAppearance` pela conexão do compositor e, quando
solicitado, postagem de notificação coordenada. A chave observada é
`SLSMenuBarUseBlurredAppearance`; desligá-la remove a chave neste sistema.
O toggle não configura o material `.headerView` de uma NSVisualEffectView.

Esses símbolos são privados e dizem respeito à menu bar do sistema. Eles não
fornecem uma API pública para aplicar o mesmo renderizador numa janela arbitrária.
A existência da notificação foi confirmada, mas um observador simples de
DistributedNotificationCenter não recebeu eventos no ensaio. A entrega por evento
precisa ser investigada antes de afirmar que substitui polling de maneira confiável.

## Comparação com APIs públicas

Foram capturados estados off/on da faixa superior e sobrepostos painéis de prova
no mesmo trecho de wallpaper (x=500, largura=600, altura=38 pt). Os painéis eram
borderless, sem sombra, sem interação e foram removidos ao terminar. Foram
comparados cinco materiais de NSVisualEffectView em Aqua/Dark Aqua e os estilos
regular/clear de NSGlassEffectView, com cantos retos.

Médias RGB sRGB de uma região sem títulos e ícones, numa amostra de wallpaper azul:

| Renderizador | RGB médio |
| --- | --- |
| Menu bar, fundo desligado | 64, 75, 107 |
| Menu bar, fundo ligado | 75, 90, 137 |
| Header view, Dark Aqua | 49, 52, 62 |
| Menu material, Dark Aqua | 54, 62, 86 |
| HUD, Dark Aqua | 56, 68, 100 |
| Liquid Glass regular, Dark Aqua | 80, 93, 128 |
| Liquid Glass clear, Dark Aqua | 74, 84, 113 |
| Liquid Glass regular, Aqua | 167, 175, 200 |

Nesta amostra, regular/Dark Aqua foi o mais próximo entre os candidatos pela
diferença da média RGB. Isso não prova identidade visual nem mede raio de blur ou
opacidade. O ensaio não cobre wallpapers variados, todos os estados de contraste,
configurações de Liquid Glass, múltiplos displays ou diferenças entre versões.
Os materiais podem fazer composição não linear; não é válido deduzir um único
alpha ou raio universal destas médias.

## Implicações para WinMuxX

1. `.headerView` deve deixar de ser tratado como equivalente à menu bar.
2. Em System, usar a menu bar como referência única, com contraste definido pelo
   wallpaper inclusive quando o fundo estiver ligado. Hoje a amostragem nesse
   modo está limitada ao fundo desligado; isso pode produzir uma sidebar clara
   enquanto a menu bar mostra texto branco sobre fundo escuro.
3. NSGlassEffectView regular é o candidato público mais promissor no macOS 26+.
   Uma réplica exata ainda não foi demonstrada. Manter um fallback explícito nas
   versões anteriores e dar prioridade a Reduce Transparency.
4. Manter cores, tint e estilos próprios sob Custom, conforme a preferência do
   usuário. O toggle local não deve ser apresentado como sincronização com o OS.
5. Preservar a decisão de evitar polling. Se for necessário acompanhar o toggle
   global automaticamente, validar a notificação e o comportamento entre versões
   antes de integrar um mecanismo de observação.

## Evidências e restauração

As capturas estão em `.release/menu-bar-investigation/` (ignoradas pelo Git).
Scripts de ensaio, métricas, lista de símbolos e desmontagem estão em
`/tmp/winmuxx-menu-*`. Capturas se restringem à faixa superior sem conteúdo de apps.
O toggle do sistema foi restaurado para desligado, seu estado inicial. A versão
instalada continua sendo o build 20; não houve instalação nem alteração da config
WinMuxX nesta investigação.

Referências:

- [Apple: Menu Bar settings](https://support.apple.com/en-gb/guide/mac-help/mchlad96d366/26/mac/26)
- [Apple: NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview)
- [Apple: NSVisualEffectView.Material](https://developer.apple.com/documentation/appkit/nsvisualeffectview/material-swift.enum)
- Headers NSGlassEffectView.h e NSVisualEffectView.h do SDK macOS instalado no Xcode.

## Consolidação aplicada após a investigação

System passou a usar NSGlassEffectView regular no macOS 26+, sem tint explícito,
com aparência escolhida pela amostragem do wallpaper tanto recolhido quanto
expandido. A view de vidro tem cantos zero; a forma externa preserva a regra de
cantos retos no compacto e arredondados no expandido. Reduce Transparency continua
produzindo fundo opaco; versões anteriores usam o fallback AppKit já existente.

A tela mantém uma única escolha System/Custom e o toggle local Show background.
Os menus alternativos de fundo e frosted tint foram removidos. Custom continua
usando as cores e o estilo de Window surfaces, que também configuram tabs e switcher.
Não foi adicionada consulta periódica às preferências globais nem sincronização do
toggle macOS. O efeito segue a referência medida; não é apresentado como réplica exata.
