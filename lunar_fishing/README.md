# lunar_fishing
An advanced fishing script that enchances the roleplay on your server!

# Features
* Supports ESX/QBCore
* Create as many zones as you wish!
* Fish anywhere
* Level & XP system
* Freelancer job
* Boat renting included
* ox_target/qtarget/qb-target support
* Very low resmon - 0.0ms on idle
* Installation files included

# Dependencies: 
* es_extended/qb-core
* ox_lib
* ox_target/qtarget/qb-target

### Preview: https://youtu.be/XUfPRGEm9_I

### Discord: https://discord.gg/zDK4CHQ56N

---

## Modificações do Atitude RP

- **Minigame de pesca estilo Stardew Valley** no lugar do `lib.skillCheck` do ox_lib (NUI em pixel art, pasta `html/`).
  - Segure **clique esquerdo**, **E** ou **espaço** pra subir a barra verde; mantenha o peixe dentro dela até encher o progresso.
  - Dica das teclas embaixo do minigame (`Config.minigame.hint`).
  - Cada peixe tem `minigame = { difficulty, behavior, color }` no `config/config.lua` (`behavior`: `mixed`, `dart`, `smooth`, `sinker`, `floater`).
  - Tamanho da barra verde por vara em `Config.minigame.barSize` (vara melhor = barra maior).
  - Pra testar fora do jogo: abra `html/index.html?test` no navegador.
- Corrigido: o tempo de espera das zonas de pesca não era usado (sempre caía no de fora das zonas).
- Corrigido: erro de digitação em `setCanRagdoll` (`statefalse`).
