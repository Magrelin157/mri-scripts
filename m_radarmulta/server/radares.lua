-- m_radarmulta | radares salvos no banco + aba no painel do mri_Qadmin (Plugins > Radares)
--
-- Cada radar é um CÍRCULO (centro + raio) ou uma ÁREA DESENHADA (cantos), igual aos territórios
-- do m_territorios. Os radares ficam na tabela m_radarmulta_radares e vão pros jogadores pelo
-- GlobalState (m_radarmulta_radares).

Radares = {}   -- [id] = radar (usado pelo server/main.lua pra validar a multa)

-- Isenções editadas no painel (aba Isenções). Começa com o que está no config.lua e,
-- depois que alguém salva no painel, passa a valer o que está no banco.
Ajustes = {
    jobsIsentos = Config.JobsIsentos or {},
    soEmServico = Config.IsentoSoEmServico ~= false,
}
local ordem = {}

local ACE = 'command.radares' -- criado pelo lib.addCommand('radares') com restricted = 'group.admin'
local PLUGIN_ID = 'radares'

local function ehAdmin(src)
    return IsPlayerAceAllowed(src, ACE)
end

local function arred(n) return math.floor((tonumber(n) or 0) * 100 + 0.5) / 100 end

-- distância máxima do centro até a borda (pra checagens rápidas)
function AlcanceDoRadar(r)
    if Area.ehPoligono(r) then return Area.raioMaximo(r.pontos, r.centro) end
    return r.raio
end

-------------------------------------------------------------------------------
-- Banco
-------------------------------------------------------------------------------

local function linhaParaRadar(l)
    local pontos
    if l.pontos and l.pontos ~= '' then
        local ok, p = pcall(json.decode, l.pontos)
        if ok and type(p) == 'table' and #p >= 3 then pontos = p end
    end
    local r = {
        id = tonumber(l.id),
        nome = l.nome,
        limite = tonumber(l.limite) or 100,
        ativo = l.ativo == true or l.ativo == 1,
        raio = tonumber(l.raio) or 20.0,
        pontos = pontos,
        heading = l.heading ~= nil and tonumber(l.heading) or nil,
        margem = tonumber(l.margem) or 60,
    }
    r.centro = pontos and Area.centro(pontos) or vec3(tonumber(l.cx) or 0.0, tonumber(l.cy) or 0.0, tonumber(l.cz) or 0.0)
    return r
end

