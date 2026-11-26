# lunar_fishing — Manual

Sistema de pesca com zonas de dificuldade progressiva, varas e iscas de níveis diferentes, aluguel de barcos e progressão de nível vinda do `cw-rep`.

---

## Sumário

1. [Dependências](#dependências)
2. [Instalação](#instalação)
3. [Configuração](#configuração)
4. [Controles](#controles)
5. [Como pescar](#como-pescar)
6. [Integrações](#integrações)
7. [Entrypoints para outros recursos](#entrypoints-para-outros-recursos)
8. [Localização](#localização)
9. [Estrutura de arquivos](#estrutura-de-arquivos)

---

## Dependências

| Recurso | Obrigatório | Observação |
|---|---|---|
| `ox_lib` | Sim | Callbacks, menus de contexto, zonas, keybinds e locale (o skill check foi trocado pelo minigame próprio) |
| `oxmysql` | Sim | Carregado nos `server_scripts` |
| `qb-core` **ou** `es_extended` | Sim | Framework. Detectado em runtime pelos arquivos de `framework/` |
| `cw-rep` | Sim | **Nesta fork o nível de pesca vem do `cw-rep`**, não de tabela própria. `fetchSkills`, `updateSkill`, `getCurrentSkill` e `getCurrentLevel` são chamados sem checagem de existência — sem o `cw-rep` o recurso quebra |
| `rep-talkNPC` | Sim | Os NPCs (pescador e locador de barcos) são criados por `exports['rep-talkNPC']:CreateNPC` |
| `qtarget` | Sim | `Utils.createPed` usa `exports.qtarget:AddCircleZone`. O export é intercompatível com `ox_target` e `qb-target` |
| Inventário | Sim | `ox_inventory`, `qb-inventory`, `ps-inventory`, `lj-inventory` ou `qs-inventory`. Detectado em runtime, apenas para resolver o caminho das imagens dos itens |
| `LegacyFuel` ou `ox_fuel` | Não | Abastece o barco alugado com 100 de combustível ao spawnar |

---

## Instalação

1. Copie a pasta `lunar_fishing` para `resources/`.
2. Adicione ao `server.cfg`:
   ```
   ensure ox_lib
   ensure oxmysql
   ensure lunar_fishing
   ```
3. Copie as imagens de `install/images/` para a pasta de imagens do seu inventário.
4. Cadastre os itens no seu inventário. Os guias prontos estão em `install/OX.md`, `install/QBCore.md` e `install/ESX.md`. Itens necessários:

   | Grupo | Itens |
   |---|---|
   | Varas | `basic_rod`, `graphite_rod`, `titanium_rod` |
   | Iscas | `worms`, `artificial_bait` |
   | Peixes | `anchovy`, `trout`, `haddock`, `salmon`, `grouper`, `piranha`, `red_snapper`, `mahi_mahi`, `tuna`, `shark` |

   As varas precisam ser **itens usáveis** — é o uso do item que inicia a pescaria.
5. **O `install/import.sql` não é mais necessário.** A tabela `lunar_fishing` existe no arquivo, mas todo o código que a lia e gravava (em `server/level.lua`) está comentado: o nível agora vem do `cw-rep`.

---

## Configuração

Arquivos: `config/config.lua` (compartilhado) e `config/sv_config.lua` (servidor).

### Geral

| Campo | Tipo | Obrigatório | Descrição |
|---|---|---|---|
| `Config.progressPerCatch` | number | Sim | XP de `fishing` enviado ao `cw-rep` a cada peixe capturado. Padrão: `1` |
| `SvConfig.Webhook` | string | Não | Webhook do Discord para log de capturas. Enquanto for `'WEBHOOK_HERE'`, nada é enviado |

### Peixes (`Config.fish`)

| Campo | Tipo | Obrigatório | Descrição |
|---|---|---|---|
| `price` | number ou `{min, max}` | Sim | Preço de venda. Se for faixa, é sorteado na hora da venda |
| `chance` | number | Sim | Peso relativo do sorteio dentro da lista de peixes da zona |
| `minigame` | table | Não | Como o peixe se comporta no minigame: `{ difficulty, behavior, color }`. Ver [Minigame](#minigame-configminigame) |
| `skillcheck` | array | Não | Só é usado se o peixe não tiver `minigame`: a dificuldade é calculada somando `easy` = 1, `medium` = 2, `hard` = 3 |

#### `minigame` de cada peixe

| Campo | Tipo | Descrição |
|---|---|---|
| `difficulty` | number | De 1 a 100, igual ao Stardew Valley. Quanto maior, mais rápido e mais vezes o peixe muda de direção |
| `behavior` | string | Jeito de nadar: `mixed` (de tudo um pouco), `dart` (dá trancos), `smooth` (suave), `sinker` (puxa pro fundo), `floater` (puxa pra cima) |
| `color` | string | Cor do peixinho no minigame, em hex (`'#e8865a'`) |

### Painel do pescador (`Config.shop`)

| Campo | Padrão | Descrição |
|---|---|---|
| `enabled` | `true` | `false` volta pro menu de contexto antigo do ox_lib |
| `title` | `'Corporação Marítima'` | Título do painel |
| `outsideLabel` | `'Qualquer água'` | Nome da "zona" de fora no painel |
| `maxAmount` | `100` | Quantidade máxima por compra |

Cada zona em `Config.fishingZones` tem um `label`, que é o nome mostrado no painel.

Callbacks do painel (servidor, `server/shop.lua`): `lunar_fishing:shopData`, `lunar_fishing:shopBuy` (`{ type, index, amount }`) e `lunar_fishing:shopSell` (`{ [peixe] = quantidade }`). Todos validam nível, dinheiro e quantidade.

### Níveis (`Config.levels` e `Config.progressPerCatch`)

O XP fica na skill `fishing` do `cw-rep`. `Config.getFishingLevel(xp)` devolve `nivel, xpDoNivel, xpDoProximo` usando a mesma tabela exponencial do `cw-rep` (`baseExp = 10`, `scaleFactor = 1.5`, `levelCount = 30`): nível 1 = 10 XP, 2 = 25, 3 = 48, 4 = 82, 5 = 133. `Config.progressPerCatch` (padrão `1`) é o XP ganho por peixe.

No servidor também existem `GetPlayerFishingXp(source)`, `GetPlayerFishingLevel(source)` e `FishingLevelFromXp(xp)`.

### Minigame (`Config.minigame`)

| Campo | Padrão | Descrição |
|---|---|---|
| `barSize` | `{ basic_rod = 104, graphite_rod = 120, titanium_rod = 136 }` | Altura da barra verde por vara. O trilho inteiro tem 568, então vara melhor = barra maior = mais fácil |
| `defaultBarSize` | `104` | Altura usada se a vara não estiver em `barSize` |
| `startProgress` | `0.3` | Progresso inicial (0 a 1) |
| `gainRate` | `0.002` | Quanto o progresso enche por tick (60 por segundo) com o peixe dentro da barra |
| `lossRate` | `0.003` | Quanto esvazia por tick com o peixe fora |
| `scale` | `3.6` | Tamanho na tela (o desenho tem 46x164 pixels e é multiplicado por isso) |
| `position` | `{ x = 62, y = 50 }` | Posição na tela, em % |
| `sound` | `true` | Sons do molinete, de vitória e de derrota |
| `hint` | `true` | Plaquinha com as teclas embaixo do minigame |

### Varas (`Config.fishingRods`)

| Campo | Tipo | Obrigatório | Descrição |
|---|---|---|---|
| `name` | string | Sim | Nome do item |
| `price` | number | Sim | Preço na loja do pescador |
| `minLevel` | number | Sim | Nível mínimo de `fishing` para comprar |
| `breakChance` | number | Sim | Chance percentual da vara quebrar **quando a pescaria falha** |

### Iscas (`Config.baits`)

| Campo | Tipo | Obrigatório | Descrição |
|---|---|---|---|
| `name` | string | Sim | Nome do item |
| `price` | number | Sim | Preço na loja do pescador |
| `minLevel` | number | Sim | Nível mínimo de `fishing` para comprar |
| `waitDivisor` | number | Sim | Divide o tempo de espera até o peixe morder. Quanto maior, mais rápido |

O jogo usa automaticamente a **isca mais cara** que o jogador tiver no inventário.

### Zonas de pesca (`Config.fishingZones`)

| Campo | Tipo | Obrigatório | Descrição |
|---|---|---|---|
| `blip` | tabela | Não | `name`, `sprite`, `color`, `scale`. O blip só aparece se o jogador tiver o nível mínimo |
| `locations` | array de `vector3` | Sim | Pontos onde a zona pode existir. Cada um vira uma zona esférica |
| `radius` | number | Sim | Raio da zona |
| `minLevel` | number | Sim | Nível mínimo para a zona existir no cliente |
| `waitTime` | `{min, max}` | Sim | Faixa de espera, em segundos, até o peixe morder |
| `includeOutside` | bool | Sim | Quando `true`, os peixes de `Config.outside.fishList` também podem ser fisgados dentro da zona |
| `message` | `{enter, exit}` | Não | Notificações ao entrar e sair da zona |
| `fishList` | array | Sim | Peixes disponíveis na zona |

Zonas que vêm no config: Coral Reef (nível 1), Swamp (nível 2) e Deep Waters (nível 3).

### Fora das zonas (`Config.outside`)

| Campo | Tipo | Obrigatório | Descrição |
|---|---|---|---|
| `waitTime` | `{min, max}` | Sim | Espera, em segundos, em água comum |
| `fishList` | array | Sim | Peixes pescáveis fora de qualquer zona. Padrão: `trout`, `anchovy`, `haddock`, `salmon` |

### NPC pescador (`Config.ped`)

| Campo | Tipo | Obrigatório | Descrição |
|---|---|---|---|
| `buyAccount` | string | Sim | Conta usada para comprar varas e iscas. Padrão: `money` |
| `sellAccount` | string | Sim | Conta que recebe o dinheiro da venda de peixes. Padrão: `money` |
| `model` | string | Sim | Modelo do ped |
| `name` / `tag` / `startMSG` / `message` | string | Sim | Nome, etiqueta, saudação e diálogo do `rep-talkNPC` |
| `locations` | array de `vector4` | Sim | Posições do NPC |
| `blip` | tabela | Não | Está **comentado** no config que vem no repositório — o NPC não gera blip |

### Aluguel de barcos (`Config.renting`)

| Campo | Tipo | Obrigatório | Descrição |
|---|---|---|---|
| `account` | string | Sim | Conta usada na cobrança e no reembolso. Padrão: `money` |
| `boats` | array | Sim | Cada item tem `model` (hash), `price` e `image` (URL exibida no menu) |
| `blip` | tabela | Sim | `name`, `sprite`, `color`, `scale` |
| `returnDivider` | number | Sim | O reembolso da devolução é `price / returnDivider`. Padrão: `5` |
| `returnRadius` | number | Sim | Raio do ponto de devolução. Padrão: `30.0` |
| `model` / `name` / `tag` / `startMSG` / `message` | string | Sim | Ped e diálogo do `rep-talkNPC` do locador |
| `locations` | array | Sim | Cada item tem `coords` (posição do NPC) e `spawn` (onde o barco nasce e onde é devolvido) |

> `Config.renting.model` está declarado duas vezes na tabela (linhas 150 e 167 do config). Vale a segunda — ambas são `s_m_m_dockwork_01`, então não há diferença prática, mas edite as duas se for trocar o modelo.

### Cliente (`config/cl_edit.lua`)

Arquivo de wrappers, não de opções: notificação, TextUI, progressbar, `SetVehicleFuel`, `SetVehicleOwner` e resolução do caminho das imagens do inventário. Edite aqui se o seu servidor usa outro sistema de notificação ou de combustível.

---

## Controles

| Tecla | Padrão | Descrição |
|---|---|---|
| `anchor_toggle` | `G` | Baixa/levanta a âncora do barco. Só funciona com o barco quase parado (velocidade abaixo de 3.0) |
| `fishing_interaction` | `E` | Devolve o barco alugado, dentro do raio do ponto de devolução |

Ambas são registradas via `lib.addKeybind` e podem ser remapeadas pelo jogador em Configurações > Teclas > FiveM.

Durante o minigame, **clique esquerdo**, **E** ou **espaço** (segurados) sobem a barra verde. Essas teclas ficam bloqueadas pro resto do jogo enquanto o minigame está aberto.

---

## Como pescar

1. Compre uma vara e iscas no painel do NPC pescador (abas "Varas" e "Iscas"). Varas e iscas de nível superior ficam bloqueadas até o nível de `fishing` correspondente.
2. Fique de frente para a água, em pé — não funciona nadando nem dentro de veículo. O recurso testa se há água à frente com `TestProbeAgainstWater`.
3. **Use a vara pelo inventário.** Não existe comando de pesca; o gatilho é o item usável.
4. A isca mais cara do inventário é consumida e começa a espera (faixa da zona, dividida pelo `waitDivisor` da isca).
5. Quando o peixe morder, abre o minigame: segure clique esquerdo, `E` ou espaço pra subir a barra verde e mantenha o peixe dentro dela até a barra de progresso encher (veja o `README.md`). Enquanto espera a mordida, segurar `E` cancela a pescaria.
6. Sucesso: o peixe entra no inventário e o XP de `fishing` sobe. Falha: nada é ganho e a vara pode quebrar conforme o `breakChance` dela.
7. Venda os peixes no painel do NPC pescador, na aba "Vender".

---

## Integrações

### cw-rep

O nível de pesca é inteiramente delegado ao `cw-rep`, na skill `fishing`:

- a cada peixe capturado, o servidor chama `exports["cw-rep"]:updateSkill(source, 'fishing', Config.progressPerCatch)`;
- o `cw-rep` guarda **XP** (`exports["cw-rep"]:fetchSkills(source).fishing`); o nível usado para liberar zonas, varas e iscas é calculado com `Config.getFishingLevel(xp)`, que replica a tabela de níveis do `cw-rep`;
- depois de cada peixe, o servidor manda o nível novo pro cliente (`lunar_fishing:updateLevel`) e avisa quando o jogador sobe de nível;
- o painel do NPC mostra nível e XP a partir do mesmo cálculo.

O sistema de XP original (tabela `lunar_fishing` no MySQL) foi desativado — o código está no arquivo, comentado.

### rep-talkNPC

Os dois NPCs são criados com `exports['rep-talkNPC']:CreateNPC`, com o diálogo de apresentação definido nos campos `name`, `tag`, `startMSG` e `message` de `Config.ped` e `Config.renting`. As opções do target (abrir a loja do pescador, abrir o aluguel de barcos) são registradas via `qtarget`.

---

## Entrypoints para outros recursos

O recurso **não expõe exports nem comandos**. O que existe são callbacks e eventos internos, usados na comunicação cliente-servidor.

### Callbacks de servidor

```lua
-- Vende `amount` do peixe indicado, com 3s de delay antes de creditar
lib.callback.await('lunar_fishing:sellFish', false, fishName, amount)

-- Compra vara ou isca. data = { type = 'fishingRods' | 'baits', index = <índice no Config> }
lib.callback.await('lunar_fishing:buy', false, data, amount)

-- Aluga o barco de índice `index` em Config.renting.boats
lib.callback.await('lunar_fishing:rentVehicle', false, index)

-- Devolve o barco; o jogador precisa estar no banco do motorista
lib.callback.await('lunar_fishing:returnVehicle', false, netId)

-- Nível atual de fishing (proxy do cw-rep)
lib.callback.await('lunar_fishing:getLevel', false)

-- Mapa de itemName -> label, montado a partir dos itens do framework
lib.callback.await('lunar_fishing:getItemLabels', false)
```

### Eventos

```lua
-- Servidor -> cliente: exibe uma notificação do ox_lib
TriggerClientEvent('lunar_fishing:showNotification', source, 'mensagem', 'success')

-- Cliente -> servidor: registra o barco recém-spawnado como alugado
TriggerServerEvent('lunar_fishing:registerBoat', netId)

-- Servidor -> cliente: atualiza o nível e recria blips e zonas
TriggerClientEvent('lunar_fishing:updateLevel', source, level)
```

---

## Localização

As strings são traduzidas via `ox_lib` locale. Os arquivos ficam em `locales/`:

- `en.json` — inglês
- `de.json` — alemão
- `pt-br.json` — português do Brasil

O locale ativo é definido pela convar `ox:locale` no `server.cfg`:

```
setr ox:locale "pt-br"
```

As mensagens de entrada e saída das zonas (`Config.fishingZones[].message`) e os diálogos dos NPCs **não** passam pelo locale: estão escritos direto em `config/config.lua`.

---

## Estrutura de arquivos

```
lunar_fishing/
├── client/
│   ├── main.lua          — zonas, blips, teste de água e a pescaria em si
│   ├── minigame.lua      — abre o minigame (NUI), lê as teclas e devolve o resultado
│   ├── shop.lua          — abre o painel do pescador e repassa compra/venda pro servidor
│   ├── ped.lua           — NPC pescador: menu de comprar varas/iscas e vender peixes
│   ├── rent.lua          — NPC locador: menu de aluguel, spawn e devolução do barco
│   ├── level.lua         — cache do nível de fishing no cliente
│   └── anchor.lua        — keybind da âncora do barco
├── server/
│   ├── main.lua          — registra as varas como itens usáveis; sorteia o peixe e resolve a captura
│   ├── ped.lua           — callbacks de venda de peixe e compra de vara/isca
│   ├── rent.lua          — callbacks de aluguel e devolução de barco
│   └── level.lua         — callback de nível (proxy do cw-rep; código MySQL original comentado)
├── config/
│   ├── config.lua        — peixes, varas, iscas, zonas, NPCs e aluguel
│   ├── sv_config.lua     — webhook do Discord
│   └── cl_edit.lua       — wrappers de notificação, TextUI, progressbar, fuel e imagens
├── framework/
│   ├── qb/{client,server}.lua
│   └── esx/{client,server}.lua
├── utils/
│   ├── cl_main.lua       — criação dos NPCs (rep-talkNPC + qtarget), blips e keybinds
│   └── sv_main.lua       — log no Discord e cache de labels dos itens
├── locales/
│   ├── en.json
│   ├── de.json
│   └── pt-br.json
├── html/
│   ├── index.html        — minigame estilo Stardew Valley (abra com ?test pra testar no navegador)
│   ├── style.css
│   ├── script.js         — física, desenho em pixel art e sons
│   ├── shop.css
│   └── shop.js           — painel do pescador (abra com ?shop pra testar no navegador)
├── docs/                 — imagens do README
├── install/
│   ├── OX.md             — itens para o ox_inventory
│   ├── QBCore.md         — itens para o qb-core
│   ├── ESX.md            — itens para o ESX
│   ├── import.sql        — tabela lunar_fishing (não utilizada nesta fork)
│   └── images/           — imagens dos itens (copiar para o inventário)
└── fxmanifest.lua
```
