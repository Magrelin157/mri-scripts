-- Catálogo (painel) da concessionária: substitui os carros expostos.
-- Aperta E no ponto da loja -> abre o painel, o veículo aparece no ponto de prévia
-- e a compra/financiamento/test drive usam os mesmos eventos do qbx_vehicleshop.

local config = require 'config.client'
local sharedConfig = require 'config.shared'

local VEHICLES = lib.callback.await('qbx_vehicleshop:server:getVehicles', false) or {}

RegisterNetEvent('qbx_core:client:onVehicleUpdate', function(model, vehicle)
    VEHICLES[model] = vehicle or nil
end)

RegisterNetEvent('qbx_vehicleshop:client:refreshVehicles', function()
    VEHICLES = lib.callback.await('qbx_vehicleshop:server:getVehicles', false) or VEHICLES
end)

-- Cores do painel (RGB). A primeira ("Original") mantém a cor de fábrica.
local COLORS = {
    { label = 'Original', rgb = false },
    { label = 'Preto', rgb = { 8, 8, 10 } },
    { label = 'Branco', rgb = { 235, 235, 235 } },
    { label = 'Prata', rgb = { 150, 155, 160 } },
    { label = 'Grafite', rgb = { 55, 58, 62 } },
    { label = 'Vermelho', rgb = { 170, 10, 15 } },
    { label = 'Laranja', rgb = { 220, 90, 10 } },
    { label = 'Amarelo', rgb = { 230, 190, 20 } },
    { label = 'Verde', rgb = { 20, 140, 50 } },
    { label = 'Ciano', rgb = { 20, 180, 190 } },
    { label = 'Azul', rgb = { 20, 70, 180 } },
    { label = 'Azul escuro', rgb = { 10, 20, 80 } },
    { label = 'Roxo', rgb = { 90, 20, 140 } },
    { label = 'Rosa', rgb = { 200, 40, 120 } },
}

local isOpen = false
local currentShop
local previewVeh
local previewModel
local previewToken = 0
local previewColor = false
local cam
local camAngle = 0.0
local camZoom = 1.0
local camPreset = 1
local CAM_PRESETS = {
    { angle = 40.0, height = 0.30 },   -- frente 3/4
    { angle = 90.0, height = 0.15 },   -- frente
    { angle = 0.0, height = 0.20 },    -- lateral
    { angle = -140.0, height = 0.30 }, -- traseira 3/4
    { angle = 40.0, height = 1.10 },   -- de cima
}

local function notify(msg, kind)
    exports.qbx_core:Notify(msg, kind or 'inform')
end

---@param shopName string
---@return { coords: vector3, preview: vector4 }?
local function getCatalog(shopName)
    local shop = sharedConfig.shops[shopName]
    if not shop then return end
    local catalog = shop.catalog or {}
    return {
        coords = catalog.coords or shop.blip.coords,
        preview = catalog.preview,
    }
end

--- Ícone (sem foto) a partir da categoria
local function iconFor(category)
    if category == 'motorcycles' then return 'moto' end
    if category == 'cycles' then return 'bike' end
    if category == 'boats' then return 'boat' end
    if category == 'helicopters' then return 'heli' end
    if category == 'planes' then return 'plane' end
    if category == 'vans' or category == 'commercial' or category == 'industrial' or category == 'utility' then return 'van' end
    if category == 'suvs' or category == 'offroad' then return 'suv' end
    return 'car'
end

--- Desempenho do modelo (não precisa carregar o modelo)
---@param hash integer
local function getStats(hash)
    local speed = GetVehicleModelEstimatedMaxSpeed(hash) or 0.0
    local accel = GetVehicleModelAcceleration(hash) or 0.0
    local brake = GetVehicleModelMaxBraking(hash) or 0.0
    local traction = GetVehicleModelMaxTraction(hash) or 0.0

    local s = math.min(1.0, speed / 70.0)
    local a = math.min(1.0, accel / 0.45)
    local b = math.min(1.0, brake / 1.6)
    local t = math.min(1.0, traction / 3.2)

    local score = math.floor((s * 0.35 + a * 0.30 + b * 0.15 + t * 0.20) * 1000)
    local class
    if score <= 0 then class = '-'
    elseif score < 400 then class = 'D'
    elseif score < 500 then class = 'C'
    elseif score < 600 then class = 'B'
    elseif score < 700 then class = 'A'
    elseif score < 800 then class = 'S1'
    else class = 'S2' end

    return {
        score = score,
        class = class,
        speed = math.floor(speed * 3.6),
        bars = { speed = s, accel = a, brake = b, traction = t },
        seats = GetVehicleModelNumberOfSeats(hash),
    }