local function carregar()
    Radares, ordem = {}, {}
    local linhas = MySQL.query.await('SELECT * FROM m_radarmulta_radares ORDER BY id') or {}
    for _, l in ipairs(linhas) do
        local r = linhaParaRadar(l)
        Radares[r.id] = r
        ordem[#ordem + 1] = r.id
    end
end

-- manda a lista pros jogadores (só o necessário pra detectar e desenhar)
local function sincronizar()
    local lista = {}
    for _, id in ipairs(ordem) do
        local r = Radares[id]
        lista[#lista + 1] = {
            id = r.id, nome = r.nome, limite = r.limite, ativo = r.ativo,
            centro = { x = r.centro.x, y = r.centro.y, z = r.centro.z },
            raio = r.raio, pontos = r.pontos, heading = r.heading, margem = r.margem,
        }
    end
    GlobalState.m_radarmulta_radares = lista
end

local function recarregar()
    carregar()
    sincronizar()
end

MySQL.ready(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS m_radarmulta_radares (
            id          INT          NOT NULL AUTO_INCREMENT,
            nome        VARCHAR(60)  NOT NULL,
            limite      INT          NOT NULL DEFAULT 100,
            ativo       TINYINT(1)   NOT NULL DEFAULT 1,
            cx          FLOAT        NOT NULL DEFAULT 0,
            cy          FLOAT        NOT NULL DEFAULT 0,
            cz          FLOAT        NOT NULL DEFAULT 0,
            raio        FLOAT        NOT NULL DEFAULT 20,
            pontos      LONGTEXT     DEFAULT NULL,
            heading     FLOAT        DEFAULT NULL,
            margem      INT          NOT NULL DEFAULT 60,
            editado_por VARCHAR(64)  DEFAULT NULL,
            atualizado  INT          NOT NULL DEFAULT 0,
            PRIMARY KEY (id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS m_radarmulta_ajustes (
            chave VARCHAR(40) NOT NULL,
            valor LONGTEXT    NOT NULL,
            PRIMARY KEY (chave)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    for _, l in ipairs(MySQL.query.await('SELECT chave, valor FROM m_radarmulta_ajustes') or {}) do
        local ok, v = pcall(json.decode, l.valor)
        if ok and v ~= nil then
            if l.chave == 'jobsIsentos' and type(v) == 'table' then
                local t = {}
                for _, nome in ipairs(v) do t[nome] = true end
                Ajustes.jobsIsentos = t
            elseif l.chave == 'soEmServico' then
                Ajustes.soEmServico = v == true
            end
        end
    end

    -- 1ª vez com a versão nova: copia os radares que estavam no config.lua
    if GetResourceKvpInt('importou_config') ~= 1 then
        local qtd = MySQL.scalar.await('SELECT COUNT(*) FROM m_radarmulta_radares') or 0
        if tonumber(qtd) == 0 then
            for _, r in ipairs(Config.RadaresIniciais or {}) do
                MySQL.insert.await(
                    'INSERT INTO m_radarmulta_radares (nome, limite, cx, cy, cz, raio, heading, atualizado) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
                    { r.nome, r.limite or 100, r.coords.x, r.coords.y, r.coords.z, r.raio or Config.RaioPadrao,
                      r.heading, os.time() })
            end
            print(('^3[m_radarmulta] %d radar(es) do config.lua copiados pro banco^7'):format(#(Config.RadaresIniciais or {})))
        end
        SetResourceKvpInt('importou_config', 1)
    end

    recarregar()
    print(('^2[m_radarmulta] iniciado com %d radar(es)^7'):format(#ordem))
end)

-------------------------------------------------------------------------------
-- Painel do admin
-------------------------------------------------------------------------------

local function texto(v, max)
    v = type(v) == 'string' and v:match('^%s*(.-)%s*$') or ''
    return v:sub(1, max or 60)
end

local function numero(v, min, max)
    v = tonumber(v)
    if not v or v ~= v then return nil end
    return math.min(math.max(v, min), max)
end

local function quem(src)
    local p = exports.qbx_core:GetPlayer(src)
    return p and p.PlayerData.citizenid or ('id ' .. src)
end

local function salvarCampos(id, src, campos)
    local sets, vals = {}, {}
    for k, v in pairs(campos) do
        sets[#sets + 1] = ('`%s` = ?'):format(k)
        vals[#vals + 1] = v
    end
    sets[#sets + 1] = 'editado_por = ?' vals[#vals + 1] = quem(src)
    sets[#sets + 1] = 'atualizado = ?'  vals[#vals + 1] = os.time()
    vals[#vals + 1] = id
    MySQL.update.await(('UPDATE m_radarmulta_radares SET %s WHERE id = ?'):format(table.concat(sets, ', ')), vals)
end

lib.callback.register('m_radarmulta:admin:lista', function(source)
    if not ehAdmin(source) then return nil end
    local lista = {}
    for _, id in ipairs(ordem) do
        local r = Radares[id]
        local poligono = Area.ehPoligono(r)
        lista[#lista + 1] = {
            id = r.id,
            nome = r.nome,
            limite = r.limite,
            ativo = r.ativo,
            forma = poligono and 'poligono' or 'circulo',
            raio = r.raio,
            cantos = poligono and #r.pontos or 0,
            tamanho = poligono and math.floor(Area.tamanho(r.pontos)) or math.floor(math.pi * r.raio * r.raio),
            heading = r.heading,
            margem = r.margem,
            centro = { x = arred(r.centro.x), y = arred(r.centro.y), z = arred(r.centro.z) },
        }
    end
    local faixas = {}
    for _, f in ipairs(Config.Faixas) do
        faixas[#faixas + 1] = { nome = f.nome, valor = f.valor, ate = f.ate ~= math.huge and f.ate or nil }
    end
    -- empregos do servidor (qbx_core) pra aba Isenções
    local empregos = {}
    local ok, jobs = pcall(function() return exports.qbx_core:GetJobs() end)
    if ok and type(jobs) == 'table' then
        for nome, j in pairs(jobs) do
            if nome ~= 'unemployed' then
                empregos[#empregos + 1] = { nome = nome, label = j.label or nome, tipo = j.type, isento = Ajustes.jobsIsentos[nome] == true }
            end
        end
    end
    -- job isento que não existe mais no qbx_core continua aparecendo (pra dar pra tirar)
    for nome in pairs(Ajustes.jobsIsentos) do
        local achou = false
        for _, e in ipairs(empregos) do if e.nome == nome then achou = true break end end
        if not achou then empregos[#empregos + 1] = { nome = nome, label = nome, isento = true, sumiu = true } end
    end
    table.sort(empregos, function(a, b)
        if a.isento ~= b.isento then return a.isento end
        return tostring(a.label):lower() < tostring(b.label):lower()
    end)

    return {
        empregos = empregos,
        soEmServico = Ajustes.soEmServico,
        isentarEmergencia = Config.IsentarEmergencia,
        radares = lista,
        tolerancia = Config.Tolerancia,
        faixas = faixas,
        raioPadrao = Config.RaioPadrao,
        limitePadrao = Config.LimitePadrao,
        contaDestino = Config.ContaDestino,
    }
end)

local acoes = {}

function acoes.criar(src, _, d)
    local nome = texto(d.nome, 60)
    if nome == '' then return false, 'Dê um nome ao radar.' end
    local limite = numero(d.limite, 10, 400)
    if not limite then return false, 'Limite de velocidade inválido.' end
    local raio = numero(d.raio, 3, 300) or Config.RaioPadrao
    local pos = GetEntityCoords(GetPlayerPed(src))
    local id = MySQL.insert.await(
        'INSERT INTO m_radarmulta_radares (nome, limite, cx, cy, cz, raio, editado_por, atualizado) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        { nome, math.floor(limite), arred(pos.x), arred(pos.y), arred(pos.z), raio, quem(src), os.time() })
    if not id then return false, 'Não consegui salvar o radar no banco.' end
    recarregar()
    return true, ('Radar "%s" criado onde você está.'):format(nome), id
end

function acoes.editar(src, id, d)
    local campos = {}
    if d.nome ~= nil then
        local nome = texto(d.nome, 60)
        if nome == '' then return false, 'O nome não pode ficar vazio.' end
        campos.nome = nome
    end
    if d.limite ~= nil then
        local limite = numero(d.limite, 10, 400)
        if not limite then return false, 'Limite de velocidade inválido.' end
        campos.limite = math.floor(limite)
    end
    if d.raio ~= nil then
        local raio = numero(d.raio, 3, 300)
        if not raio then return false, 'Raio inválido.' end
        campos.raio = raio
    end
    if d.ativo ~= nil then campos.ativo = d.ativo == true and 1 or 0 end
    if d.margem ~= nil then
        local m = numero(d.margem, 10, 90)
        if m then campos.margem = math.floor(m) end
    end
    if not next(campos) then return false, 'Nada para salvar.' end
    salvarCampos(id, src, campos)
    recarregar()
    return true, 'Radar salvo.'
end

function acoes.desenharArea(src, id, d)
    local pontos = type(d.pontos) == 'table' and d.pontos or {}
    if #pontos < 3 or #pontos > 60 then return false, 'A área precisa de 3 a 60 cantos.' end
    local limpos = {}
    for i, p in ipairs(pontos) do
        local x, y, z = tonumber(p.x), tonumber(p.y), tonumber(p.z)
        if not (x and y and z) then return false, 'Canto inválido.' end
        limpos[i] = { x = arred(x), y = arred(y), z = arred(z) }
    end
    local c = Area.centro(limpos)
    salvarCampos(id, src, { pontos = json.encode(limpos), cx = arred(c.x), cy = arred(c.y), cz = arred(c.z) })
    recarregar()
    return true, ('Área do radar salva (%d cantos).'):format(#limpos)
end

function acoes.circulo(src, id)
    local r = Radares[id]
    if not Area.ehPoligono(r) then return false, 'Esse radar já é um círculo.' end
    local raio = math.max(5.0, math.floor(Area.raioMaximo(r.pontos, r.centro)))
    salvarCampos(id, src, { pontos = nil, raio = raio })
    MySQL.update.await('UPDATE m_radarmulta_radares SET pontos = NULL WHERE id = ?', { id })
    recarregar()
    return true, ('Área apagada: agora é um círculo de %dm de raio.'):format(raio)
end

function acoes.moverAqui(src, id)
    local r = Radares[id]
    if Area.ehPoligono(r) then return false, 'Radar com área desenhada: use "Redesenhar a área".' end
    local pos = GetEntityCoords(GetPlayerPed(src))
    salvarCampos(id, src, { cx = arred(pos.x), cy = arred(pos.y), cz = arred(pos.z) })
    recarregar()
    return true, 'Centro do radar movido para onde você está.'
end

function acoes.sentido(src, id, d)
    if d.heading == false then
        MySQL.update.await('UPDATE m_radarmulta_radares SET heading = NULL WHERE id = ?', { id })
        salvarCampos(id, src, {})
        recarregar()
        return true, 'O radar agora multa nos dois sentidos.'
    end
    local h = numero(d.heading, 0, 360)
    if not h then return false, 'Direção inválida.' end
    salvarCampos(id, src, { heading = math.floor(h * 10 + 0.5) / 10 })
    recarregar()
    return true, ('O radar agora só multa quem passa nessa direção (%.0f°).'):format(h)
end

function acoes.isencoes(src, _, d)
    local jobs, lista = {}, {}
    for _, nome in ipairs(type(d.jobs) == 'table' and d.jobs or {}) do
        nome = texto(nome, 50)
        if nome ~= '' and not jobs[nome] then
            jobs[nome] = true
            lista[#lista + 1] = nome
        end
    end
    local soEmServico = d.soEmServico == true
    MySQL.query.await('REPLACE INTO m_radarmulta_ajustes (chave, valor) VALUES (?, ?), (?, ?)',
        { 'jobsIsentos', json.encode(lista), 'soEmServico', json.encode(soEmServico) })
    Ajustes.jobsIsentos = jobs
    Ajustes.soEmServico = soEmServico
    return true, ('Isenções salvas: %d emprego(s) %s.'):format(#lista, soEmServico and 'livres da multa quando em serviço' or 'livres da multa sempre')
end

function acoes.excluir(src, id)
    MySQL.query.await('DELETE FROM m_radarmulta_radares WHERE id = ?', { id })
    recarregar()
    return true, 'Radar excluído.'
end

lib.callback.register('m_radarmulta:admin:acao', function(source, nome, id, dados)
    if not ehAdmin(source) then return false, 'Sem permissão.' end
    local fn = acoes[nome]
    if not fn then return false, 'Ação inválida.' end
    id = tonumber(id)
    if nome ~= 'criar' and nome ~= 'isencoes' and not (id and Radares[id]) then return false, 'Radar não encontrado.' end
    local ok, msg, extra = fn(source, id, type(dados) == 'table' and dados or {})
    if ok and Config.Debug then
        print(('[m_radarmulta] admin %s: %s (radar %s) -> %s'):format(quem(source), nome, tostring(id or extra), msg))
    end
    return ok, msg, extra
end)

-------------------------------------------------------------------------------
-- /radares e registro no mri_Qadmin
-------------------------------------------------------------------------------

lib.addCommand('radares', {
    help = 'Abre o painel de radares de velocidade',
    restricted = 'group.admin',
}, function(source)
    if GetResourceState('mri_Qadmin') == 'started' then
        local ok = pcall(function() return exports.mri_Qadmin:OpenPluginForPlayer(source, PLUGIN_ID) end)
        if ok then return end
    end
    TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = 'O painel do admin (mri_Qadmin) não está ligado.' })
end)

local function registrarPlugin()
    if GetResourceState('mri_Qadmin') ~= 'started' then return end
    local ok, err = pcall(function()
        return exports.mri_Qadmin:RegisterPlugin({
            id = PLUGIN_ID,
            label = 'Radares',
            icon = 'camera',
            resource = GetCurrentResourceName(),
            htmlPath = 'html/index.html',
            requiredPerms = { ACE },
            description = 'Radares de velocidade: criar, desenhar a área, limite e sentido',
            category = 'access',
        })
    end)
    if not ok then lib.print.warn(('não consegui registrar no mri_Qadmin: %s'):format(err)) end
end

-- pluginsReady cobre o Qadmin reiniciando; o onResourceStart cobre este script ligando depois
AddEventHandler('mri_Qadmin:server:pluginsReady', registrarPlugin)
AddEventHandler('onResourceStart', function(res)
    if res == GetCurrentResourceName() or res == 'mri_Qadmin' then
        SetTimeout(500, registrarPlugin)
    end
end)
