---@type table<string, number>
local levels = {}

-- MySQL.ready(function()
--     local data = MySQL.query.await('SELECT * FROM lunar_fishing')

--     for _, entry in ipairs(data) do
--         levels[entry.user_identifier] = entry.xp
--     end
-- end)

-- local function save()
--     local query = 'UPDATE lunar_fishing SET xp = ? WHERE user_identifier = ?'
--     local parameters = {}
--     local size = 0

--     for identifier, level in pairs(levels) do
--         size += 1
--         parameters[size] = {
--             level,
--             identifier
--         }
--     end

--     if size > 0 then
--         print('Saving player progress.')
--         MySQL.prepare.await(query, parameters)
--     end
-- end

-- lib.cron.new('*/10 * * * *', save)
-- AddEventHandler('txAdmin:events:serverShuttingDown', save)

AddEventHandler('txAdmin:events:scheduledRestart', function(eventData)
    if eventData.secondsRemaining ~= 60 then return end

	-- save()
end)

AddEventHandler('onResourceStop', function(resource)
	if resource == cache.resource then
		-- save()
	end
end)


-- local function createPlayer(identifier)
--     levels[identifier] = 1.0
--     MySQL.insert.await('INSERT INTO lunar_fishing (user_identifier, xp) VALUES(?, ?)', { identifier, levels[identifier] })
-- end

---@param source integer
---@return number xp
function GetPlayerFishingXp(source)
    local skills = exports["cw-rep"]:fetchSkills(source)

    return tonumber(skills and skills.fishing) or 0
end

--- Nível "quebrado" (ex.: 1.4 = nível 1, 40% do caminho pro 2), que é o formato que o client usa.
---@param xp number
---@return number
function FishingLevelFromXp(xp)
    local level, from, to = Config.getFishingLevel(xp)

    if not to then return level end

    return level + (xp - from) / (to - from)
end

---@param source integer
---@return integer
function GetPlayerFishingLevel(source)
    return (Config.getFishingLevel(GetPlayerFishingXp(source)))
end

lib.callback.register('lunar_fishing:getLevel', function(source)
    local player = Framework.getPlayerFromId(source)

    if not player then return end

    -- O cw-rep guarda XP; o nível sai da mesma tabela dele (Config.getFishingLevel)
    return FishingLevelFromXp(GetPlayerFishingXp(source))
end)

---@param player Player
---@param amount number
-- function AddPlayerLevel(player, amount)
--     local identifier = player:getIdentifier()
--     local level = math.floor(levels[identifier])

--     levels[identifier] += amount

--     if math.floor(levels[identifier]) - level > 0 then
--         TriggerClientEvent('lunar_fishing:showNotification', player.source, locale('unlocked_level'), 'success')
--     end

--     TriggerClientEvent('lunar_fishing:updateLevel', player.source, levels[identifier])
-- end

---@param player Player
-- function GetPlayerLevel(player)
--     return levels[player:getIdentifier()]
-- end