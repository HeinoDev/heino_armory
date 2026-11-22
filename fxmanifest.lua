fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Heino'
version '1.0.0'

shared_script '@ox_lib/init.lua'
client_script 'client/*.lua'
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/*.lua',
}

files {
    'config.lua',
    'locales/*.json',
    'ped.json',
    'util/client.lua',
}

dependencies {
    '/onesync',
    'ox_lib',
    'oxmysql',
    'ox_inventory',
    'ox_target',
    'heino_lib',
}