end

---@param shopName string
local function buildData(shopName)
    local shop = sharedConfig.shops[shopName]
    local menu = GetVehiclesFromServer()

    local categories = {}
    for id, label in pairs(shop.categories) do
        categories[#categories + 1] = { id = id, label = label }
    end
    table.sort(categories, function(a, b) return a.label:upper() < b.label:upper() end)

    local vehicles, seen = {}, {}
    for i = 1, menu.count do
        local v = menu.vehicles[i]
        local model = v.args and v.args.toVehicle
        if model and v.shopType == shopName and shop.categories[v.category] and not seen[model] then
            seen[model] = true
            local data = VEHICLES[model] or {}
            local hash = joaat(model)
            vehicles[#vehicles + 1] = {
                model = model,
                name = data.name or model,
                brand = data.brand or '',
                price = data.price or 0,
                category = v.category,
                icon = iconFor(v.category),
                inGame = IsModelInCdimage(hash),
                stats = getStats(hash),
            }
        end
    end
    table.sort(vehicles, function(a, b)
        if a.price ~= b.price then return a.price < b.price end
        return a.name:upper() < b.name:upper()
    end)

    return categories, vehicles
end

local function getMoney()
    local money = QBX.PlayerData and QBX.PlayerData.money or {}
    return { cash = money.cash or 0, bank = money.bank or 0 }
end

--------------------------------------------------------------------------------
-- Câmera e prévia
--------------------------------------------------------------------------------

local function updateCam()
    if not cam or not previewVeh or not DoesEntityExist(previewVeh) then return end

    local min, max = GetModelDimensions(GetEntityModel(previewVeh))
    local size = #(max - min)
    local preset = CAM_PRESETS[camPreset]
    local dist = (size * 0.85 + 1.2) * camZoom
    local center = GetEntityCoords(previewVeh)
    local heading = GetEntityHeading(previewVeh)
    local ang = math.rad(heading + 90.0 + preset.angle + camAngle)

    SetCamCoord(cam,
        center.x + math.cos(ang) * dist,
        center.y + math.sin(ang) * dist,
        center.z + 0.25 + size * preset.height * 0.5)
    PointCamAtCoord(cam, center.x, center.y, center.z + (max.z + min.z) * 0.25)
end

local function createCam()
    if cam then return end
    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 45.0, false, 0)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 700, true, true)
end

local function destroyCam()
    if not cam then return end
    RenderScriptCams(false, true, 700, true, true)
    DestroyCam(cam, false)
    cam = nil
end

local function deletePreview()
    if previewVeh and DoesEntityExist(previewVeh) then
        DeleteEntity(previewVeh)
    end
    previewVeh = nil
end

local function applyColor()
    if not previewVeh or not DoesEntityExist(previewVeh) then return end
    if previewColor then
        local c = previewColor
        SetVehicleCustomPrimaryColour(previewVeh, c[1], c[2], c[3])
        SetVehicleCustomSecondaryColour(previewVeh, c[1], c[2], c[3])
    else
        ClearVehicleCustomPrimaryColour(previewVeh)
        ClearVehicleCustomSecondaryColour(previewVeh)
    end
end

--------------------------------------------------------------------------------
-- Clone do personagem ao lado do veículo (só no seu jogo)
--------------------------------------------------------------------------------

-- Animações que o clone faz (sorteia uma cada vez que abre o catálogo)
local PED_SCENARIOS = {
    'WORLD_HUMAN_STAND_MOBILE',     -- mexendo no celular
    'WORLD_HUMAN_STAND_IMPATIENT',  -- esperando, braços cruzados
    'WORLD_HUMAN_HANG_OUT_STREET',  -- parado, olhando
    'WORLD_HUMAN_AA_COFFEE',        -- tomando café
}

local showcasePed
local showcaseScenario

