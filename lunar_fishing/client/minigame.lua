-- Minigame de pesca estilo Stardew Valley (substitui o lib.skillCheck do ox_lib)

---@type table?
local minigamePromise

local skillWeights = { easy = 1, medium = 2, hard = 3 }

--- Se o peixe não tiver `minigame` no config, calcula a dificuldade pelo skillcheck antigo.
---@param fish Fish
local function fallbackSettings(fish)
    local total = 0

    for _, level in ipairs(fish.skillcheck or {}) do
        total += skillWeights[level] or 2
    end

    return { difficulty = math.min(95, 10 + total * 8), behavior = 'mixed' }
end

local function sendInput(state)
    SendNUIMessage({ action = 'input', holding = state })
end

local holdControls = { 24, 38, 22 } -- botão esquerdo do mouse, E, espaço
local blockedControls = { 24, 25, 22, 37, 38, 44, 140, 141, 142, 257, 263, 264 }

---@param fish Fish
---@param rodName string?
---@return boolean success
function StartFishingMinigame(fish, rodName)
    if minigamePromise then return false end

    local cfg = Config.minigame or {}
    local settings = fish.minigame or fallbackSettings(fish)
    local barSize = (cfg.barSize and rodName and cfg.barSize[rodName]) or cfg.defaultBarSize or 96

    minigamePromise = promise.new()
    local current = minigamePromise

    SendNUIMessage({
        action = 'start',
        difficulty = settings.difficulty,
        behavior = settings.behavior or 'mixed',
        color = settings.color,
        barSize = barSize,
        scale = cfg.scale,
        posX = cfg.position and cfg.position.x,
        posY = cfg.position and cfg.position.y,
        startProgress = cfg.startProgress,
        gainRate = cfg.gainRate,
        lossRate = cfg.lossRate,
        sound = cfg.sound,
        hint = cfg.hint,
    })

    CreateThread(function()
        local holding = false

        while current.state == 0 do
            for i = 1, #blockedControls do
                DisableControlAction(0, blockedControls[i], true)
            end

            local pressed = false
            for i = 1, #holdControls do
                if IsDisabledControlPressed(0, holdControls[i]) then
                    pressed = true
                    break
                end
            end

            if pressed ~= holding then
                holding = pressed
                sendInput(holding)
            end

            if IsEntityDead(cache.ped) or IsPedRagdoll(cache.ped) or IsPedSwimming(cache.ped) then
                SendNUIMessage({ action = 'stop' })
                current:resolve(false)
            end

            Wait(0)
        end
    end)

    local success = Citizen.Await(current)
    minigamePromise = nil

    return success == true
end

RegisterNUICallback('minigameEnd', function(data, cb)
    cb(1)

    if minigamePromise and minigamePromise.state == 0 then
        minigamePromise:resolve(data and data.success == true)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    if minigamePromise and minigamePromise.state == 0 then
        minigamePromise:resolve(false)
    end
end)
