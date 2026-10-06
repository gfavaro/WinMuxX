# Revisão de Sidebar & Appearance — 2026-10-03

Revisão de cada controle, seu consumidor no código, persistência e dependências.

**Estado atual:** há um único menu Sidebar appearance com Liquid Glass e Solid
color. A antiga escolha System/Custom foi removida; `chrome-style` controla o
renderizador da sidebar, tabs e switcher. Liquid Glass usa o vidro nativo inspirado
na menu bar e Show background; Solid exibe a paleta de cores. `appearance` legado
é aceito, mas não sobrepõe o estilo. Os registros abaixo descrevem a evolução.
Esta alteração é posterior ao build 21 instalado.

O build 19 está instalado em `/Applications/WinMuxX.app`, assinado com
`WinMuxX Local Code Signing`, com app e CLI no commit `c0bc117e`. A validação
interativa e as limitações da sessão estão registradas abaixo.

## Problemas corrigidos

1. `Focus sidebar monitor only` descrevia uma função inexistente. `enable-focus`
   apenas inclui o filtro **Focused** no seletor de monitores; agora o rótulo e
   a ajuda dizem isso explicitamente.
2. Auto-hide e Always expanded podiam ficar ligados simultaneamente. Agora há
   uma escolha exclusiva **Sidebar display**: Compact rail, Auto-hide ou Always
   expanded. Os dois valores TOML são validados e salvos em uma única operação.
3. `Tab group padding` não é usado no caminho dos tabs com barra visível. O campo
   foi retirado desta aba; o parâmetro legado continua disponível no TOML.
4. A altura dos tabs oferecia 21–35 pt, mas o renderer exige pelo menos 36 pt.
   O controle agora começa em 36 pt e representa o tamanho efetivo das configs antigas.
5. As paletas apareciam mesmo quando não tinham efeito. Cor sólida aparece em
   Solid color; fundo da sidebar aparece em System; frosted tint aparece somente
   com Transparent. O alcance global do estilo permanece explicitado.
6. Editar um gap podia substituir sua lista de overrides por um número único.
   Agora só altera o padrão, preserva regras por monitor e informa esse alcance.
7. O `@State` da aba não era reconstruído pela identidade aplicada dentro de seu
   próprio body. A identidade agora envolve a view da aba, e reload de config
   atualiza o modelo de Settings. Isso mantém os valores exibidos sincronizados.
8. Paletas não identificavam a configuração responsável por um erro de gravação.
   Agora participam do feedback específico do campo.
9. Os limites de largura respeitam a relação entre compacto e expandido.
   A largura compacta fica indisponível no modo Always expanded.
10. `Menu bar reserve` virou **Top clearance**, com unidade pt. Exclusions de
    bordas foi colocado em um grupo expansível por ser uma configuração avançada.

## Seleção de cores

As duas paletas compartilham amostras circulares com anel de seleção, como o
System Settings. O nome da seleção aparece abaixo, e cada amostra tem tooltip e
identificação para acessibilidade. As cores sólidas ocupam múltiplas linhas para
preservar todos os presets; Custom aparece primeiro como círculo multicolorido.
Os valores TOML são preservados.
A opção Custom continua abrindo o ColorPicker nativo, também usado pelas bordas;
superfícies opacas não oferecem alpha, enquanto bordas mantêm essa possibilidade.
Os controles ficam próximos do elemento afetado para preservar o contexto.

## Item a item

