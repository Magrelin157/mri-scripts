local blocklist = {}
local sharedConfig = require 'config.shared'.vehicles
local allowed = {
    vehicles = {},
    count = 0,
    hidden = {}, -- modelos vanilla escondidos da loja
}

-- Vanilla = tudo que está no arquivo original do qbx_core (shared/vehicles.lua).
-- Addons registrados em runtime (mri_Qvehicles) não estão nesse arquivo, então continuam aparecendo.
if sharedConfig.hideVanilla then
    local allowVanilla = {}
    for i = 1, #(sharedConfig.allowVanilla or {}) do
        allowVanilla[sharedConfig.allowVanilla[i]] = true
    end

    local file = LoadResourceFile('qbx_core', 'shared/vehicles.lua')
    if file then
        local total = 0
        for model in file:gmatch('\n    ([%w_]+)%s*=%s*{') do
            if not allowVanilla[model] then
                allowed.hidden[model] = true
                total += 1
            end
        end
        lib.print.info(('Veículos vanilla escondidos da loja: %d'):format(total))
    else
        lib.print.warn('hideVanilla: não consegui ler qbx_core/shared/vehicles.lua')
    end
end

for i = 1, #sharedConfig.blocklist do
    local blockveh = sharedConfig.blocklist[i]
    blocklist[blockveh] = true
end

local function insertVehicle(vehicleData, shopType)
    allowed.count += 1
    allowed.vehicles[allowed.count] = {
        shopType = shopType,
        category = vehicleData.category,
        model = vehicleData.model,
    }
end

local function build()
    allowed.vehicles = {}
    allowed.count = 0

    for k, vehicle in pairs(exports.qbx_core:GetVehiclesByName()) do
        local vehicleShop = sharedConfig.models[k] or sharedConfig.categories[vehicle.category] or sharedConfig.default

        if blocklist[k] then
            lib.print.debug('Vehicle is blocked. Skipping: ' .. k)
        elseif allowed.hidden[k] then
            lib.print.debug('Vanilla vehicle hidden from shop. Skipping: ' .. k)
        elseif not vehicleShop then
            lib.print.debug('Vehicle not found in config. Skipping: ' .. k)
        else
            if type(vehicleShop) == 'table' then
                for i = 1, #vehicleShop do
                    insertVehicle(vehicle, vehicleShop[i])
                end
            else
                insertVehicle(vehicle, vehicleShop)
            end
        end
    end
end

build()

-- Rebuilds when vehicles are added/edited/removed at runtime (qbx_core mri/)
local rebuildPending = false
AddEventHandler('qbx_core:server:onVehicleUpdate', function()
    if rebuildPending then return end
    rebuildPending = true
    SetTimeout(500, function()
        rebuildPending = false
        build()
    end)
end)

return allowed
