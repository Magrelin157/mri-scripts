-- Painel do pescador: dados, compra e venda (tudo validado aqui no servidor)

local busy = {}

---@param amount any
---@return integer?
local function validAmount(amount)
    amount = tonumber(amount)

    if not amount or amount ~= amount then return end

    amount = math.floor(amount)

    if amount < 1 or amount > (Config.shop.maxAmount or 100) then return end

    return amount
end

---@param fish Fish
local function rollPrice(fish)
    if type(fish.price) == 'number' then return fish.price end

    return math.random(fish.price.min, fish.price.max)
end

---@param player table
local function fishCounts(player)
    local counts = {}

    for fishName in pairs(Config.fish) do
        counts[fishName] = player:getItemCount(fishName)
    end

    return counts
end

lib.callback.register('lunar_fishing:shopData', function(source)
    local player = Framework.getPlayerFromId(source)

    if not player then return end

    return {
        xp = GetPlayerFishingXp(source),
        money = player:getAccountMoney(Config.ped.buyAccount),
        fish = fishCounts(player),
    }
end)

---@param data { type: string, index: integer, amount: integer }
lib.callback.register('lunar_fishing:shopBuy', function(source, data)
    if busy[source] or type(data) ~= 'table' then return { ok = false } end

    local listType = data.type
    if listType ~= 'fishingRods' and listType ~= 'baits' then return { ok = false } end

    local item = Config[listType][tonumber(data.index)]
    local amount = validAmount(data.amount)
    local player = Framework.getPlayerFromId(source)

    if not item or not amount or not player then return { ok = false } end

    if GetPlayerFishingLevel(source) < item.minLevel then
        return { ok = false, reason = 'level' }
    end

    local price = item.price * amount

    if player:getAccountMoney(Config.ped.buyAccount) < price then
        return { ok = false, reason = 'money' }
    end

    if not player:canCarryItem(item.name, amount) then
        return { ok = false, reason = 'weight' }
    end

    busy[source] = true
    player:removeAccountMoney(Config.ped.buyAccount, price)
    player:addItem(item.name, amount)
    busy[source] = nil

    Utils.logToDiscord(source, player, ('Comprou %sx %s por R$ %s.'):format(amount, item.name, price))

    return { ok = true, spent = price, money = player:getAccountMoney(Config.ped.buyAccount) }
end)

---@param items table<string, integer> peixe -> quantidade
lib.callback.register('lunar_fishing:shopSell', function(source, items)
    if busy[source] or type(items) ~= 'table' then return { ok = false } end

    local player = Framework.getPlayerFromId(source)
    if not player then return { ok = false } end

    busy[source] = true

    local total, sold = 0, 0

    for fishName, amount in pairs(items) do
        local fish = Config.fish[fishName]
        local count = fish and player:getItemCount(fishName) or 0
        amount = math.min(tonumber(amount) and math.floor(amount) or 0, count, 1000)

        if fish and amount > 0 then
            local earned = 0

            for _ = 1, amount do
                earned += rollPrice(fish)
            end

            player:removeItem(fishName, amount)
            total += earned
            sold += amount
        end
    end

    if total > 0 then
        player:addAccountMoney(Config.ped.sellAccount, total)
        Utils.logToDiscord(source, player, ('Vendeu %s peixe(s) por R$ %s.'):format(sold, total))
    end

    busy[source] = nil

    return {
        ok = sold > 0,
        earned = total,
        sold = sold,
        money = player:getAccountMoney(Config.ped.buyAccount),
        fish = fishCounts(player),
    }
end)

AddEventHandler('playerDropped', function()
    busy[source] = nil
end)
