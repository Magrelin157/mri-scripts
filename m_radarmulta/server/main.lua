-- m_radarmulta | server
-- A multa vai para o DONO do veículo (player_vehicles do qbx_vehicles), não para quem está dirigindo.
-- As multas ficam na tabela m_radarmulta_lista e são pagas pelo app Multas do celular (client/app.lua).

MySQL.ready(function()
    -- A conta que recebe as multas precisa existir no ps-banking (ele só cria quando um chefe do job
    -- entra no servidor). Se não existir, cria vazia; quando o chefe entrar, o ps-banking assume ele como dono.
    local existe = MySQL.scalar.await('SELECT 1 FROM ps_banking_accounts WHERE holder = ? LIMIT 1', { Config.ContaDestino })
    if not existe then
        local cartao = tostring(math.random(1000, 9999)) .. ' ' .. tostring(math.random(1000, 9999)) .. ' '
            .. tostring(math.random(1000, 9999)) .. ' ' .. tostring(math.random(1000, 9999))
        MySQL.insert.await('INSERT INTO ps_banking_accounts (balance, holder, cardNumber, users, owner) VALUES (0, ?, ?, ?, ?)',
            { Config.ContaDestino, cartao, '[]', '{}' })
        print(('^3[m_radarmulta] conta "%s" não existia no ps-banking; criada para receber as multas^7'):format(Config.ContaDestino))
    else
        print(('^2[m_radarmulta] conta "%s" encontrada no ps-banking^7'):format(Config.ContaDestino))
    end
end)

local cooldowns = {} -- [placa] = { [idRadar] = os.time() }

local function trim(s)
    return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

local function calcularMulta(velocidade, limite)
    local excesso = (velocidade - limite) / limite * 100
    for _, f in ipairs(Config.Faixas) do
        if excesso <= f.ate then return f end
    end
    return Config.Faixas[#Config.Faixas]
end

-- (viatura de emergência, classe 18, é filtrada no client: o server não tem GetVehicleClass)
local function motoristaIsento(player)
    local job = player.PlayerData.job
    if not (job and Ajustes.jobsIsentos[job.name]) then return false end -- Ajustes: server/radares.lua (aba Isenções)
    if Ajustes.soEmServico then return job.onduty == true end
    return true
end

-- Dono pela placa que o radar "lê". Placa fria (fakeplate) não bate com nenhum registro = sem dono.
local function buscarDono(placa)
    local id = exports.qbx_vehicles:GetVehicleIdByPlate(placa)
    if not id then return nil end
    local v = exports.qbx_vehicles:GetPlayerVehicle(id)
    return v and v.citizenid or nil
end

-- ===== Multas (tabela própria) =====
-- m_radarmulta_lista guarda todas as multas. O jogador vê e paga pelo app Multas do celular.

MySQL.ready(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS m_radarmulta_lista (
            id         INT          NOT NULL AUTO_INCREMENT,
            citizenid  VARCHAR(64)  NOT NULL,
            placa      VARCHAR(16)  DEFAULT NULL,
            gravidade  VARCHAR(24)  DEFAULT NULL,
            origem     VARCHAR(16)  NOT NULL DEFAULT 'radar',
            descricao  VARCHAR(255) NOT NULL,
            valor      INT          NOT NULL,
            criado     INT          NOT NULL,
            pago       TINYINT(1)   NOT NULL DEFAULT 0,
            pago_em    INT          DEFAULT NULL,
            PRIMARY KEY (id),
            INDEX idx_cid (citizenid, pago)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])

    -- Migração: multas que ainda estavam em aberto no ps-banking / app de Faturas (versão antiga)
    -- passam pra cá e somem de lá. Roda só se a tabela antiga existir.
    local temAntiga = MySQL.scalar.await([[SELECT COUNT(*) FROM information_schema.tables
        WHERE table_schema = DATABASE() AND table_name = 'm_radarmulta_multas']])
    if tonumber(temAntiga) == 0 then return end

    local movidas = 0
    for _, m in ipairs(MySQL.query.await('SELECT * FROM m_radarmulta_multas') or {}) do
        local bill = MySQL.single.await('SELECT description, isPaid, UNIX_TIMESTAMP(date) AS quando FROM ps_banking_bills WHERE id = ?', { m.ps_bill_id })
        if bill and tonumber(bill.isPaid) == 0 then
            local desc = tostring(bill.description or 'Multa')
            local placa = desc:match('Placa%s+(.-)%s*$')
            local gravidade = desc:match('^Multa%s+(%S+)%s+%-')
            local origem = desc:find('^RDO') and 'policia' or 'radar'
            if placa then
                -- "Multa Grave - Rodovia X - 120 km/h (lim. 100) - Placa ABC" -> "Rodovia X - 120 km/h (lim. 100)"
                desc = desc:gsub('^Multa%s+%S+%s+%-%s+', ''):gsub('%s+%-%s+Placa%s+.-$', '')
            end
            MySQL.insert.await('INSERT INTO m_radarmulta_lista (citizenid, placa, gravidade, origem, descricao, valor, criado) VALUES (?, ?, ?, ?, ?, ?, ?)',
                { m.citizenid, placa, gravidade, origem, desc:sub(1, 255), m.valor, tonumber(bill.quando) or m.criado })
            movidas = movidas + 1
        end
        MySQL.query.await('DELETE FROM ps_banking_bills WHERE id = ?', { m.ps_bill_id })
        if m.phone_id then pcall(MySQL.query.await, 'DELETE FROM phone_service_invoices WHERE id = ?', { m.phone_id }) end
    end
    MySQL.query.await('DROP TABLE m_radarmulta_multas')
    print(('^3[m_radarmulta] %d multa(s) em aberto migradas do ps-banking pro app Multas^7'):format(movidas))
end)

