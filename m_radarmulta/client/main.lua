-- m_radarmulta | client

local radares = {}       -- lista vinda do servidor (GlobalState.m_radarmulta_radares)
local ultimoDisparo = {} -- [idRadar] = GetGameTimer() do último flash (evita spam de evento)
local blips = {}
local mostrarAreas = false

local function notificar(msg, tipo)
    lib.notify({ title = 'Radares', description = msg, type = tipo or 'inform' })
end

local function diffAngulo(a, b)
    local d = math.abs(a - b) % 360
    return d > 180 and 360 - d or d
end

-------------------------------------------------------------------------------
-- Lista de radares (vem do servidor, que lê do banco)
-------------------------------------------------------------------------------

local function converter(lista)
    local out = {}
    for _, r in ipairs(lista or {}) do
        out[#out + 1] = {
            id = r.id, nome = r.nome, limite = r.limite, ativo = r.ativo,
            centro = vec3(r.centro.x, r.centro.y, r.centro.z),
            raio = r.raio,
            pontos = r.pontos and #r.pontos >= 3 and r.pontos or nil,
            heading = r.heading, margem = r.margem or 60,
        }
        local x = out[#out]
        x.alcance = x.pontos and Area.raioMaximo(x.pontos, x.centro) or x.raio
    end
    return out
end

local function atualizarBlips()
    for _, b in ipairs(blips) do if DoesBlipExist(b) then RemoveBlip(b) end end
    blips = {}
    if not Config.Blips.ativo then return end
    for _, r in ipairs(radares) do
        if r.ativo then
            local blip = AddBlipForCoord(r.centro.x, r.centro.y, r.centro.z)
            SetBlipSprite(blip, Config.Blips.sprite)
            SetBlipColour(blip, Config.Blips.cor)
            SetBlipScale(blip, Config.Blips.escala)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(('%s (%d km/h)'):format(Config.Blips.nome, r.limite))
            EndTextCommandSetBlipName(blip)
            blips[#blips + 1] = blip
        end
    end
end

local function aplicarLista(lista)
    radares = converter(lista)
    atualizarBlips()
end

AddStateBagChangeHandler('m_radarmulta_radares', 'global', function(_, _, valor)
    aplicarLista(valor)
end)

-------------------------------------------------------------------------------
-- Detecção
-------------------------------------------------------------------------------

local function flash()
    if not Config.Flash then return end
    PlaySoundFrontend(-1, 'Camera_Shoot', 'Phone_Soundset_Franklin', true)
    CreateThread(function()
        local inicio = GetGameTimer()
        local duracao = 350
        while GetGameTimer() - inicio < duracao do
            local alpha = math.floor(220 * (1 - (GetGameTimer() - inicio) / duracao))
            DrawRect(0.5, 0.5, 1.0, 1.0, 255, 255, 255, alpha)
            Wait(0)
        end
    end)
end

local function dentroDoRadar(r, pos)
    if math.abs(pos.z - r.centro.z) > Config.AlturaMaxima then return false end
    return Area.dentro(r, pos)
end

CreateThread(function()
    while true do
        local espera = 1000
        local veh = cache.vehicle

        local classe = veh and GetVehicleClass(veh)
        if veh and cache.seat == -1 and not Config.ClassesIgnoradas[classe]
            and not (Config.IsentarEmergencia and classe == 18) then
            local pos = GetEntityCoords(veh)
            local agora = GetGameTimer()

            for _, r in ipairs(radares) do
                if r.ativo then
                    local dist = #(pos.xy - r.centro.xy)
                    if dist < r.alcance + 120.0 then espera = 50 end -- perto: checa bem mais rápido

                    if dist <= r.alcance and dentroDoRadar(r, pos)
                        and (not ultimoDisparo[r.id] or agora - ultimoDisparo[r.id] > Config.Cooldown * 1000) then
                        local kmh = GetEntitySpeed(veh) * 3.6
                        local sentidoOk = not r.heading or diffAngulo(GetEntityHeading(veh), r.heading) <= r.margem

                        if sentidoOk and kmh > r.limite + Config.Tolerancia then
                            ultimoDisparo[r.id] = agora
                            flash()
                            TriggerServerEvent('m_radarmulta:server:flagrante', r.id, math.floor(kmh))
                        end
                    end
                end
            end
        end

        Wait(espera)
    end
end)

RegisterNetEvent('m_radarmulta:client:multado', function(dados)
    lib.notify({
        title = 'Radar de velocidade',
        description = ('Seu veículo %s foi multado (%s): %d km/h numa via de %d km/h.\nR$ %s no app Multas do celular.'):format(
            dados.placa, dados.gravidade, dados.velocidade, dados.limite, dados.valor),
        type = 'error',
        icon = 'camera',
        duration = 8000,
    })
end)

-------------------------------------------------------------------------------
-- Visualização das áreas (botão "Mostrar áreas" do painel)
-------------------------------------------------------------------------------

local function direcaoCamera()
    local rot = GetGameplayCamRot(2)
    local z, x = math.rad(rot.z), math.rad(rot.x)
    local cx = math.abs(math.cos(x))
    return vec3(-math.sin(z) * cx, math.cos(z) * cx, math.sin(x))
end

-- parede entre dois cantos (do chão até "altura"), vista dos dois lados
local function parede(a, b, altura, r, g, bl, alpha)
    local a2, b2 = vec3(a.x, a.y, a.z + altura), vec3(b.x, b.y, b.z + altura)
    DrawPoly(a.x, a.y, a.z, b.x, b.y, b.z, b2.x, b2.y, b2.z, r, g, bl, alpha)
    DrawPoly(b2.x, b2.y, b2.z, b.x, b.y, b.z, a.x, a.y, a.z, r, g, bl, alpha)
    DrawPoly(a.x, a.y, a.z, b2.x, b2.y, b2.z, a2.x, a2.y, a2.z, r, g, bl, alpha)
    DrawPoly(a2.x, a2.y, a2.z, b2.x, b2.y, b2.z, a.x, a.y, a.z, r, g, bl, alpha)
    DrawLine(a.x, a.y, a.z, b.x, b.y, b.z, r, g, bl, 255)
    DrawLine(a2.x, a2.y, a2.z, b2.x, b2.y, b2.z, r, g, bl, 255)
    DrawLine(a.x, a.y, a.z, a2.x, a2.y, a2.z, r, g, bl, 255)
end

local function texto3D(coords, txt)
    local ok, x, y = GetScreenCoordFromWorldCoord(coords.x, coords.y, coords.z)
    if not ok then return end
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextCentre(true)
    SetTextOutline()
    SetTextColour(255, 255, 255, 230)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(txt)
    EndTextCommandDisplayText(x, y)
end

local function setaSentido(r)
    if not r.heading then return end
    local rad = math.rad(r.heading)
    local dir = vec3(-math.sin(rad), math.cos(rad), 0.0)
    local a = r.centro + vec3(0, 0, 2.0)
    local b = a + dir * math.min(r.alcance, 15.0)
    DrawLine(a.x, a.y, a.z, b.x, b.y, b.z, 255, 220, 0, 255)
    -- ponta da seta
    local lado = vec3(-dir.y, dir.x, 0.0)
    local p1 = b - dir * 3.0 + lado * 2.0
    local p2 = b - dir * 3.0 - lado * 2.0
    DrawLine(b.x, b.y, b.z, p1.x, p1.y, p1.z, 255, 220, 0, 255)
    DrawLine(b.x, b.y, b.z, p2.x, p2.y, p2.z, 255, 220, 0, 255)
end

local function loopAreas()
    CreateThread(function()
        while mostrarAreas do
            local pos = GetEntityCoords(cache.ped)
            for _, r in ipairs(radares) do
                if #(pos.xy - r.centro.xy) <= r.alcance + 400.0 then
                    local cr, cg, cb = 255, 60, 60
                    if not r.ativo then cr, cg, cb = 150, 150, 150 end
                    if r.pontos then
                        for i, p in ipairs(r.pontos) do
                            local q = r.pontos[i % #r.pontos + 1]
                            parede(vec3(p.x, p.y, p.z - 2.0), vec3(q.x, q.y, q.z - 2.0), 20.0, cr, cg, cb, 45)
                        end
                    else
                        DrawMarker(1, r.centro.x, r.centro.y, r.centro.z - 3.0, 0, 0, 0, 0, 0, 0,
                            r.raio * 2.0, r.raio * 2.0, 20.0, cr, cg, cb, 45, false, false, 2, false, nil, nil, false)
                    end
                    setaSentido(r)
                    if #(pos - r.centro) <= 120.0 then
                        texto3D(r.centro + vec3(0, 0, 4.0), ('~r~%s~w~\n%d km/h%s%s'):format(
                            r.nome, r.limite, r.heading and (' | só %.0f°'):format(r.heading) or ' | 2 sentidos',
                            r.ativo and '' or ' | ~c~DESLIGADO'))
                    end
                end
            end
            Wait(0)
        end
    end)
end

local function definirAreas(ativo)
    if ativo == mostrarAreas then return end
    mostrarAreas = ativo
    if ativo then loopAreas() end
end

-------------------------------------------------------------------------------
-- Desenhar a área (igual ao do m_territorios): mire e aperte E (ou clique) em cada
-- canto, Backspace desfaz, R recomeça, Enter termina e Esc cancela. Mínimo 3 cantos.
-------------------------------------------------------------------------------

local function textoDesenho(n)
    lib.showTextUI(('Desenhando a área do radar  \n%d canto%s marcado%s  \n  \n[E] / [Clique] Marcar canto  \n[Backspace] Desfazer  \n[R] Recomeçar  \n[Enter] Terminar  \n[Esc] Cancelar')
        :format(n, n == 1 and '' or 's', n == 1 and '' or 's'), { position = 'left-center', icon = 'fa-solid fa-draw-polygon' })
end

local function numeroNoCanto(p, txt)
    local ok, x, y = GetScreenCoordFromWorldCoord(p.x, p.y, p.z + 3.0)
    if not ok then return end
    SetTextFont(4)
    SetTextScale(0.0, 0.5)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(txt)
    EndTextCommandDisplayText(x, y)
end

local function desenharArea()
    local cantos = {}
    local ALTURA = 15.0
    textoDesenho(0)
    Wait(200) -- não pegar o clique que abriu o menu

    local resultado
    while true do
        Wait(0)
        for _, c in ipairs({ 24, 25, 38, 45, 47, 140, 141, 142, 143, 177, 194, 199, 200, 257 }) do DisableControlAction(0, c, true) end

        local de = GetGameplayCamCoord()
        local destino = de + direcaoCamera() * 300.0
        local _, acertou, mira = GetShapeTestResult(StartExpensiveSynchronousShapeTestLosProbe(
            de.x, de.y, de.z, destino.x, destino.y, destino.z, 1 | 16, cache.ped, 0))
        if acertou ~= 1 and acertou ~= true then mira = nil end

        if mira then
            DrawMarker(28, mira.x, mira.y, mira.z, 0, 0, 0, 0, 0, 0, 0.6, 0.6, 0.6, 239, 68, 68, 220, false, false, 2, false, nil, nil, false)
        end

        local n = #cantos
        for i = 1, n - 1 do parede(cantos[i], cantos[i + 1], ALTURA, 239, 68, 68, 70) end
        if n > 0 and mira then
            parede(cantos[n], mira, ALTURA, 255, 255, 255, 40)
            if n > 1 then parede(mira, cantos[1], ALTURA, 255, 255, 255, 25) end
        elseif n > 2 then
            parede(cantos[n], cantos[1], ALTURA, 239, 68, 68, 70)
        end
        for i = 1, n do numeroNoCanto(cantos[i], tostring(i)) end

        if (IsDisabledControlJustPressed(0, 38) or IsDisabledControlJustPressed(0, 24)) and mira then
            cantos[n + 1] = vec3(mira.x, mira.y, mira.z)
            PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
            textoDesenho(#cantos)
        elseif (IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 194)) and n > 0 then
            cantos[n] = nil
            PlaySoundFrontend(-1, 'BACK', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
            textoDesenho(#cantos)
        elseif IsDisabledControlJustPressed(0, 45) and n > 0 then
            cantos = {}
            textoDesenho(0)
        elseif IsControlJustPressed(0, 201) or IsControlJustPressed(0, 191) then
            if n >= 3 then
                resultado = {}
                for i, p in ipairs(cantos) do
                    resultado[i] = { x = math.floor(p.x * 100 + 0.5) / 100, y = math.floor(p.y * 100 + 0.5) / 100, z = math.floor(p.z * 100 + 0.5) / 100 }
                end
                break
            end
            PlaySoundFrontend(-1, 'ERROR', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
            notificar('Marque pelo menos 3 cantos.', 'error')
        elseif IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 199) then
            break
        end
    end

    lib.hideTextUI()
    return resultado
end

-------------------------------------------------------------------------------
-- Aba no painel do mri_Qadmin (Plugins > Radares)
-- A página (html/index.html) abre dentro do painel e chama estes callbacks.
-------------------------------------------------------------------------------

local PLUGIN_ID = 'radares'

local function qadminLigado()
    return GetResourceState('mri_Qadmin') == 'started'
end

local function fecharPainelAdmin()
    if not qadminLigado() then return end
    pcall(function() exports.mri_Qadmin:ClosePlugin(PLUGIN_ID) end)
    Wait(300)
end

local function reabrirPainelAdmin()
    if not qadminLigado() then return end
    pcall(function() exports.mri_Qadmin:OpenPlugin(PLUGIN_ID) end)
end

local function irPara(c)
    DoScreenFadeOut(300) Wait(300)
    SetEntityCoords(cache.ped, c.x, c.y, c.z + 1.0, false, false, false, false)
    DoScreenFadeIn(300)
end

local function acaoServidor(nome, id, dados)
    return lib.callback.await('m_radarmulta:admin:acao', false, nome, id, dados)
end

RegisterNUICallback('plugin:lista', function(_, cb)
    local d = lib.callback.await('m_radarmulta:admin:lista', false)
    if d then d.mostrarAreas = mostrarAreas end
    cb(d or false)
end)

RegisterNUICallback('plugin:acao', function(p, cb)
    p = type(p) == 'table' and p or {}
    local ok, msg, extra = acaoServidor(p.nome, p.id, p.dados)
    cb({ ok = ok == true, msg = msg, extra = extra })
end)

RegisterNUICallback('plugin:mundo', function(p, cb)
    p = type(p) == 'table' and p or {}
    local d = type(p.dados) == 'table' and p.dados or {}

    if p.tipo == 'areas' then
        definirAreas(not mostrarAreas)
        return cb({ ok = true, mostrarAreas = mostrarAreas })
    end

    if p.tipo == 'criar' then
        -- cria onde o admin está e, se pediu, já abre o desenho da área
        local ok, msg, id = acaoServidor('criar', nil, d)
        if not ok then return cb({ ok = false, msg = msg }) end
        definirAreas(true)
        if not d.desenhar then return cb({ ok = true, msg = msg, id = id }) end
        cb({ ok = true, id = id })
        fecharPainelAdmin()
        local pontos = desenharArea()
        if pontos then
            local ok2, msg2 = acaoServidor('desenharArea', id, { pontos = pontos })
            notificar(msg2, ok2 and 'success' or 'error')
        else
            notificar('Desenho cancelado: o radar ficou como círculo. Dá pra desenhar depois pelo painel.', 'inform')
        end
        reabrirPainelAdmin()
        return
    end

    if p.tipo == 'desenhar' then
        cb({ ok = true })
        fecharPainelAdmin()
        definirAreas(true)
        local pontos = desenharArea()
        if pontos then
            local ok, msg = acaoServidor('desenharArea', d.id, { pontos = pontos })
            notificar(msg, ok and 'success' or 'error')
        else
            notificar('Desenho cancelado.', 'error')
        end
        reabrirPainelAdmin()
        return
    end

    if p.tipo == 'sentidoAtual' then
        -- direção pra onde o admin (ou o carro dele) está virado
        local h = GetEntityHeading(cache.vehicle or cache.ped)
        local ok, msg = acaoServidor('sentido', d.id, { heading = h })
        return cb({ ok = ok == true, msg = msg })
    end

    if p.tipo == 'irPara' then
        cb({ ok = true })
        if type(d.coords) ~= 'table' then return end
        fecharPainelAdmin()
        definirAreas(true)
        irPara(d.coords)
        return
    end

    cb({ ok = false, msg = 'Ação inválida.' })
end)

-------------------------------------------------------------------------------

CreateThread(function()
    aplicarLista(GlobalState.m_radarmulta_radares)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, b in ipairs(blips) do if DoesBlipExist(b) then RemoveBlip(b) end end
    lib.hideTextUI()
end)
