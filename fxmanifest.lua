fx_version 'cerulean'
game 'gta5'

author 'Rico-Scripts'
description 'Universeel standalone Discord logging-systeem voor FiveM.'
version '1.0.0'

lua54 'yes'

server_scripts {
    'config.lua',
    'server/utils.lua',
    'server/scanner.lua',
    'server/discord.lua',
    'server/main.lua'
}