local function avisarApp(citizenid, titulo, texto)
    local online = exports.qbx_core:GetPlayerByCitizenId(citizenid)
    if not online then return end
    local src = online.PlayerData.source
    TriggerClientEvent('m_radarmulta:client:atualizarApp', src)
    if titulo and Config.App.notificar then
        pcall(function()
            exports['sd-phone']:notify(src, { title = titulo, body = texto, app = 'm_multas', appId = 'm_multas', time = 'agora' })
        end)
    end
end

-- extra (opcional) = { placa = 'ABC1D23', gravidade = 'Grave', origem = 'radar' | 'policia' }
local function multar(citizenid, descricao, valor, extra)
    extra = type(extra) == 'table' and extra or {}
    local id = MySQL.insert.await(
        'INSERT INTO m_radarmulta_lista (citizenid, placa, gravidade, origem, descricao, valor, criado) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { citizenid, extra.placa and tostring(extra.placa):sub(1, 16) or nil, extra.gravidade and tostring(extra.gravidade):sub(1, 24) or nil,
          tostring(extra.origem or 'radar'):sub(1, 16), tostring(descricao):sub(1, 255), valor, os.time() })
    return id ~= nil, id
end

-- Usado por outros scripts (ex.: m_mdt) pra lançar multa no app Multas do celular
exports('Multar', function(citizenid, descricao, valor, extra)
    valor = math.floor(tonumber(valor) or 0)
    if type(citizenid) ~= 'string' or valor <= 0 then return false end
    extra = type(extra) == 'table' and extra or { origem = 'policia' }
    local ok, id = multar(citizenid, tostring(descricao or 'Multa'), valor, extra)
    if ok then avisarApp(citizenid, 'Nova multa', ('Multa %d - R$ %s'):format(id, valor)) end
    return ok
end)

-- Compatibilidade com o ps-banking modificado (ele ainda chama esses exports).
-- Multa não passa mais pelo banco, então: qualquer fatura do banco pode ser cobrada normalmente,
-- e nenhum pagamento do app de Faturas é de multa.
exports('ReservarPagamento', function() return true end)
exports('EhPagamentoDeMulta', function() return false end)

-- ===== App Multas: consulta e pagamento =====

local function linhaApp(l)
    return {
        id = l.id, placa = l.placa, gravidade = l.gravidade, origem = l.origem,
        descricao = l.descricao, valor = l.valor, criado = l.criado, pagoEm = l.pago_em,
    }
end