-- Props que as animações criam (copo, celular...). Usado para limpar sobras no chão.
local SCENARIO_PROPS = {
    [`p_amb_coffeecup_01`] = true,
    [`p_ing_coffeecup_01`] = true,
    [`p_ing_coffeecup_02`] = true,
    [`prop_fib_coffee`] = true,
    [`prop_npc_phone`] = true,
    [`prop_npc_phone_02`] = true,
    [`prop_amb_phone`] = true,
    [`p_amb_phone_01`] = true,
}

--- Apaga os objetos presos ao clone antes de reiniciar/apagar a animação
--- (senão o copo/celular cai no chão a cada troca de veículo)
local function deleteShowcaseProps()
    if not showcasePed or not DoesEntityExist(showcasePed) then return end
    local pedCoords = GetEntityCoords(showcasePed)
    local objects = GetGamePool('CObject')
    for i = 1, #objects do
        local obj = objects[i]
        if DoesEntityExist(obj) and not NetworkGetEntityIsNetworked(obj) then
            local attached = IsEntityAttachedToEntity(obj, showcasePed)
            local leftover = SCENARIO_PROPS[GetEntityModel(obj)] and #(GetEntityCoords(obj) - pedCoords) < 6.0
            if attached or leftover then
                DetachEntity(obj, false, false)
                SetEntityAsMissionEntity(obj, true, true)
                DeleteObject(obj)
            end
        end
    end
end

local function deleteShowcasePed()
    if showcasePed and DoesEntityExist(showcasePed) then
        deleteShowcaseProps()
        DeleteEntity(showcasePed)
    end
    showcasePed = nil
end

local function placeShowcasePed()
    local shop = currentShop and sharedConfig.shops[currentShop]
    if not shop or (shop.catalog and shop.catalog.ped == false) or not previewVeh or not DoesEntityExist(previewVeh) then
        return deleteShowcasePed()
    end

    -- ao lado da porta do motorista do outro lado (direita do veículo), virado para ele
    local min, max = GetModelDimensions(GetEntityModel(previewVeh))
    local pos = GetOffsetFromEntityInWorldCoords(previewVeh, max.x + 0.85, max.y * 0.25, 0.0)
    local found, groundZ = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 1.5, false)
    if not found then return deleteShowcasePed() end

    if not showcasePed or not DoesEntityExist(showcasePed) then
        showcasePed = ClonePed(cache.ped, false, false, true)
        SetEntityInvincible(showcasePed, true)
        SetBlockingOfNonTemporaryEvents(showcasePed, true)
        SetPedCanRagdoll(showcasePed, false)
        SetPedConfigFlag(showcasePed, 17, true) -- não reage a nada
    end

    local center = GetEntityCoords(previewVeh)
    FreezeEntityPosition(showcasePed, false)
    deleteShowcaseProps()
    ClearPedTasksImmediately(showcasePed)
    SetEntityCoords(showcasePed, pos.x, pos.y, groundZ, false, false, false, false)
    SetEntityHeading(showcasePed, GetHeadingFromVector_2d(center.x - pos.x, center.y - pos.y))
    FreezeEntityPosition(showcasePed, true)
    TaskStartScenarioInPlace(showcasePed, showcaseScenario or PED_SCENARIOS[1], 0, true)
end

---@param model string
---@return boolean ok
local function setPreview(model)
    previewToken += 1
    local token = previewToken
    previewModel = model

    local catalog = getCatalog(currentShop)
    local hash = joaat(model)

    if not catalog or not catalog.preview or not IsModelInCdimage(hash) then
        deletePreview()
        deleteShowcasePed()
        return false
    end

    local loaded = pcall(lib.requestModel, hash, config.requestModelTimeout or 10000)
    if not loaded or token ~= previewToken or not isOpen then
        SetModelAsNoLongerNeeded(hash)
        return false
    end

    deletePreview()

    local p = catalog.preview
    local veh = CreateVehicle(hash, p.x, p.y, p.z, p.w, false, false)
    SetModelAsNoLongerNeeded(hash)

    SetVehicleOnGroundProperly(veh)
    FreezeEntityPosition(veh, true)
    SetEntityInvincible(veh, true)
    SetVehicleDoorsLocked(veh, 2)
    SetVehicleDirtLevel(veh, 0.0)
    SetVehicleNumberPlateText(veh, 'VITRINE')
    SetVehicleLights(veh, 2)
    Entity(veh).state.isVehicleShopEntity = true

    previewVeh = veh
    applyColor()
    placeShowcasePed()
    updateCam()
    return true
end

