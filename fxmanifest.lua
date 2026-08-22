fx_version 'cerulean'
game 'gta5'

author 'Rico-Scripts'
description 'Universeel centraal Discord logging-systeem voor FiveM.'
version '2.1.0'

lua54 'yes'
node_version '22'

server_scripts {
    'config.lua',
    'server/utils.lua',
    'server/scanner.lua',
    'server/discord.lua',
    'server/compat.lua',
    'server/adapters.lua',
    'server/main.lua',
    'server/gateway.js'
}