local function estado(src)
    local p = exports.qbx_core:GetPlayer(src)
    if not p then return nil end
    local cid = p.PlayerData.citizenid
    local pend, pagas, total = {}, {}, 0
    for _, l in ipairs(MySQL.query.await('SELECT * FROM m_radarmulta_lista WHERE citizenid = ? AND pago = 0 ORDER BY id DESC', { cid }) or {}) do
        pend[#pend + 1] = linhaApp(l)
        total = total + l.valor
    end
    for _, l in ipairs(MySQL.query.await('SELECT * FROM m_radarmulta_lista WHERE citizenid = ? AND pago = 1 ORDER BY pago_em DESC LIMIT ?',
        { cid, Config.App.historico or 50 }) or {}) do
        pagas[#pagas + 1] = linhaApp(l)
    end
    local nome = p.PlayerData.charinfo and (p.PlayerData.charinfo.firstname .. ' ' .. p.PlayerData.charinfo.lastname) or ''
    return { pendentes = pend, pagas = pagas, total = total, saldo = p.PlayerData.money.bank or 0, nome = nome }
end

lib.callback.register('m_radarmulta:app:estado', function(source)
    return estado(source)
end)

local pagando = {} -- trava por jogador (evita clique duplo)

-- paga uma lista de multas (ids) do jogador, tudo ou nada
local function pagar(src, ids)
    if pagando[src] then return { ok = false, erro = 'Aguarde...' } end
    local p = exports.qbx_core:GetPlayer(src)
    if not p then return { ok = false, erro = 'Sem sinal.' } end
    local cid = p.PlayerData.citizenid
    pagando[src] = true

    local ok, res = pcall(function()
        local lista
        if ids then
            if #ids == 0 then return { ok = false, erro = 'Nenhuma multa.' } end
            lista = MySQL.query.await(('SELECT id, valor FROM m_radarmulta_lista WHERE citizenid = ? AND pago = 0 AND id IN (%s)')
                :format(('?,'):rep(#ids):sub(1, -2)), { cid, table.unpack(ids) }) or {}
        else
            lista = MySQL.query.await('SELECT id, valor FROM m_radarmulta_lista WHERE citizenid = ? AND pago = 0', { cid }) or {}
        end
        if #lista == 0 then return { ok = false, erro = 'Essa multa já foi paga.' } end

        local total, marcados = 0, {}
        for _, l in ipairs(lista) do total = total + l.valor; marcados[#marcados + 1] = l.id end

        if (p.PlayerData.money.bank or 0) < total then
            return { ok = false, erro = 'Saldo insuficiente no banco.' }
        end

        -- marca como paga primeiro (só as que ainda estão em aberto); se o banco falhar, desfaz
        local agora = os.time()
        local marcar = ('UPDATE m_radarmulta_lista SET pago = 1, pago_em = ? WHERE pago = 0 AND id IN (%s)')
            :format(('?,'):rep(#marcados):sub(1, -2))
        local afetadas = MySQL.update.await(marcar, { agora, table.unpack(marcados) })
        if tonumber(afetadas) ~= #marcados then
            if (tonumber(afetadas) or 0) > 0 then
                MySQL.update.await(('UPDATE m_radarmulta_lista SET pago = 0, pago_em = NULL WHERE pago_em = ? AND id IN (%s)')
                    :format(('?,'):rep(#marcados):sub(1, -2)), { agora, table.unpack(marcados) })
            end
            return { ok = false, erro = 'Essa multa já foi paga.' }
        end

        local motivo = #marcados == 1 and ('Multa %d'):format(marcados[1]) or ('%d multas'):format(#marcados)
        if not p.Functions.RemoveMoney('bank', total, 'Pagamento: ' .. motivo) then
            MySQL.update.await(('UPDATE m_radarmulta_lista SET pago = 0, pago_em = NULL WHERE id IN (%s)')
                :format(('?,'):rep(#marcados):sub(1, -2)), marcados)
            return { ok = false, erro = 'Saldo insuficiente no banco.' }
        end

        -- dinheiro pra conta da polícia no ps-banking
        local creditou = pcall(function()
            return exports['ps-banking']:AddMoney(Config.ContaDestino, total, ('Multa paga (%s) - %s'):format(cid, motivo))
        end)
        if not creditou then
            MySQL.update.await('UPDATE ps_banking_accounts SET balance = balance + ? WHERE holder = ?', { total, Config.ContaDestino })
        end

        if Config.Debug then print(('[m_radarmulta] %s pagou %s: R$ %d'):format(cid, motivo, total)) end
        return { ok = true, pagas = #marcados, valor = total }
    end)

    pagando[src] = nil
    if not ok then
        print('^1[m_radarmulta] erro ao pagar multa: ' .. tostring(res) .. '^7')
        return { ok = false, erro = 'Erro ao pagar. Tente de novo.' }
    end
    return res
end

local function logPagamento(src, oque, res)
    if not Config.Debug then return end
    print(('[m_radarmulta] pagamento pelo app: jogador %s, %s -> %s'):format(
        src, oque, res and (res.ok and ('OK (%s multa(s), R$ %s)'):format(res.pagas, res.valor) or ('FALHOU: ' .. tostring(res.erro))) or 'sem resposta'))
end

lib.callback.register('m_radarmulta:app:pagar', function(source, id)
    if Config.Debug then print(('[m_radarmulta] app pediu pra pagar a multa %s (jogador %s)'):format(tostring(id), source)) end
    id = math.floor(tonumber(id) or 0)
    if id <= 0 then return { ok = false, erro = 'Multa inválida.' } end
    local res = pagar(source, { id })
    logPagamento(source, 'multa ' .. id, res)
    return res
end)

lib.callback.register('m_radarmulta:app:pagarTodas', function(source)
    if Config.Debug then print(('[m_radarmulta] app pediu pra pagar todas (jogador %s)'):format(source)) end
    local res = pagar(source, nil)
    logPagamento(source, 'todas', res)
    return res
end)

AddEventHandler('playerDropped', function() pagando[source] = nil end)

RegisterNetEvent('m_radarmulta:server:flagrante', function(radarId, velocidade)
    local src = source
    local indice = tonumber(radarId)
    local radar = indice and Radares[indice]
    velocidade = tonumber(velocidade)
    if not radar or not radar.ativo or not velocidade then return end

    local motorista = exports.qbx_core:GetPlayer(src)
    if not motorista then return end

    -- validação: tem que estar perto do radar e dirigindo um veículo
    local ped = GetPlayerPed(src)
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then return end
    -- (folga de 30 m na horizontal por causa do atraso da rede a alta velocidade)
    local pos = GetEntityCoords(ped)
    if #(pos.xy - radar.centro.xy) > AlcanceDoRadar(radar) + 30.0 then return end
    if math.abs(pos.z - radar.centro.z) > Config.AlturaMaxima + 15.0 then return end

    -- velocidade absurda = cliente mentindo/bugado; ignora
    if velocidade > 600 or velocidade <= radar.limite + Config.Tolerancia then return end

    if motoristaIsento(motorista) then return end

    local placa = trim(GetVehicleNumberPlateText(veh))
    if placa == '' then return end

    -- cooldown por veículo/radar
    cooldowns[placa] = cooldowns[placa] or {}
    local agora = os.time()
    if cooldowns[placa][indice] and agora - cooldowns[placa][indice] < Config.Cooldown then return end
    cooldowns[placa][indice] = agora

    local faixa = calcularMulta(velocidade, radar.limite)
    local descricao = ('%s - %d km/h (lim. %d)'):format(radar.nome, velocidade, radar.limite)

    local dono = buscarDono(placa)
    if not dono and Config.SemDono == 'motorista' then
        dono = motorista.PlayerData.citizenid
    end

    if not dono then
        if Config.Debug then print(('[m_radarmulta] placa %s sem dono registrado: %s'):format(placa, descricao)) end
        return
    end

    local multou, idMulta = multar(dono, descricao, faixa.valor, { placa = placa, gravidade = faixa.nome, origem = 'radar' })
    if not multou then return end

    -- avisa o dono pelo celular se ele estiver online (mesmo que não seja ele dirigindo)
    avisarApp(dono, 'Radar de velocidade', ('Multa %d (%s) - Placa %s - R$ %s'):format(idMulta, faixa.nome, placa, faixa.valor))

    if Config.Debug then
        print(('[m_radarmulta] %s dirigindo, multa para %s: %s'):format(
            motorista.PlayerData.citizenid, dono, descricao))
    end
end)

-- limpa cooldowns vencidos de tempos em tempos
CreateThread(function()
    while true do
        Wait(5 * 60 * 1000)
        local agora = os.time()
        for placa, lista in pairs(cooldowns) do
            local vazio = true
            for i, t in pairs(lista) do
                if agora - t >= Config.Cooldown then lista[i] = nil else vazio = false end
            end
            if vazio then cooldowns[placa] = nil end
        end
    end
end)