--------------------------------------------------------------------------------
-- Abrir / fechar
--------------------------------------------------------------------------------

local function closeCatalog()
    if not isOpen then return end
    isOpen = false
    previewToken += 1
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    deletePreview()
    deleteShowcasePed()
    destroyCam()
    previewModel = nil
    currentShop = nil
end

---@param shopName string
local function openCatalog(shopName)
    if isOpen then return end

    local shop = sharedConfig.shops[shopName]
    if not shop then return end

    if shop.job and QBX.PlayerData.job.name ~= shop.job then
        return notify('Apenas funcionários podem usar este catálogo', 'error')
    end

    local catalog = getCatalog(shopName)
    if not catalog or not catalog.preview then
        return notify(('Configure catalog.preview da loja "%s" no config/shared.lua'):format(shopName), 'error')
    end

    local categories, vehicles = buildData(shopName)

    isOpen = true
    currentShop = shopName
    previewColor = false
    showcaseScenario = PED_SCENARIOS[math.random(#PED_SCENARIOS)]
    camAngle, camZoom, camPreset = 0.0, 1.0, 1

    lib.hideTextUI()
    createCam()

    SendNUIMessage({
        action = 'open',
        shop = {
            name = shopName,
            label = shop.blip and shop.blip.label or 'Concessionária',
            managed = shop.type == 'managed',
        },
        categories = categories,
        vehicles = vehicles,
        colors = COLORS,
        money = getMoney(),
        options = {
            buy = shop.type == 'managed' or sharedConfig.enableFreeUseBuy,
            testDrive = sharedConfig.enableTestDrive,
            finance = sharedConfig.finance.enable,
            minimumDown = sharedConfig.finance.minimumDown,
            maximumPayments = sharedConfig.finance.maximumPayments,
        },
    })
    SetNuiFocus(true, true)

    CreateThread(function()
        while isOpen do
            HideHudAndRadarThisFrame()
            SetEntityLocallyInvisible(cache.ped) -- o clone aparece no lugar
            Wait(0)
        end
    end)
end

exports('OpenCatalog', openCatalog)

--------------------------------------------------------------------------------
-- NUI callbacks
--------------------------------------------------------------------------------

RegisterNUICallback('close', function(_, cb)
    closeCatalog()
    cb(1)
end)

RegisterNUICallback('select', function(data, cb)
    if not isOpen or type(data.model) ~= 'string' then return cb({ ok = false }) end
    local model = data.model
    local ok = setPreview(model)
    local stock = lib.callback.await('qbx_vehicleshop:server:checkstock', false, model)
    cb({ ok = ok, model = model, stock = stock })
end)

RegisterNUICallback('color', function(data, cb)
    local color = COLORS[tonumber(data.index) or 1]
    previewColor = color and color.rgb or false
    applyColor()
    cb(1)
end)

RegisterNUICallback('rotate', function(data, cb)
    camAngle = camAngle - (tonumber(data.dx) or 0) * 0.35
    updateCam()
    cb(1)
end)

RegisterNUICallback('zoom', function(data, cb)
    camZoom = math.max(0.55, math.min(1.7, camZoom + (tonumber(data.delta) or 0) * 0.08))
    updateCam()
    cb(1)
end)

RegisterNUICallback('camera', function(_, cb)
    camPreset = camPreset % #CAM_PRESETS + 1
    camAngle = 0.0
    updateCam()
    cb(camPreset)
end)

--- Ações: fecha o painel e usa os eventos originais do qbx_vehicleshop
RegisterNUICallback('action', function(data, cb)
    cb(1)
    if not isOpen then return end

    local model = data.model
    if type(model) ~= 'string' then return end

    local color = previewColor or nil
    local playerId = tonumber(data.playerId)
    local down = tonumber(data.downPayment)
    local payments = tonumber(data.payments)
    local managed = sharedConfig.shops[currentShop].type == 'managed'

    closeCatalog()

    if data.type == 'buy' then
        if managed then
            if not playerId then return notify('Informe o ID do comprador', 'error') end
            TriggerServerEvent('qbx_vehicleshop:server:sellShowroomVehicle', model, playerId, color)
        else
            TriggerServerEvent('qbx_vehicleshop:server:buyShowroomVehicle', model, color)
        end
    elseif data.type == 'finance' then
        if not down or not payments then return end
        if managed then
            if not playerId then return notify('Informe o ID do comprador', 'error') end
            TriggerServerEvent('qbx_vehicleshop:server:sellfinanceVehicle', down, payments, model, playerId, color)
        else
            TriggerServerEvent('qbx_vehicleshop:server:financeVehicle', down, payments, model, color)
        end
    elseif data.type == 'test' then
        if managed then
            if not playerId then return notify('Informe o ID do cliente', 'error') end
            TriggerServerEvent('qbx_vehicleshop:server:customTestDrive', model, playerId, color)
        else
            TriggerServerEvent('qbx_vehicleshop:server:testDrive', model, color)
        end
    end
end)

--------------------------------------------------------------------------------
-- Ponto de abertura (E) em cada loja
--------------------------------------------------------------------------------

local function canUse(shop)
    return not shop.job or (QBX.PlayerData.job and QBX.PlayerData.job.name == shop.job)
end

-- Interação pelo mri_Qinteract (se estiver no servidor)
local interactIds = {}

local function registerInteract()
    for i = 1, #interactIds do
        pcall(exports.mri_Qinteract.removeCoords, exports.mri_Qinteract, interactIds[i])
    end
    interactIds = {}

    for shopName, shop in pairs(sharedConfig.shops) do
        local catalog = getCatalog(shopName)
        if catalog and catalog.coords then
            local ok, id = pcall(exports.mri_Qinteract.addCoords, exports.mri_Qinteract, catalog.coords, {
                {
                    name = 'qbx_vehicleshop_catalog',
                    label = 'Catálogo de veículos',
                    icon = 'car',
                    distance = 2.0,
                    groups = shop.job,
                    canInteract = function() return not isOpen and not cache.vehicle end,
                    onSelect = function() openCatalog(shopName) end,
                },
            })
            if ok and id then interactIds[#interactIds + 1] = id end
        end
    end
end

AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'mri_Qinteract' then
        Wait(500)
        registerInteract()
    end
end)

CreateThread(function()
    if GetResourceState('mri_Qinteract') ~= 'missing' then
        local timeout = GetGameTimer() + 15000
        while GetResourceState('mri_Qinteract') ~= 'started' and GetGameTimer() < timeout do Wait(250) end
        if GetResourceState('mri_Qinteract') == 'started' then
            registerInteract()
            return
        end
    end

    for shopName, shop in pairs(sharedConfig.shops) do
        local catalog = getCatalog(shopName)
        if catalog and catalog.coords then
            local coords = catalog.coords

            if config.useTarget then
                exports.ox_target:addSphereZone({
                    coords = coords,
                    radius = 1.5,
                    debug = config.debugPoly,
                    options = {
                        {
                            name = 'qbx_vehicleshop_catalog',
                            icon = 'fas fa-car',
                            label = 'Catálogo de veículos',
                            groups = shop.job,
                            onSelect = function() openCatalog(shopName) end,
                        }
                    }
                })
            else
                local showing = false
                lib.points.new({
                    coords = coords,
                    distance = 12.0,
                    nearby = function(self)
                        if isOpen or not canUse(shop) then
                            if showing then lib.hideTextUI() showing = false end
                            return
                        end

                        DrawMarker(36, coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                            0.7, 0.7, 0.7, 22, 86, 245, 170, true, true, 2, false, nil, nil, false)

                        if self.currentDistance < 1.6 then
                            if not showing then
                                lib.showTextUI('[E] - Catálogo de veículos', { icon = 'car' })
                                showing = true
                            end
                            if IsControlJustPressed(0, 38) and not cache.vehicle then
                                lib.hideTextUI()
                                showing = false
                                openCatalog(shopName)
                            end
                        elseif showing then
                            lib.hideTextUI()
                            showing = false
                        end
                    end,
                    onExit = function()
                        if showing then lib.hideTextUI() showing = false end
                    end,
                })
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end
    if isOpen then
        SetNuiFocus(false, false)
        deletePreview()
        deleteShowcasePed()
        destroyCam()
    end
end)

--------------------------------------------------------------------------------
-- Sem carros e sem pedestres de NPC dentro das lojas
--------------------------------------------------------------------------------

local shopAreas = {}

for shopName, shop in pairs(sharedConfig.shops) do
    local shape = shop.zone and shop.zone.shape
    if shape and #shape > 0 then
        local minX, minY, minZ = math.huge, math.huge, math.huge
        local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
        for i = 1, #shape do
            local p = shape[i]
            minX, minY, minZ = math.min(minX, p.x), math.min(minY, p.y), math.min(minZ, p.z)
            maxX, maxY, maxZ = math.max(maxX, p.x), math.max(maxY, p.y), math.max(maxZ, p.z)
        end
        shopAreas[#shopAreas + 1] = {
            name = shopName,
            min = vec3(minX - 2.0, minY - 2.0, minZ - 6.0),
            max = vec3(maxX + 2.0, maxY + 2.0, maxZ + 8.0),
            poly = lib.zones.poly({ points = shape, thickness = 14 }),
            center = vec3((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2),
        }
    end
end

---@param area table
local function blockGenerators(area)
    SetAllVehicleGeneratorsActiveInArea(area.min.x, area.min.y, area.min.z, area.max.x, area.max.y, area.max.z, false, false)
    RemoveVehiclesFromGeneratorsInArea(area.min.x, area.min.y, area.min.z, area.max.x, area.max.y, area.max.z, 0)
end

---@param ped integer
local function isNpcPed(ped)
    if ped == cache.ped or IsPedAPlayer(ped) then return false end
    if IsEntityAMissionEntity(ped) then return false end -- NPCs de script (vendedor, emprego etc.)
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 then return false end -- quem está dentro de veículo fica (o veículo é tratado à parte)
    return true
end

---@param veh integer
local function isNpcVehicle(veh)
    if veh == previewVeh then return false end
    if Entity(veh).state.isVehicleShopEntity or Entity(veh).state.vehicleid then return false end
    if IsEntityAMissionEntity(veh) then return false end -- comprados / test drive / spawn de script
    local driver = GetPedInVehicleSeat(veh, -1)
    if driver ~= 0 and IsPedAPlayer(driver) then return false end
    for seat = 0, GetVehicleMaxNumberOfPassengers(veh) - 1 do
        local ped = GetPedInVehicleSeat(veh, seat)
        if ped ~= 0 and IsPedAPlayer(ped) then return false end
    end
    return true
end

---@param ped integer
local function removePed(ped)
    if NetworkGetEntityIsNetworked(ped) and not NetworkHasControlOfEntity(ped) then
        NetworkRequestControlOfEntity(ped)
        local timeout = GetGameTimer() + 500
        while not NetworkHasControlOfEntity(ped) and GetGameTimer() < timeout do Wait(0) end
        if not NetworkHasControlOfEntity(ped) then return end
    end
    SetEntityAsMissionEntity(ped, true, true)
    DeletePed(ped)
end

---@param veh integer
local function removeVehicle(veh)
    if NetworkGetEntityIsNetworked(veh) and not NetworkHasControlOfEntity(veh) then
        NetworkRequestControlOfEntity(veh)
        local timeout = GetGameTimer() + 500
        while not NetworkHasControlOfEntity(veh) and GetGameTimer() < timeout do Wait(0) end
        if not NetworkHasControlOfEntity(veh) then return end
    end
    SetEntityAsMissionEntity(veh, true, true)
    DeleteVehicle(veh)
end

CreateThread(function()
    for i = 1, #shopAreas do
        local area = shopAreas[i]
        blockGenerators(area)
        -- impede NPCs de cenário (sentados, conversando etc.) de nascer na loja
        AddScenarioBlockingArea(area.min.x, area.min.y, area.min.z, area.max.x, area.max.y, area.max.z, false, true, true, true)
    end

    while true do
        local sleep = 3000
        local coords = GetEntityCoords(cache.ped)

        for i = 1, #shopAreas do
            local area = shopAreas[i]
            if #(coords - area.center) < 150.0 then
                sleep = 1500
                blockGenerators(area)

                local vehicles = GetGamePool('CVehicle')
                for v = 1, #vehicles do
                    local veh = vehicles[v]
                    if DoesEntityExist(veh) and area.poly:contains(GetEntityCoords(veh)) and isNpcVehicle(veh) then
                        removeVehicle(veh)
                    end
                end

                local peds = GetGamePool('CPed')
                for p = 1, #peds do
                    local ped = peds[p]
                    if DoesEntityExist(ped) and isNpcPed(ped) and area.poly:contains(GetEntityCoords(ped)) then
                        removePed(ped)
                    end
                end
            end
        end

        Wait(sleep)
    end
end)
