Config = {}

Config.progressPerCatch = 1 -- XP ganho por peixe pescado (era 5)
-- Com 1 XP por peixe: nível 1 = 10 peixes, nível 2 = 25, nível 3 = 48, nível 4 (vara de titânio) = 82, nível 5 = 133

-- Níveis de pesca: o XP fica no cw-rep (skill 'fishing') e o nível sai desta tabela.
-- TEM que ser igual ao Config.DefaultLevels do cw-rep (baseExp = 10, scaleFactor = 1.5, levelCount = 30).
-- Com isso: nível 1 = 10 XP, nível 2 = 25 XP, nível 3 = 48 XP, nível 4 = 82 XP, nível 5 = 133 XP...
Config.levels = { baseExp = 10, scaleFactor = 1.5, levelCount = 30 }

do
    local thresholds = { 0 }
    local fromExp = 0

    for i = 1, Config.levels.levelCount do
        local toExp = fromExp + Config.levels.baseExp * Config.levels.scaleFactor ^ (i - 1)
        fromExp = math.floor(toExp + 0.5)
        thresholds[i + 1] = fromExp
    end

    --- Converte XP de pesca em nível.
    ---@param xp number?
    ---@return integer level, integer fromXp, integer? toXp (nil = nível máximo)
    function Config.getFishingLevel(xp)
        xp = tonumber(xp) or 0
        local level = 0

        for i = 2, #thresholds do
            if xp >= thresholds[i] then
                level = i - 1
            else
                break
            end
        end

        return level, thresholds[level + 1], thresholds[level + 2]
    end
end

---@class Fish
---@field price integer | { min: integer, max: integer }
---@field chance integer Percentage chance
---@field skillcheck SkillCheckDifficulity Usado só se o peixe não tiver `minigame`
---@field minigame { difficulty: number, behavior: string?, color: string? }?

---@type table<string, Fish>
-- Preços equilibrados por simulação (jogador médio, minhoca, vara da zona):
--   fora das zonas ~5 mil/h | recife ~6,5 mil/h | pântano ~10 mil/h | águas profundas ~12 mil/h (grafite) / ~23 mil/h (titânio)
-- minigame.difficulty: 1 a 100 (igual ao Stardew). minigame.behavior: 'mixed', 'dart' (dá trancos),
-- 'smooth' (suave), 'sinker' (puxa pro fundo), 'floater' (puxa pra cima). minigame.color: cor do peixinho.
Config.fish = {
    ['anchovy'] = { price = { min = 40, max = 55 }, chance = 35, skillcheck = { 'easy', 'easy' }, minigame = { difficulty = 20, behavior = 'dart', color = '#9fb7c9' } },
    ['trout'] = { price = { min = 55, max = 65 }, chance = 35, skillcheck = { 'easy', 'easy' }, minigame = { difficulty = 25, behavior = 'mixed', color = '#d98fb0' } },
    ['haddock'] = { price = { min = 70, max = 90 }, chance = 20, skillcheck = { 'easy', 'easy' }, minigame = { difficulty = 35, behavior = 'sinker', color = '#b9a27a' } },
    ['salmon'] = { price = { min = 110, max = 140 }, chance = 10, skillcheck = { 'easy', 'easy', 'medium' }, minigame = { difficulty = 45, behavior = 'mixed', color = '#e8865a' } },
    ['grouper'] = { price = { min = 280, max = 340 }, chance = 25, skillcheck = { 'easy', 'easy', 'medium', 'medium' }, minigame = { difficulty = 55, behavior = 'sinker', color = '#7d8a4a' } },
    ['piranha'] = { price = { min = 510, max = 630 }, chance = 25, skillcheck = { 'easy', 'easy', 'hard' }, minigame = { difficulty = 55, behavior = 'dart', color = '#d64a3a' } },
    ['red_snapper'] = { price = { min = 210, max = 250 }, chance = 20, skillcheck = { 'easy', 'easy', 'medium', 'medium' }, minigame = { difficulty = 50, behavior = 'mixed', color = '#e0453a' } },
    ['mahi_mahi'] = { price = { min = 240, max = 290 }, chance = 20, skillcheck = { 'easy', 'easy', 'medium', 'medium' }, minigame = { difficulty = 60, behavior = 'smooth', color = '#5fc24a' } },
    ['tuna'] = { price = { min = 620, max = 750 }, chance = 5, skillcheck = { 'easy', 'easy', 'hard' }, minigame = { difficulty = 75, behavior = 'smooth', color = '#3d6fb8' } },
    ['shark'] = { price = { min = 1400, max = 1700 }, chance = 1, skillcheck = { 'easy', 'easy', 'hard' }, minigame = { difficulty = 85, behavior = 'mixed', color = '#8a96a3' } },
}