| Item original | Controle e efeito real | Resultado da revisão |
| --- | --- | --- |
| Style | Menu de escolha única; material de tabs, switcher, overlays e sidebar Custom. | Renomeado Surface style, em Window surfaces. Não equivale ao fundo System da sidebar. |
| Solid color | Amostras circulares com anel e nome da seleção. | Mostrar somente em Solid color; mantém escolha anterior ao voltar a Liquid Glass. |
| Custom color | ColorPicker nativo, sem transparência para superfícies opacas. | Manter; aparece quando o preset Custom é selecionado. |
| Show sidebar | Toggle mestre; cria/oculta os painéis nos displays configurados. | Manter; dependentes ficam indisponíveis quando desligado. |
| Sidebar appearance | System usa cores/material macOS; Custom usa o estilo das superfícies. | Manter, com alcance explícito. |
| Sidebar background | Sidebar material, estilo que acompanha o fundo da menu bar ou Transparent. | Mostrar somente em System. `.sidebar` e `.headerView` são materiais diferentes, embora possam parecer próximos. |
| Expanded frosted tint | Amostras circulares, somente para a sidebar transparente expandida. | Mostrar somente em System + Transparent. Não é a mesma paleta de cor sólida. |
| Focus sidebar monitor only | Na realidade adiciona um filtro de workspaces por display focado. | Corrigido para Show focused-display filter. Não move nem oculta painéis. |
| Reveal sidebar at the display edge | Auto-hide zera a largura em repouso, mantendo ativação pela borda. | Integrado ao menu Sidebar display. |
| Keep sidebar expanded | Expansão persistente; reserva largura na área das janelas. | Integrado ao mesmo menu. A prioridade antiga é preservada ao ler configs com ambos os flags true. |
| Expanded width | Campo numérico + stepper; largura completa do painel. | Manter; limite inferior maior que a largura compacta. |
| Collapsed width | Menu Collapsed sidebar size: Small (36 pt), Medium (44 pt), Large (56 pt). Valores legados fora dos presets aparecem como Custom. | Indisponível em Always expanded. Auto-hide usa essa medida ao revelar o rail. O tamanho altera a largura do painel, a fonte, a área do seletor e o botão + no modo recolhido. |
| Menu bar reserve | Altura retirada do topo do painel da sidebar. | Renomeado Top clearance; não é o outer top gap das janelas. |
| Show status pills | Liga indicadores de status dentro da sidebar. | Manter, independente do relógio. |
| Show clock | Liga o cartão que contém relógio e calendário. | Manter como mestre dos próximos três itens. |
| Show seconds | Mostra segundos na hora. | Manter; só atua com Show clock. |
| Show date | Mostra dia e mês no cartão. | Manter; não é duplicado de Show weekday. |
| Show weekday | Mostra o dia da semana. | Manter independente de Show date, dependente de Show clock. |
| Show tab strips | Liga a interface de tabs dos grupos de janelas. | Manter; renderer usa a janela ativa e esconde as demais. |
| Tab strip height | Campo numérico + stepper; altura real tem mínimo 36 pt. | Faixa corrigida para 36–80 pt. |
| Tab group padding | Recuo do layout legado sem a interface de tabs visíveis. | Retirado da aba: sua habilitação anterior correspondia ao caminho onde não atua. |
| Inner horizontal | Espaço entre janelas lado a lado. | Manter; editar padrão sem apagar overrides por display. |
| Inner vertical | Espaço entre janelas empilhadas verticalmente. | Manter; mesma preservação. |
| Outer left | Espaço entre sidebar e janelas, ou entre borda da tela e janelas sem sidebar. | Ajuda corrigida para distinguir da largura do painel. |
| Outer right | Recuo das janelas na direita do display. | Manter; não muda o desenho da sidebar. |
| Outer top | Recuo das janelas no topo do display. | Manter; distinto do Top clearance da sidebar. |
| Outer bottom | Recuo das janelas no rodapé do display. | Manter; não altera os cantos ou o rodapé do painel. |
| Show window borders | Liga a decoração de bordas das janelas gerenciadas. | Manter; não é uma borda da sidebar e é suprimido durante Mission Control. |
| Border width | Campo numérico + stepper fracionário; espessura em pt. | Manter. Zero também oculta as bordas; ajuda já explica isso. |
| Focused window color | ColorPicker com opacidade e entrada hexadecimal. | Manter; controles nativos com validação. |
| Other window color | Mesmo controle para janelas não focadas. | Manter; contexto diferente, sem duplicação. |
| Border placement | Menu exclusivo para nível atrás/à frente da janela. | Opções simplificadas para Behind/In front; não é posição interna/externa do traço. |
| Excluded app bundle IDs | Texto validado como lista de IDs separados por vírgula. | Mantido em App exclusions; editor visual de apps pode ser uma melhoria posterior. |

