fx_version 'cerulean'
game 'gta5'

author 'Rico-Scripts'
description 'Hosted centrale Discord logging voor FiveM via de officiele Rico Scripts bot.'
version '3.1.0'

lua54 'yes'

server_scripts {
    'config.lua',
    'server/utils.lua',
    'server/scanner.lua',
    'server/discord.lua',
    'server/compat.lua',
    'server/adapters.lua',
    'server/main.lua'
}
