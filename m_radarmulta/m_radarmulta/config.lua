Config = {}

Config.Debug = false -- true = loga as multas e os pagamentos no console do servidor

-- Os radares agora são criados e editados no jogo: painel do admin > Plugins > Radares (ou /radares).
-- Eles ficam salvos no banco (tabela m_radarmulta_radares).

-- Para onde vai o dinheiro quando o jogador PAGA a multa no app Multas do celular.
-- É o "holder" de uma conta do ps_banking_accounts (nome do job/gangue, ex.: 'police').
-- Se a conta não existir, o script cria vazia ao ligar.
Config.ContaDestino = 'police'

-- App "Multas" no sd-phone: é por ele que o jogador vê e paga as multas (sai do saldo do BANCO).
-- As multas NÃO vão mais pro ps-banking nem pro app de Faturas.
Config.App = {
    nome = 'Multas',
    descricao = 'Consulte e pague as multas dos seus veículos',
    desenvolvedor = 'DETRAN-SP',
    padrao = true,       -- true = já vem instalado no celular | false = baixa na loja
    historico = 50,      -- quantas multas pagas aparecem na aba Histórico
    notificar = true,    -- notificação no celular quando chega multa nova
}

-- A multa vai para o DONO do veículo (pela placa, tabela player_vehicles).
-- Veículo sem dono registrado (NPC, roubado de NPC, placa fria):
--   'ninguem'   = só bate o flash, ninguém é multado
--   'motorista' = multa quem está dirigindo
Config.SemDono = 'ninguem'

-- Tolerância antes de multar (km/h acima do limite). Ex.: limite 80 + tolerância 7 = multa a partir de 88.
Config.Tolerancia = 7

-- Valor da multa conforme o quanto passou do limite (em %), no estilo do CTB.
-- Lido de cima pra baixo: a primeira faixa em que o excesso couber é a usada.
Config.Faixas = {
    { ate = 20,        valor = 130,  nome = 'Média' },       -- até 20% acima
    { ate = 50,        valor = 195,  nome = 'Grave' },       -- de 20% a 50% acima
    { ate = math.huge, valor = 880,  nome = 'Gravíssima' },  -- mais de 50% acima
}

-- Tempo (segundos) que o MESMO radar espera antes de multar o mesmo jogador de novo
Config.Cooldown = 30

-- Empregos que NÃO levam multa do radar (quem está dirigindo).
-- AGORA SE EDITA NO PAINEL: Plugins > Radares > aba Isenções (fica salvo no banco).
-- Esta lista e o IsentoSoEmServico abaixo só valem até alguém salvar a aba Isenções pela 1ª vez.
Config.JobsIsentos = {
    police = true,     -- LSPD
    bcso = true,       -- BCSO (xerife do condado)
    sasp = true,       -- SASP (polícia estadual)
    ambulance = true,  -- EMS
}

-- true  = só fica livre da multa se estiver EM SERVIÇO (bateu ponto)
-- false = fica livre sempre, mesmo fora de serviço
Config.IsentoSoEmServico = true

-- Viaturas de emergência (classe 18) não levam multa
Config.IsentarEmergencia = true

-- Só multa quem está DIRIGINDO (passageiro não leva)
-- Classes de veículo ignoradas: 13 = bicicleta, 14 = barco, 15 = helicóptero, 16 = avião, 21 = trem
Config.ClassesIgnoradas = { [13] = true, [14] = true, [15] = true, [16] = true, [21] = true }

-- Flash na tela + som de câmera quando o radar pega
Config.Flash = true

-- Blip no mapa para os radares
Config.Blips = {
    ativo = true,
    sprite = 184,
    cor = 1,
    escala = 0.6,
    nome = 'Radar',
}

-- Altura: o radar só pega quem está até essa distância (m) acima/abaixo do chão da área.
-- Evita multar quem passa num viaduto por cima (ou por baixo) do radar.
Config.AlturaMaxima = 12.0

-- Raio padrão (m) de um radar novo criado como círculo no painel
Config.RaioPadrao = 20.0
-- Limite padrão (km/h) sugerido ao criar um radar no painel
Config.LimitePadrao = 100

-- Radares antigos (de antes do painel). São copiados pro banco UMA vez, na primeira vez que
-- o script liga com a versão nova. Depois disso esta lista não é mais usada: edite pelo painel.
Config.RadaresIniciais = {
    { nome = 'Rodovia - Vinewood Hills',        coords = vec3(1435.06, 736.72, 77.67),  raio = 20.0, limite = 100 },
    { nome = 'Rodovia - Grapeseed',             coords = vec3(2416.72, 5721.58, 45.44), raio = 30.0, limite = 100 },
    { nome = 'Great Ocean Hwy - Banham Canyon', coords = vec3(-2991.76, 412.65, 14.94), raio = 20.0, limite = 100 },
}