## Aplicação imediata e situações sem efeito visual

Todos os controles mantidos salvam config validada e chamam o mesmo reload.
O reload atualiza o modelo de Settings, atualiza os painéis, atualiza as barras de
tabs e agenda o refresh de layout. Não há botão Apply adicional. As duas flags do
modo de sidebar são aplicadas juntas, evitando um estado intermediário conflitante.

Nem toda opção deve mudar a sidebar: tabs, bordas e gaps atuam principalmente nas
janelas. O estilo global só muda a sidebar em Custom; o tint só atua em Transparent
expandido. Reduce Transparency do macOS pode substituir transparência por um fundo
opaco. Essas dependências explicam parte dos controles que pareciam não disparar.
Não foi atribuída uma falha genérica ao mecanismo de refresh sem reproduzi-la.

## Validação no build instalado

- [x] Abrir Settings e revisar visualmente o layout de Sidebar & Appearance.
- [x] Trocar System/Custom e Glass/Solid; os controles condicionais acompanham a seleção.
- [x] Trocar os três fundos da sidebar e a tonalidade Pink; o painel muda sem reiniciar.
- [x] Selecionar cores sólidas e Custom; o preset mostra nome e amostra e disponibiliza o ColorPicker.
- [x] Trocar Compact rail, Always expanded e Auto-hide; flags persistem conjuntamente.
- [x] Editar a largura expandida de 280 para 320 pt; o painel muda imediatamente.
- [x] Always expanded desabilita o campo de largura compacta.
- [x] Ativar relógio e alterar segundos, data, dia da semana e status pills.
- [x] Alternar Show sidebar, focused-display filter e Show tab strips; valores persistem.
- [x] Alterar config externamente com auto-reload ativo; Settings reflete a configuração.
- [x] Editar o gap padrão de 4 para 6 mantendo overrides main=8 e secondary=12.
- [x] Simular falha de gravação com arquivo temporariamente imutável; Settings mostra
      o erro de permissão e restaura o toggle de bordas ao valor salvo. Bloqueio removido.
- [x] Renderizar e inspecionar prévias de Reduce Transparency e Increased Contrast
      com o renderer real da sidebar, sem mudar a acessibilidade global do macOS.
- [x] Restaurar a configuração original e verificar igualdade byte a byte.

### Limites da validação

- [ ] Verificação visual em dois monitores físicos: `list-monitors` retorna apenas
      Built-in Retina Display nesta sessão. Os overrides foram preservados no arquivo,
      mas o resultado no segundo monitor ainda precisa ser observado.
- [ ] Alternar Reduce Transparency no sistema com o app aberto: nesta sessão foi
      validado o renderer por prévias; não foi testada a mudança global ao vivo.
- [ ] Confirmar a barra de tabs num grupo ativo e os dois seletores nativos de cor de
      borda em interação completa. A alternância dos tabs e a recuperação de erro de
      bordas foram verificadas, mas não equivalem à inspeção visual desses fluxos.

Prévias geradas em `.release/appearance-review-build19/`. Capturas interativas e
relatórios de acessibilidade foram mantidos em `/tmp/winmuxx-*`; contêm dados da
sessão e não foram incluídos no repositório.

## Referências Apple e decisões de interface

