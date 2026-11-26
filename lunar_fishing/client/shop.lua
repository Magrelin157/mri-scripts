-- Painel do pescador (NUI) no lugar do menu de contexto do ox_lib

local isOpen = false

local accountLabels = { money = 'Dinheiro na mão', cash = 'Dinheiro na mão', bank = 'Saldo no banco' }

local function zonesPayload(level)
    local zones = {
        {
            label = Config.shop.outsideLabel or 'Qualquer água',
            minLevel = 0,
            unlocked = true,
            fish = Config.outside.fishList,
        }
    }

    for _, zone in ipairs(Config.fishingZones) do
        local fish = {}

        for _, name in ipairs(zone.fishList) do fish[#fish + 1] = name end

        zones[#zones + 1] = {
            label = zone.label or (zone.blip and zone.blip.name) or '?',
            minLevel = zone.minLevel,
            unlocked = level >= zone.minLevel,
            fish = fish,
            withOutside = zone.includeOutside == true,
        }
    end

    table.sort(zones, function(a, b) return a.minLevel < b.minLevel end)

    return zones
end

local function itemList(listType, level)
    local list = {}

    for index, item in ipairs(Config[listType]) do
        list[#list + 1] = {
            type = listType,
            index = index,
            name = item.name,
            label = Utils.getItemLabel(item.name),
            image = GetInventoryIcon(item.name),
            price = item.price,
            minLevel = item.minLevel,
            locked = level < item.minLevel,
            breakChance = item.breakChance,
            waitDivisor = item.waitDivisor,
            barSize = listType == 'fishingRods' and Config.minigame and Config.minigame.barSize
                and Config.minigame.barSize[item.name] or nil,
        }
    end

    return list
end

local function fishList(counts)
    local list = {}

    for name, fish in pairs(Config.fish) do
        local min = type(fish.price) == 'number' and fish.price or fish.price.min
        local max = type(fish.price) == 'number' and fish.price or fish.price.max

        list[#list + 1] = {
            name = name,
            label = Utils.getItemLabel(name),
            image = GetInventoryIcon(name),
            min = min,
            max = max,
            count = counts and counts[name] or 0,
        }
    end

    table.sort(list, function(a, b) return a.min < b.min end)

    return list
end

local function levelPayload(xp)
    local level, from, to = Config.getFishingLevel(xp)

    return { level = level, xp = xp, from = from, to = to }
end

function OpenFishingShop()
    if isOpen then return end

    local data = lib.callback.await('lunar_fishing:shopData', false)

    if not data then return end

    local level = levelPayload(data.xp)
    local barSizes = Config.minigame and Config.minigame.barSize or {}

    isOpen = true
    SetNuiFocus(true, true)

    SendNUIMessage({
        action = 'shopOpen',
        title = Config.shop.title or locale('fisherman'),
        npc = { name = Config.ped.name, tag = Config.ped.tag },
        account = accountLabels[Config.ped.buyAccount] or Config.ped.buyAccount,
        money = data.money,
        level = level,
        rods = itemList('fishingRods', level.level),
        baits = itemList('baits', level.level),
        fish = fishList(data.fish),
        zones = zonesPayload(level.level),
        maxAmount = Config.shop.maxAmount or 100,
        barSizes = barSizes,
    })
end

local function close()
    if not isOpen then return end

    isOpen = false
    SetNuiFocus(false, false)
end

RegisterNUICallback('shopClose', function(_, cb)
    cb(1)
    close()
end)

RegisterNUICallback('shopBuy', function(data, cb)
    local result = lib.callback.await('lunar_fishing:shopBuy', false, {
        type = data.type,
        index = data.index,
        amount = data.amount,
    }) or { ok = false }

    -- O aviso aparece dentro do próprio painel (sem notificação do ox_lib)
    cb(result)
end)

RegisterNUICallback('shopSell', function(data, cb)
    local result = lib.callback.await('lunar_fishing:shopSell', false, data.items or {}) or { ok = false }

    -- O aviso aparece dentro do próprio painel (sem notificação do ox_lib)
    cb(result)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and isOpen then
        SetNuiFocus(false, false)
    end
end)
