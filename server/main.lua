RSDiscordLogs = RSDiscordLogs or {}

local RESOURCE_NAME = GetCurrentResourceName()

local function syncGatewayRuntimeConfig()
    local gateway = Config.Gateway or {}
    local token = RSDiscordLogs.GetSecret(
        Config.Discord.BotToken,
        Config.Discord.TokenConvar
    )

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

local function detectedLoggingInfo(info)
    if type(info) ~= 'table' then
        return false
    end

    return info.webhook ~= nil
        or (type(info.exports) == 'table' and #info.exports > 0)
end

local function detectedResources()
    local resources = {}

    for resourceName, info in pairs(RSDiscordLogs.ResourceInfo or {}) do
        if detectedLoggingInfo(info) then
            resources[#resources + 1] = resourceName
        end
    end

    table.sort(resources)
    return resources
end

local function confirmationPayload(resourceName, info)
    local exportsText = 'Geen'

    if type(info.exports) == 'table' and #info.exports > 0 then
        exportsText = table.concat(info.exports, ', ')
    end

    return {
        type = 'success',
        title = 'Logging gevonden en kanaal bevestigd',
        description = ('De centrale FiveM logger heeft logging voor `%s` gevonden. Dit kanaal is aangemaakt of gecontroleerd en is klaar voor logs.'):format(resourceName),
        fields = {
            {
                name = 'Webhook gedetecteerd',
                value = info.webhook and 'Ja' or 'Nee',
                inline = true
            },
            {
                name = 'Logging exports',
                value = exportsText,
                inline = false
            },
            {
                name = 'Route',
                value = 'Centrale bot / rs_discordlogs',
                inline = false
            }
        }
    }
end

local function testDetectedResource(resourceName, callback)
    callback = callback or function() end

    local info = RSDiscordLogs.ScanResource(resourceName)
    if not info then
        callback(false, 'resource_not_started_or_ignored')
        return
    end

    handleLog(resourceName, confirmationPayload(resourceName, info), function(success, result)
        callback(success, result, info)
    end)
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

RegisterCommand('rslogs_test_webhooks', function()
    RSDiscordLogs.ScanAllResources()

    local resources = detectedResources()
    if #resources == 0 then
        print('[rs_discordlogs] Geen resources met gevonden webhook/logging-export om te testen.')
        return
    end

    print(('[rs_discordlogs] Test gestart voor %s resource(s). Kanalen worden automatisch aangemaakt/gecontroleerd.'):format(#resources))

    local index = 1
    local successes = 0
    local failures = 0

    local function nextResource()
        local resourceName = resources[index]
        if not resourceName then
            print(('[rs_discordlogs] Test klaar: %s OK, %s fout.'):format(successes, failures))
            return
        end

        index = index + 1

        testDetectedResource(resourceName, function(success, result)
            if success then
                successes = successes + 1
                print(('[rs_discordlogs] [OK] %s -> kanaal bevestigd via %s'):format(resourceName, tostring(result)))
            else
                failures = failures + 1
                print(('[rs_discordlogs] [FOUT] %s -> %s'):format(resourceName, tostring(result)))
            end

            SetTimeout(250, nextResource)
        end)
    end

    nextResource()
end, true)

RegisterCommand('rslogs_test_resource', function(_, args)
    local resourceName = args and args[1] or nil

    if not resourceName or resourceName == '' then
        print('[rs_discordlogs] Gebruik: rslogs_test_resource <resource>')
        return
    end

    testDetectedResource(resourceName, function(success, result, info)
        if success then
            local found = info and detectedLoggingInfo(info) and 'logging gevonden' or 'geen logging-signaal gevonden'
            print(('[rs_discordlogs] [OK] %s -> kanaal bevestigd via %s (%s).'):format(resourceName, tostring(result), found))
        else
            print(('[rs_discordlogs] [FOUT] %s -> %s'):format(resourceName, tostring(result)))
        end
    end)
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
