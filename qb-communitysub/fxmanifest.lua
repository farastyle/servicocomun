fx_version 'cerulean'

game 'gta5'

lua54 'yes'

author 'Community Service System by OpenAI Codex'
description 'Substitui prisão por serviço comunitário configurável para servidores QBCore'
version '1.0.0'

shared_scripts {
    '@qb-core/shared/locale.lua',
    'config.lua'
}

client_scripts {
    'client.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua'
}

provides {'community_service'}