- [Settings](https://developer.apple.com/design/human-interface-guidelines/settings): organização em grupos e clareza do alcance das preferências.
- [Toggles](https://developer.apple.com/design/human-interface-guidelines/toggles): configurações booleanas com alvo claramente identificado; escolhas mutuamente exclusivas são representadas por um menu nesta revisão.
- [Color wells](https://developer.apple.com/design/human-interface-guidelines/color-wells): ColorPicker nativo para cores personalizadas e bordas.
- [Color](https://developer.apple.com/design/human-interface-guidelines/color): preservar cores dinâmicas, contraste e comportamento de acessibilidade do sistema.

Ocultar controles sem efeito e agrupar os modos são decisões desta revisão, apoiadas
nesses princípios; não são exigências literais da Apple.

## Verificação

716 testes Swift passaram. Os novos testes verificam a gravação conjunta dos modos e
preservação de overrides de gaps, incluindo monitor principal, secundário, índice e
padrões com aspas. O build foi compilado pela suíte e pelo build Release 19. A assinatura foi
verificada com `codesign --verify --deep --strict`. O app e o CLI em execução
confirmaram o mesmo commit. Os limites da validação visual estão explicitados acima.

## Dimensões da janela de Settings

Em 2026-10-03, a janela Appearance do System Settings nesta máquina manteve a
largura de 757 pt ao tentar reduzi-la ou ampliá-la. O tamanho original era
757 × 818 pt; a altura mínima medida foi 470 pt. Ao pedir altura máxima, o
resultado foi 932 pt na posição original e 1074 pt no topo da área útil do
monitor. Portanto, o máximo vertical observado depende da área útil e da posição,
e não deve ser tratado como uma constante universal da Apple. A janela foi
restaurada ao tamanho e à posição originais após a medição.

WinMuxX agora usa largura de conteúdo fixa de 757 pt, altura inicial de 700 pt e
altura mínima de conteúdo de 470 pt, com redimensionamento vertical. A coluna de
navegação usa largura ideal de 200 pt. Estes ajustes e as amostras circulares são
posteriores ao build 19 instalado.

## Tamanho da sidebar recolhida

Collapsed sidebar size substitui o campo numérico por Small, Medium e Large,
usando a mesma chave `collapsed-width` e o reload imediato já existente. Medium
corresponde ao padrão de 44 pt. Valores personalizados do TOML são preservados e
identificados no menu; escolher um preset passa a salvar sua largura. Os presets
que não cabem na largura expandida ficam indisponíveis. O modo Always expanded
desabilita esse controle; Auto-hide continua usando a largura ao revelar o rail.
Este ajuste também é posterior ao build 19 instalado.

A fonte dos badges, suas dimensões, a altura dos seletores e o botão + agora
escalam com a largura recolhida. Medium mantém fonte de 18 pt, badge de 22 pt e
altura de seletor de 32 pt. Valores personalizados também ajustam a escala, com
limites para evitar controles excessivamente pequenos ou grandes. Os espaçamentos
internos respeitam a largura disponível; o layout expandido mantém sua escala.
Dois testes adicionais verificam a escala dos presets e a ausência de overflow
horizontal em larguras de 28 a 120 pt.

## Fundo no estilo Menu bar

Show menu bar background aparece em System + Menu bar style. O toggle local
mostra material translúcido quando ligado e fundo transparente quando desligado,
usando a chave `workspace-sidebar.menu-bar-background`. O padrão é desligado
para manter a barra recolhida transparente. Reduce Transparency tem prioridade.
O texto usa cores semânticas do sistema. Não há leitura periódica das
preferências do macOS.

A preferência global foi investigada e o toggle do sistema restaurado ao estado
original. Por escolha do usuário, o WinMuxX usa uma opção própria com reload
imediato. O material é uma aproximação nativa; AppKit não fornece o material
exato da menu bar. Esta alteração ainda não está instalada no build 19.

## Investigação do efeito real da menu bar

[Comparação de renderizadores e limites da equivalência](MENU_BAR_APPEARANCE_INVESTIGATION.md).
O toggle do build 20 usa `.headerView` como aproximação e não reproduz fielmente
o renderizador da menu bar. A referência desejada é System acompanhar a menu bar,
com aparência própria apenas em Custom.

## Bordas no Mission Control

Os painéis de bordas usavam `.stationary`, comportamento que o AppKit define como
visível e estacionário durante Exposé. Agora usam `.transient`, ocultado pelo
próprio sistema durante Exposé/Mission Control, sem depender de um refresh do
layout. A detecção existente da janela WindowManager nível 19 permanece como
proteção adicional. Não foi adicionado polling. A validação com Mission Control
aberto no build atualizado ainda precisa ser realizada após instalação.

### Palette and accessibility follow-up

Solid color now shows Custom, Blue, Purple, Pink, Red, Orange, Yellow, Green and
Graphite, in the order of the supplied System Settings reference. Preset values
are sRGB samples from that image, rather than AppKit semantic systemBlue/systemRed
colors, which are a different palette. Older named colors remain valid in config.
Solid sidebar text chooses black or white by relative luminance, including custom
colors, and Increased Contrast removes secondary text opacity.

Show background controls both the compact Liquid Glass surface and its expanded
surface over other windows. Non-always-expanded overlays add a native blur backing
when background is enabled. Reduce Transparency has priority over both toggle
states: it replaces all glass/blur/clear layers with opaque windowBackgroundColor.
SwiftUI's accessibility environment follows system preference changes without
polling. Automated checks cover background precedence and foreground contrast;
changing the actual macOS accessibility preference with the installed app remains
an outstanding manual check.

### Expanded sidebar follow-up

Expanded Liquid Glass always uses the earlier frosted surface (native blur plus
wallpaper-aware veil), including Always expanded and Show background disabled.
Show background now controls the compact rail only; Reduce Transparency still
forces an opaque surface in both states. Solid keeps its selected opaque color.
Expanded sidebar size offers Small (200 pt), Medium (240 pt, existing default),
and Large (280 pt), applying immediately through the existing width setting.
Existing custom widths remain selected until the user chooses a preset.
Validation: all 723 tests passed for the frosted surface change, including the
expanded/background/accessibility combinations.

### Sidebar position and height

Sidebar position offers Left (default) and Right. Both retain the selected display
edge while expanding, mirror the inner separator/corners and popup anchoring, and
reserve window space on the selected side. Text and item order stay unchanged.
Sidebar height replaces the clearance controls in Appearance and General:
Standard and Full fill the safe height; Centered measures the natural compact and
expanded content, fits the larger, and grows to 90% of the safe height before
scrolling. The same height is retained during hover expansion.
All modes protect the menu bar and notch, including the menu-bar reveal region
when auto-hidden. Thus Full and Standard currently have identical geometry.
Config keys are `position = 'left' | 'right'` and
`height-mode = 'standard' | 'centered' | 'full'`. Legacy clearance remains effective
only without height-mode and cannot reduce the mandatory system reservation.
Validation: geometry/config tests cover both edges, every height mode, negative
screen origins, centered growth, overflow, and legacy precedence. Actual multi-
monitor hover/drag and menu-bar reveal require manual validation after installation.

### Menu bar workspace indicator

Appearance → Menu bar now offers two indicator choices: Icon (default) and Workspace.
Workspace uses the first Unicode character of the configured label, uppercased;
blank/missing labels use the existing workspace number, or its presentation index
for named workspaces. It follows the focused display. The tooltip/accessibility
label identifies the full workspace name, and the existing action menu is retained.
Disabled management retains its pause icon. Icon color/monochrome controls appear
only for Icon. Preference changes persist locally and update immediately through
the existing model observation; no polling or extra permissions are introduced.
Validation: 729 tests passed, including blank labels, multi-digit numbers, accented
initials, emoji graphemes and wallpaper contrast on opposite display edges.

The indicator controls are in the active ShortcutAppearanceSettingsView, reached
by the Settings navigation. ShortcutGeneralView was legacy and has now been removed.

Repository cleanup: active config panes now live in SettingsGeneralView.swift,
SettingsWindowsView.swift, SettingsAppearanceView.swift and SettingsAutomationView.swift.
See HACKING.md for current architecture; earlier file references are historical.
