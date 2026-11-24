-- m_radarmulta | app "Multas" do celular (sd-phone)

local APP_ID = 'm_multas'
local PHONE = 'sd-phone'

-- ícone com "versão" pelo conteúdo do arquivo, pra o celular não ficar com o ícone velho em cache
local function iconUrl()
    local svg = LoadResourceFile(cache.resource, 'html/icon.svg') or ''
    local hash = 0
    for i = 1, #svg do hash = (hash * 31 + svg:byte(i)) % 2147483647 end
    return ('https://cfx-nui-%s/html/icon.svg?v=%d'):format(cache.resource, hash)
end

local function registrar()
    if GetResourceState(PHONE) ~= 'started' then return end
    local ok, err = exports[PHONE]:addCustomApp({
        identifier = APP_ID,
        name = Config.App.nome,
        description = Config.App.descricao,
        developer = Config.App.desenvolvedor,
        defaultApp = Config.App.padrao == true,
        size = 4200,
        icon = iconUrl(),
        ui = ('%s/html/app.html'):format(cache.resource),
        images = {},
    })
    if not ok then lib.print.error(('addCustomApp: %s'):format(err)) end
end

CreateThread(registrar)

AddEventHandler('onClientResourceStart', function(res)
    if res == PHONE then registrar() end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    pcall(function() exports[PHONE]:removeCustomApp(APP_ID) end)
end)

-- chegou multa nova: o app (se estiver aberto) recarrega
RegisterNetEvent('m_radarmulta:client:atualizarApp', function()
    pcall(function()
        exports[PHONE]:sendCustomAppMessage(APP_ID, { action = 'atualizar', data = {} })
    end)
end)

-- ------------------------------------------------------------
-- callbacks chamados pela página do app (fetchNui)
-- ------------------------------------------------------------
RegisterNUICallback('estado', function(_, cb)
    cb(lib.callback.await('m_radarmulta:app:estado', false) or { erro = 'Sem sinal.' })
end)

RegisterNUICallback('pagar', function(data, cb)
    local id = type(data) == 'table' and tonumber(data.id)
    if not id then return cb({ ok = false, erro = 'Multa inválida.' }) end
    cb(lib.callback.await('m_radarmulta:app:pagar', false, id) or { ok = false, erro = 'Sem sinal.' })
end)

RegisterNUICallback('pagarTodas', function(_, cb)
    cb(lib.callback.await('m_radarmulta:app:pagarTodas', false) or { ok = false, erro = 'Sem sinal.' })
end)
