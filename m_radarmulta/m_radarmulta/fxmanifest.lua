fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'm_radarmulta'
description 'Radar de velocidade + app Multas no celular (sd-phone) pra pagar as multas - Magrao Atitude'
version '3.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/area.lua',
}

client_scripts {
    'client/main.lua',
    'client/app.lua', -- app Multas do celular
}

-- qbx_vehicles é usado só no server; NÃO pode ir em dependencies (o client não tem ele e falha ao conectar)
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/radares.lua', -- radares no banco + painel do admin
    'server/main.lua',    -- multas + pagamento pelo app
}

-- página vazia: só existe pra o app do celular conseguir chamar os callbacks deste resource
ui_page 'html/nui.html'

files {
    'html/nui.html',
    'html/index.html', -- aba no painel do mri_Qadmin (Plugins > Radares)
    'html/app.html',   -- app Multas do celular
    'html/icon.svg',
}

dependencies {
    'ox_lib',
    'qbx_core',
    'ps-banking',
    'sd-phone',
}