-- Minigame de pesca (estilo Stardew Valley). Segure clique esquerdo, E ou espaço pra subir a barra verde.
Config.minigame = {
    -- Tamanho da barra verde por vara (o trilho tem 568; no Stardew começa em 96)
    barSize = {
        basic_rod = 104,
        graphite_rod = 120,
        titanium_rod = 136,
    },
    defaultBarSize = 104,
    startProgress = 0.3, -- progresso inicial (0 a 1)
    gainRate = 0.002,    -- quanto enche por tick com o peixe dentro da barra
    lossRate = 0.003,    -- quanto esvazia por tick com o peixe fora
    scale = 3.6,         -- tamanho na tela (pixel art 46x164 multiplicado por isso)
    position = { x = 62, y = 50 }, -- posição na tela em %
    sound = true,
    hint = true,         -- mostra a dica das teclas embaixo do minigame
}

---@class FishingRod
---@field name string
---@field price integer
---@field minLevel integer The minimal level
---@field breakChance integer Percentage chance

---@type FishingRod[]
Config.fishingRods = {
    { name = 'basic_rod', price = 1000, minLevel = 0, breakChance = 20 },
    { name = 'graphite_rod', price = 2500, minLevel = 2, breakChance = 10 },
    { name = 'titanium_rod', price = 5000, minLevel = 4, breakChance = 1 },
}

---@class FishingBait
---@field name string
---@field price integer
---@field minLevel integer The minimal level
---@field waitDivisor number The total wait time gets divided by this value

---@type FishingBait[]
Config.baits = {
    { name = 'worms', price = 5, minLevel = 0, waitDivisor = 1.0 },
    { name = 'artificial_bait', price = 60, minLevel = 2, waitDivisor = 2.0 },
}

---@class FishingZone
---@field locations vector3[] One of these gets picked at random
---@field radius number
---@field minLevel integer
---@field waitTime { min: integer, max: integer }
---@field includeOutside boolean Whether you can also catch fish from Config.outside
---@field blip BlipData?
---@field message { enter: string, exit: string }?
---@field fishList string[]

---@type FishingZone[]
Config.fishingZones = {
    {
        blip = {
            name = 'Coral Reef',
            sprite = 317,
            color = 24,
            scale = 0.6
        },
        locations = {
            vector3(-1774.0654, -1796.2740, 0.0),
            vector3(2482.8589, -2575.6780, 0.0)
        },
        label = 'Recife de Coral', -- nome mostrado no painel do pescador
        radius = 250.0,
        minLevel = 1,
        waitTime = { min = 12, max = 25 },
        includeOutside = true,
        message = { enter = 'Você entrou em um recife de coral.', exit = 'Você deixou o recife de coral.' },
        fishList = { 'mahi_mahi', 'red_snapper' }
    },
    {
        blip = {
            name = 'Deep Waters',
            sprite = 317,
            color = 29,
            scale = 0.6
        },
        locations = {
            vector3(-4941.7964, -2411.9146, 0.0),
        },
        label = 'Águas Profundas', -- nome mostrado no painel do pescador
        radius = 1000.0,
        minLevel = 3,
        waitTime = { min = 25, max = 45 },
        includeOutside = false,
        message = { enter = 'Você entrou em águas profundas.', exit = 'Você deixou águas profundas.' },
        fishList = { 'grouper', 'tuna', 'shark' }
    },
    {
        blip = {
            name = 'Swamp',
            sprite = 317,
            color = 56,
            scale = 0.6
        },
        locations = {
            vector3(-2188.1182, 2596.9348, 0.0),
        },
        label = 'Pântano', -- nome mostrado no painel do pescador
        radius = 200.0,
        minLevel = 2,
        waitTime = { min = 12, max = 25 },
        includeOutside = true,
        message = { enter = 'Você entrou em um pântano.', exit = 'Você deixou o pântano.' },
        fishList = { 'piranha' }
    },
}

