fx_version 'cerulean'
game 'gta5'

name 'qbx_vehicleshop'
description 'Vehicle shop system for Qbox edited by MRI'
repository 'https://github.com/Qbox-project/qbx_vehicleshop'
version '2.0.0'

ox_lib 'locale'

shared_script {
    '@ox_lib/init.lua',
    '@qbx_core/modules/lib.lua',
}

client_scripts {
    '@qbx_core/modules/playerdata.lua',
    'client/vehicles.lua',
    'client/main.lua',
    'client/catalog.lua',
}

ui_page 'html/index.html'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/utils.lua',
    'server/finance.lua'
}

files {
    'client/vehicles.lua',
    'config/client.lua',
    'config/shared.lua',
    'locales/*.json',
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

lua54 'yes'
use_experimental_fxv2_oal 'yes'