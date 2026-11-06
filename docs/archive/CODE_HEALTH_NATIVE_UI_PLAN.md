# Plano verificado: limpeza e controles nativos

Revisão: 2026-10-05. Este documento planeja mudanças; não autoriza remover alterações preexistentes do worktree nem afirma que os protótipos abaixo já funcionam.

## Objetivo e limites

Corrigir o ciclo de vida da sidebar, eliminar caminhos comprovadamente inativos e avaliar controles AppKit onde trouxerem benefício. Preservar a aparência aprovada: recolhida transparente, expandida com frost, opção Show background e cores semânticas. Não alterar numeração dinâmica/persistent workspaces, override, Dwindle, bordas ou glide nesta limpeza.

Não substituir componentes que já são nativos: painel, menu de contexto, status item, alertas, materiais, labels e campo de rename. Não tratar abas de outras aplicações como um caso para NSTabView.

## Evidências conferidas

| Achado | Evidência | Consequência |
|---|---|---|
| Painéis antigos permanecem no registro | `WorkspaceSidebarPanelController.swift`: `refreshAll` esconde escopos inativos, sem removê-los | Investigar/reparar descarte quando monitor/configuração muda; esconder temporariamente não equivale a destruir |
| Observadores sem encerramento explícito | `WorkspaceSidebarPanelMenuTracking.swift` registra tokens armazenados em `menuTrackingObservers` | Criar encerramento idempotente; não simplesmente apagar o armazenamento |
| Estado global apagado por painel inativo | `WorkspaceSidebarPanelLifecycle.swift`: `resetHiddenSidebarState` zera drop targets e preview globais | Um painel antigo pode invalidar o arraste de um painel ativo |
| Singleton separado do registro | `WorkspaceSidebarPanelController.swift`: `shared` cria outro painel | Resolver fallbacks pelo painel registrado; evitar duplicação e ressurgimento após descarte |
| Limite de largura duplicado | `WorkspaceSidebarGeometry.swift`: variável `maximumExpandedWidth` sem uso, frame calculado com `width * 2` | Centralizar o limite, mantendo a expansão dupla de split browsing |
| Renderizador antigo sem entrada de produção | `WorkspaceSidebarAppearance.swift`: cadeia iniciada em `WorkspaceSidebarSystemSurface` | Migrar testes antes de remover; preservar `WorkspaceSidebarFrostedVeil`, que continua ativo |
| Testes validam caminho antigo | `WorkspaceSidebarAppearanceTest.swift` instancia `WorkspaceSidebarVisualEffect` | Testar `WorkspaceSidebarMaterialContainer`, usado pelo painel real |
| Busca não é campo de texto nativo | `WorkspaceSidebarView.swift` e `WorkspaceSidebarViewEditing.swift`: Text + tratamento manual de teclas | Prototipar NSSearchField para edição, seleção e IME |
| Popup com posicionamento próprio | `WorkspaceSidebarProjectPopup.swift`, `WorkspaceSidebarMonitorSelector.swift`, `WorkspaceSidebarProjectPagerActions.swift` | Prototipar NSPopover para ancoragem e fechamento |

Os caminhos de produção acima estão em `Sources/AppBundle/ui/sidebar/`; os testes em `Sources/AppBundleTests/ui/`. Ausência de limpeza aponta um problema de ciclo de vida, mas consumo crescente de memória ainda exige reprodução/medição.

## 1. Corrigir ciclo de vida e isolamento por painel

Prioridade alta; entrega separada de qualquer mudança visual.

- Classificar escopos: painel válido temporariamente escondido versus painel aposentado por desconexão, mudança de geometria/escopo ou configuração. Não recriar a cada fullscreen, Mission Control ou refresh de foco.
- Implementar encerramento explícito no main actor, idempotente: cancelar work items; invalidar callbacks enfileirados com geração/estado de encerramento; remover observadores de menu e monitores de eventos; invalidar event tap/runloop source; terminar edição; limpar locks/buffers; esconder e fechar o painel; remover o registro.
- Tornar instalação de observadores idempotente. Reutilizar a limpeza de monitores de comando hoje privada em `WorkspaceSidebarCommandActions.swift`, sem acionar animação de fechamento como efeito colateral.
- Garantir desmontagem do capturador de swipe e de seu monitor local ao aposentar conteúdo. Integrar fechamento de popovers quando existirem.
- Trocar o singleton independente por resolução do painel registrado, auditando todos os fallbacks de `shared` para não criar recursão ou painel extra.
- Separar limpeza local de estado compartilhado. Guardar targets por painel/escopo e agregar os válidos; aposentar um painel não pode apagar targets, hover ou preview pertencentes a outro.

Aceite automatizado: descarte repetido é seguro; instalação repetida não duplica observadores; callbacks antigos não reabrem painel; desconectar/reconectar não acumula registros; fullscreen mantém painel reutilizável; aposentar A preserva arraste em B; encerrar durante busca/rename solta captura de teclado.

Aceite manual: dois monitores, alteração de disposição, escolha de monitor na configuração, desconexão durante edição/arraste, fullscreen/Mission Control. Comparar número de painéis/observadores antes e depois de ciclos repetidos. Não adicionar polling para reconciliar o registro.

## 2. Limpeza pequena e largura canônica

Confirmar referências novamente no código e nos testes imediatamente antes de cada remoção.

Candidatos já conferidos: `focusOrReportNoop` em `command/impl/WorkspaceCommand.swift`; `workspaceSidebarMonitorScopeIsSentinel`; `WorkspaceSidebarWorkspaceSection.headerButton` e `contentWidth` e seu helper exclusivo `workspaceSidebarContentWidth`; wrappers sem argumento `currentSidebarPanelLayout`, `workspaceSidebarPanelScreen` e `createWorkspaceFromSidebarButton`; armazenamento redundante `WorkspaceSidebarMaterialContainer.wallpaperTone` (não o parâmetro usado para configurar cores).