-- Outside of all zones
Config.outside = {
    waitTime = { min = 10, max = 25 },

    ---@type string[]
    fishList = {
        'trout', 'anchovy', 'haddock', 'salmon'
    }
}

-- Painel do pescador (substitui o menu do ox_lib)
Config.shop = {
    enabled = true,          -- false = volta pro menu antigo do ox_lib
    title = 'Corporação Marítima',
    outsideLabel = 'Qualquer água', -- nome da "zona" de fora no painel
    maxAmount = 100,         -- quantidade máxima por compra
}

Config.ped = {
    buyAccount = 'money',
    sellAccount = 'money',
    -- blip = {
    --     name = 'SeaTrade Corporation',
    --     sprite = 356,
    --     color = 74,
    --     scale = 0.75
    -- },

    -- TALK NPCS
    model = 's_m_m_cntrybar_01',
    name = 'João',
    tag = 'PESCADOR',
    startMSG = 'Vamos pescar?',
    message = "👋 Olá, me chamo 😃**João Luiz**, mas pode me chamar de **Tarzan da Pescaria**.  \nVou te explicar como 🎣 pescar.  \nPara isso, você vai precisar de uma 🪝 vara de pesca e isca de pesca. Depois, você pode ir até um lago ou ao mar e começar a pescar usando a vara de pesca. 🌊  \nLembrando que quanto mais experiência você adquirir, poderá pescar em áreas específicas, pegando peixes melhores e podendo comprar varas de pesca melhores para essa pescaria.  \nEntão, agora que você já sabe como faz, boa pescaria para você! 🎣🐟",

    ---@type vector4[]
    locations = {
        vector4(-2081.3831, 2614.3223, 3.0840, 112.7910),
        vector4(-1492.3639, -939.2579, 10.2140, 144.0305)
    }
}

Config.renting = {
    model = 's_m_m_dockwork_01', -- The ped model
    account = 'money',
    boats = {
        { model = `speeder`, price = 500, image = 'https://i.postimg.cc/mDSqWj4P/164px-Speeder.webp' },
        { model = `dinghy`, price = 750, image = 'https://i.postimg.cc/ZKzjZgj0/164px-Dinghy2.webp'  },
        { model = `tug`, price = 1250, image = 'https://i.postimg.cc/jq7vpKHG/164px-Tug.webp' }
    },
    blip = {
        name = 'Aluguel de Barcos',
        sprite = 410,
        color = 74,
        scale = 0.75
    },
    returnDivider = 5, -- Players can return it and get some cash back
    returnRadius = 30.0, -- The save radius

    -- TALK NPCS
    model = 's_m_m_dockwork_01',
    name = 'Trakinas',
    tag = 'PESCADOR APOSENTADO',
    startMSG = 'Tá precisando de um barco?',
    message = "👋 Olá, me chamo 😃**Alessandro Azevedo**, mas pode me chamar de **Trakinas**.  \nAqui você pode alugar barcos para pescar. Vai querer algum?",


    ---@type { coords: vector4, spawn: vector4 }[]
    locations = {
        { coords = vector4(-1434.4818, -1512.2745, 2.1486, 25.8666), spawn = vector4(-1494.4496, -1537.6943, 2.3942, 115.6015) }
    }
}