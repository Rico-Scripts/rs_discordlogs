RSDiscordLogs = RSDiscordLogs or {}

local RESOURCE_NAME = GetCurrentResourceName()

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
    RSDiscordLogs.Send(resolveCallingResource(resourceName), normalizePayload(payload), callback)
end

local function detectedLoggingInfo(info)
    if type(info) ~= 'table' then
        return false
    end

    return info.loggingDetected == true
        or info.webhook ~= nil
        or info.webhookCode == true
        or info.bridge == true
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

    local bridgeConnected = info.bridge == true
    local maker = RSDiscordLogs.GetResourceMaker(resourceName)

    return {
        type = bridgeConnected and 'success' or 'warning',
        title = bridgeConnected and 'Logging gevonden en bridge bevestigd' or 'Logging gevonden - bridge controleren',
        description = bridgeConnected
            and ('De officiele Rico Scripts loggingservice heeft `%s` gevonden. Bridge en kanaal zijn klaar voor logs.'):format(resourceName)
            or ('De hosted loggingservice kan `%s` testen, maar de fxmanifest bridge is niet gedetecteerd.'):format(resourceName),
        fields = {
            { name = 'Script maker', value = maker ~= '' and maker or 'Onbekend', inline = true },
            { name = 'Webhook URL gevonden', value = info.webhook and 'Ja' or 'Nee', inline = true },
            { name = 'Webhookcode gevonden', value = info.webhookCode and 'Ja' or 'Nee', inline = true },
            { name = 'FXManifest bridge', value = bridgeConnected and 'Ja' or 'Nee', inline = true },
            { name = 'Logging exports', value = exportsText, inline = false },
            { name = 'Benodigde regel', value = '`@rs_discordlogs/server/intercept.lua`', inline = false },
            { name = 'Route', value = 'Hosted API -> officiele Rico Scripts bot', inline = false }
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
    if not resourceName then return nil end
    return RSDiscordLogs.CopyTable(RSDiscordLogs.ResourceInfo[resourceName])
end)

exports('RescanResource', function(resourceName)
    resourceName = resourceName or GetInvokingResource()
    if not resourceName then return nil end
    return RSDiscordLogs.CopyTable(RSDiscordLogs.ScanResource(resourceName))
end)

-- Backwards-compatible naam; v3 heeft geen lokale Gateway meer.
exports('GetGatewayStatus', function()
    return RSDiscordLogs.GetCachedRemoteStatus()
end)

exports('GetRemoteStatus', function()
    return RSDiscordLogs.GetCachedRemoteStatus()
end)

AddEventHandler('rs_discordlogs:log', function(payload, resourceName)
    handleLog(resourceName, payload)
end)

RegisterCommand('rslogs_test', function(source)
    handleLog(RESOURCE_NAME, {
        type = 'success',
        title = 'Rico Scripts hosted logging test',
        description = 'De FiveM resource, hosted API en officiele Discord bot werken samen.',
        source = source > 0 and source or nil,
        fields = {
            { name = 'Route', value = 'FiveM -> hosted API -> officiele bot', inline = false }
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
        print('[rs_discordlogs] Geen resources met webhookcode, bridge of logging-export om te testen.')
        return
    end

    print(('[rs_discordlogs] Hosted test gestart voor %s resource(s). Categorieen worden bepaald via fxmanifest author.'):format(#resources))
    local index, successes, warnings, failures = 1, 0, 0, 0

    local function nextResource()
        local resourceName = resources[index]
        if not resourceName then
            print(('[rs_discordlogs] Test klaar: %s OK, %s waarschuwing(en), %s fout.'):format(successes, warnings, failures))
            return
        end
        index = index + 1

        testDetectedResource(resourceName, function(success, result, info)
            local maker = RSDiscordLogs.GetResourceMaker(resourceName)
            local makerText = maker ~= '' and maker or 'Onbekend'

            if success and info and info.bridge then
                successes = successes + 1
                print(('[rs_discordlogs] [OK] %s -> maker=%s | hosted kanaal + bridge bevestigd via %s')
                    :format(resourceName, makerText, tostring(result)))
            elseif success then
                warnings = warnings + 1
                print(('[rs_discordlogs] [WAARSCHUWING] %s -> maker=%s | hosted kanaal werkt, bridge niet gevonden.')
                    :format(resourceName, makerText))
            else
                failures = failures + 1
                print(('[rs_discordlogs] [FOUT] %s -> %s'):format(resourceName, tostring(result)))
            end
            SetTimeout(300, nextResource)
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
            local maker = RSDiscordLogs.GetResourceMaker(resourceName)
            print(('[rs_discordlogs] [OK] %s -> %s | maker=%s | logging=%s | webhookcode=%s | bridge=%s')
                :format(
                    resourceName,
                    tostring(result),
                    maker ~= '' and maker or 'Onbekend',
                    info and detectedLoggingInfo(info) and 'ja' or 'nee',
                    info and info.webhookCode and 'ja' or 'nee',
                    info and info.bridge and 'ja' or 'nee'
                ))
        else
            print(('[rs_discordlogs] [FOUT] %s -> %s'):format(resourceName, tostring(result)))
        end
    end)
end, true)

RegisterCommand('rslogs_status', function()
    local cached = RSDiscordLogs.GetCachedRemoteStatus()
    print(('[rs_discordlogs] Cached status: %s%s'):format(
        cached.state or 'unknown',
        cached.user and cached.user ~= '' and (' | bot: ' .. cached.user) or ''
    ))

    RSDiscordLogs.GetRemoteStatus(function(success, data, statusCode, reason)
        if success then
            print(('[rs_discordlogs] Hosted API online | bot=%s | bot in guild=%s | license=%s')
                :format(
                    data.bot and data.bot.username or 'onbekend',
                    data.botInGuild == false and 'nee' or 'ja',
                    tostring(data.licenseId or 'onbekend')
                ))
            if data.inviteUrl then
                print('[rs_discordlogs] Bot invite: ' .. tostring(data.inviteUrl))
            end
        else
            print(('[rs_discordlogs] Hosted status mislukt (HTTP %s): %s'):format(statusCode, tostring(reason)))
        end
    end)
end, true)

RegisterCommand('rslogs_invite', function()
    RSDiscordLogs.GetInvite(function(success, data, statusCode, reason)
        if success and data.inviteUrl then
            print('[rs_discordlogs] Officiele Rico Scripts bot invite: ' .. tostring(data.inviteUrl))
        else
            print(('[rs_discordlogs] Invite ophalen mislukt (HTTP %s): %s'):format(statusCode, tostring(reason)))
        end
    end)
end, true)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == RESOURCE_NAME then return end

    RSDiscordLogs.ClearResourceMakerCache(resourceName)

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
    if resourceName == RESOURCE_NAME then return end

    if Config.AutomaticLogs.ResourceLifecycle then
        handleLog(resourceName, {
            type = 'warning',
            title = 'Resource gestopt',
            description = ('Resource `%s` is gestopt.'):format(resourceName)
        })
    end

    RSDiscordLogs.ResourceInfo[resourceName] = nil
    RSDiscordLogs.ClearResourceMakerCache(resourceName)
end)

AddEventHandler('playerConnecting', function(playerName)
    if not Config.AutomaticLogs.PlayerConnecting then return end
    handleLog('connections', {
        type = 'info',
        title = 'Speler verbindt',
        description = ('%s maakt verbinding met de server.'):format(playerName or 'Onbekend'),
        source = source
    })
end)

AddEventHandler('playerDropped', function(reason)
    if not Config.AutomaticLogs.PlayerDropped then return end
    local playerSource = source
    local playerName = GetPlayerName(playerSource) or ('ID ' .. tostring(playerSource))
    handleLog('connections', {
        type = 'warning',
        title = 'Speler verlaten',
        description = ('%s heeft de server verlaten.'):format(playerName),
        source = playerSource,
        fields = {
            { name = 'Reden', value = tostring(reason or 'Onbekend'), inline = false }
        }
    })
end)

CreateThread(function()
    Wait(750)
    RSDiscordLogs.Info('Rico Scripts hosted FiveM logger gestart.')

    if Config.Scanner.Enabled and Config.Scanner.ScanOnStart then
        RSDiscordLogs.ScanAllResources()
    end

    RSDiscordLogs.InitializeDiscord(function(success)
        if success then
            RSDiscordLogs.Debug('Hosted initialisatie afgerond.')
        end
    end)
end)