Preservar overloads parametrizados e interações atuais de override. Nenhum arquivo Swift inteiro foi comprovado descartável nesta revisão.

Criar uma definição canônica da largura máxima de expansão e usá-la em geometria, split browsing e persistência da largura após reload. Manter o comportamento atual de duas vezes a largura configurada; não criar nova configuração nem reduzir o split por apagar a variável local.

Aceite: testes existentes de geometria/override passam; adicionar casos de split, reload e bordas esquerda/direita se não cobertos. Sem mudança visual ou funcional nesta entrega.

## 3. Testar o material real e remover renderer antigo

Primeiro migrar testes para `WorkspaceSidebarMaterialContainer`, depois remover a cadeia inativa `WorkspaceSidebarSystemSurface`, `WorkspaceSidebarNativeGlass`, `WorkspaceSidebarVisualEffect` e `WorkspaceSidebarFrostedSurface`, se a nova busca confirmar ausência de consumidores. Manter o veil ativo.

Os testes antigos de frost exigem `.hudWindow` e alpha 0,93, enquanto o container atual usa outra composição. Não copiar essas expectativas para preservar comportamento obsoleto: validar os modos aprovados no caminho real.

Cobrir recolhida/expandida, Show background ligado/desligado, aparência custom, Reduce Transparency, ambos os lados, conteúdo sem mudança de coordenadas e material restrito à largura visível. Manter NSGlassEffectView protegido pela disponibilidade do macOS 26 e fallback NSVisualEffectView para versões suportadas anteriores.

Aceite manual obrigatório: nenhuma mudança perceptível na sidebar aprovada. Não prometer contraste nativo independente por display: o sinal de aparência do status item é compartilhado. Revisão de 2026-10-06: amostras válidas do wallpaper local têm prioridade; wallpapers dinâmicos/indisponíveis usam o fallback nativo. Isso não comprova contraste independente para cada variante dinâmica.

## 4. Piloto NSSearchField

Usar um adapter AppKit/SwiftUI e binding para busca; não substituir o campo nativo de rename. Definir dono da edição para evitar que o event tap global e o field editor processem a mesma tecla.

Preservar abertura pelo comando, primeira tecla em buffer, filtro, seleção por setas, Return, Escape, clear, foco restaurado e locks de expansão. Respeitar composição/marked text antes de interpretar Return/Escape como ação da sidebar.

Aceite: testes do adapter e roteamento; teste real de acentos, colagem, seleção, edição no meio do texto e IME; dois monitores, expandida/recolhida e rename. Só tornar padrão após passar esses critérios, em uma entrega isolada.

Referência: [NSSearchField](https://developer.apple.com/documentation/appkit/nssearchfield). `.searchable` não é uma substituição direta para a arquitetura atual de painel flutuante.

## 5. Piloto NSPopover

Compartilhar um apresentador entre seletor de monitor e projetos. Reutilizar o conteúdo SwiftUI existente, evitando fundo/material duplicado. Ancorar no botão correto e permitir que AppKit ajuste aos limites da tela.

Controlar expansão com abertura/fechamento do popover e delegate; preservar locks de comando e grace de menus. Fechar por Escape, clique externo e aposentadoria do painel. Preservar seleção, rename, cor, exclusão, menus de contexto e destinos de arraste existentes.

Aceite: ambas as posições, monitores diferentes, mudança de foco, menus dentro do popup e nenhuma captura de eventos restante após fechamento. Só adotar após comparação visual e funcional.

Referência: [NSPopover](https://developer.apple.com/documentation/appkit/nspopover).

## 6. Prevenção de regressões e entrega

- Configurar Periphery inicialmente em modo informativo; a varredura atual do scheme do app não considera todos os usos nos testes. Indexar app/testes/helpers antes de ativar gate.
- Não apagar resultados automaticamente. Codable/DTOs, callbacks Objective-C, igualdade sintetizada e helpers usados só em testes precisam análise. Exemplos a preservar: `WallpaperAnalyzer.tone(for:)` usado nos testes e `Appearance.settings` usado indiretamente por Equatable.
- Depois da limpeza, registrar baseline justificado e bloquear novos achados confirmados na CI; evitar supressão ampla que esconda regressões.
- Cada fase: diff limitado, `git diff --check`, testes específicos, `make check` e build do app. Commits não devem incluir alterações antigas sem relação.
- Antes de instalar: build novo, assinatura verificada, backup recuperável fora de Applications, versão instalada e processo confirmados. Instalar uma entrega validada por vez.
- Smoke test de proteção: override nos dois tamanhos, numeração/persistent workspaces, Cmd+W e botão fechar sem borda fantasma, app quit, Mission Control, Dwindle 3→2 e três colunas no segundo monitor sem tremor. Não usar testes unitários como prova de comportamento real do WindowServer.

## Verificação deste plano

Conferido contra referências e implementação atuais: preserva largura split, overloads ativos e veil; migra testes antes de apagar renderer; inclui singleton e callbacks atrasados no descarte; separa targets globais do ciclo local; diferencia esconder de aposentar; trata controles nativos como pilotos, não correções garantidas.

Baseline da revisão anterior nesta árvore: 785 testes passando e `git diff --check` sem erros. Esse resultado não prova cenários manuais nem significa que as mudanças planejadas já foram testadas. Nesta etapa somente este documento é criado e verificado.

Ordem de execução: ciclo de vida → limpeza/largura → material/testes → busca nativa → popover nativo. Preparar análise estática desde o início; ativar o gate após revisar o baseline.
