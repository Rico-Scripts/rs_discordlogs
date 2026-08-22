RSDiscordLogs = RSDiscordLogs or {}

local RESOURCE_NAME = GetCurrentResourceName()

local function syncGatewayRuntimeConfig()
    local gateway = Config.Gateway or {}
    local token = RSDiscordLogs.GetSecret(
        Config.Discord.BotToken,
        Config.Discord.TokenConvar
    )

    -- De Node.js Gateway draait binnen dezelfde resource. Deze server-only
    -- runtime convars delen de Lua-config met de JS-runtime zonder de token
    -- naar clients te repliceren.
    SetConvar('rs_discordlogs_gateway_token_runtime', token or '')
    SetConvar('rs_discordlogs_gateway_enabled_runtime', gateway.Enabled == false and '0' or '1')
    SetConvar('rs_discordlogs_gateway_status_runtime', tostring(gateway.Status or 'online'))
    SetConvar('rs_discordlogs_gateway_activity_type_runtime', tostring(gateway.ActivityType or 3))
    SetConvar('rs_discordlogs_gateway_activity_runtime', tostring(gateway.ActivityName or 'FiveM Logs'))
    SetConvar('rs_discordlogs_gateway_reconnect_delay_runtime', tostring(gateway.ReconnectDelayMs or 5000))
    SetConvar('rs_discordlogs_gateway_debug_runtime', gateway.Debug == true and '1' or '0')
end

syncGatewayRuntimeConfig()

local function resolveCallingResource(explicitResource)
    if explicitResource and explicitResource ~= '' then
        return tostring(explicitResource)
    end

    local invoking = GetInvokingResource()
    if invoking and invoking ~= '' then
        return invoking
    end

    return RESOURCE_NAME
end

local function normalizePayload(payload)
    if type(payload) ~= 'table' then
        payload = {
            title = 'FiveM log',
            description = tostring(payload or '')
        }
    end

    payload.type = payload.type or payload.level or 'info'
    return payload
end

local function handleLog(resourceName, payload, callback)
    resourceName = resolveCallingResource(resourceName)
    payload = normalizePayload(payload)

    RSDiscordLogs.Send(resourceName, payload, callback)
end

exports('Log', function(payload)
    handleLog(nil, payload)
    return true
end)

exports('SendLog', function(logType, title, description, fields, playerSource)
    handleLog(nil, {
        type = logType or 'info',
        title = title or 'FiveM log',
        description = description,
        fields = fields,
        source = playerSource
    })

    return true
end)

exports('LogForResource', function(resourceName, payload)
    handleLog(resourceName, payload)
    return true
end)

exports('GetResourceInfo', function(resourceName)
    resourceName = resourceName or GetInvokingResource()
    if not resourceName then
        return nil
    end

    return RSDiscordLogs.CopyTable(RSDiscordLogs.ResourceInfo[resourceName])
end)

exports('RescanResource', function(resourceName)
    resourceName = resourceName or GetInvokingResource()
    if not resourceName then
        return nil
    end

    return RSDiscordLogs.CopyTable(RSDiscordLogs.ScanResource(resourceName))
end)

exports('GetGatewayStatus', function()
    return {
        state = GetConvar('rs_discordlogs_gateway_state', 'starting'),
        user = GetConvar('rs_discordlogs_gateway_user', '')
    }
end)

-- Server-only event. Er wordt bewust geen RegisterNetEvent gebruikt zodat
-- clients niet rechtstreeks loggingevents kunnen spoofen.
AddEventHandler('rs_discordlogs:log', function(payload, resourceName)
    handleLog(resourceName, payload)
end)

RegisterCommand('rslogs_test', function(source)
    handleLog(RESOURCE_NAME, {
        type = 'success',
        title = 'FiveM Discord Logs test',
        description = 'De centrale Discord logging werkt.',
        source = source > 0 and source or nil,
        fields = {
            {
                name = 'Status',
                value = 'Centrale bot/API route en fallback zijn getest.',
                inline = false
            }
        }
    })
end, true)

RegisterCommand('rslogs_scan', function()
    RSDiscordLogs.ScanAllResources()
end, true)

RegisterCommand('rslogs_status', function()
    local state = GetConvar('rs_discordlogs_gateway_state', 'starting')
    local botUser = GetConvar('rs_discordlogs_gateway_user', '')

    print(('[rs_discordlogs] Gateway status: %s%s'):format(
        state,
        botUser ~= '' and (' | bot: ' .. botUser) or ''
    ))
end, true)

RegisterCommand('rslogs_gateway_restart', function()
    syncGatewayRuntimeConfig()
    TriggerEvent('rs_discordlogs:gateway:restart')
    print('[rs_discordlogs] Discord Gateway restart aangevraagd.')
end, true)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == RESOURCE_NAME then
        return
    end

    if Config.Scanner.Enabled and Config.Scanner.ScanOnResourceStart then
        SetTimeout(250, function()
            RSDiscordLogs.ScanResource(resourceName)
        end)
    end

    if Config.AutomaticLogs.ResourceLifecycle then
        handleLog(resourceName, {
            type = 'info',
            title = 'Resource gestart',
            description = ('Resource `%s` is gestart.'):format(resourceName)
        })
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == RESOURCE_NAME then
        SetConvar('rs_discordlogs_gateway_token_runtime', '')
        return
    end

    if Config.AutomaticLogs.ResourceLifecycle then
        handleLog(resourceName, {
            type = 'warning',
            title = 'Resource gestopt',
            description = ('Resource `%s` is gestopt.'):format(resourceName)
        })
    end

    RSDiscordLogs.ResourceInfo[resourceName] = nil
end)

AddEventHandler('playerConnecting', function(playerName)
    if not Config.AutomaticLogs.PlayerConnecting then
        return
    end

    local playerSource = source

    handleLog('connections', {
        type = 'info',
        title = 'Speler verbindt',
        description = ('%s maakt verbinding met de server.'):format(playerName or 'Onbekend'),
        source = playerSource
    })
end)

AddEventHandler('playerDropped', function(reason)
    if not Config.AutomaticLogs.PlayerDropped then
        return
    end

    local playerSource = source
    local playerName = GetPlayerName(playerSource) or ('ID ' .. tostring(playerSource))

    handleLog('connections', {
        type = 'warning',
        title = 'Speler verlaten',
        description = ('%s heeft de server verlaten.'):format(playerName),
        source = playerSource,
        fields = {
            {
                name = 'Reden',
                value = tostring(reason or 'Onbekend'),
                inline = false
            }
        }
    })
end)

CreateThread(function()
    Wait(750)

    RSDiscordLogs.Info('Centrale FiveM logger gestart.')

    if Config.Scanner.Enabled and Config.Scanner.ScanOnStart then
        RSDiscordLogs.ScanAllResources()
    end

    RSDiscordLogs.InitializeDiscord(function()
        RSDiscordLogs.Debug('Initialisatie afgerond.')
    end)
end)
