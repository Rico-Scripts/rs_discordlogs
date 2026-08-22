RSDiscordLogs = RSDiscordLogs or {}

local INSTALL_KVP = 'rs_discordlogs:install_id'
local STATE_CONVAR = 'rs_discordlogs_remote_state'
local BOT_CONVAR = 'rs_discordlogs_remote_bot'

local makerCache = {}
local generalResources = {
    ['connections'] = true,
    ['algemeen'] = true,
    ['resources'] = true,
    ['server'] = true,
    ['rs_discordlogs'] = true
}

local function trim(value)
    value = tostring(value or '')
    return value:match('^%s*(.-)%s*$') or ''
end

local function remoteConfig()
    return Config.Remote or {}
end

local function apiBaseUrl()
    local remote = remoteConfig()
    local value = RSDiscordLogs.GetSecret(remote.ApiBaseUrl or '', remote.ApiUrlConvar or 'rs_discordlogs_api_url')
    return tostring(value or ''):gsub('/+$', '')
end

local function licenseKey()
    local remote = remoteConfig()
    return RSDiscordLogs.GetSecret(remote.LicenseKey or '', remote.LicenseConvar or 'rs_discordlogs_license')
end

local function guildId()
    local remote = remoteConfig()
    return RSDiscordLogs.GetSecret(remote.GuildId or '', remote.GuildConvar or 'rs_discordlogs_guild')
end

local function serverName()
    return tostring(GetConvar('sv_hostname', 'FiveM server'))
end

local function setState(state, bot)
    SetConvar(STATE_CONVAR, tostring(state or 'unknown'))
    if bot ~= nil then
        SetConvar(BOT_CONVAR, tostring(bot or ''))
    end
end

local function urlEncode(value)
    value = tostring(value or '')
    return value:gsub('([^%w%-_%.~])', function(char)
        return ('%%%02X'):format(string.byte(char))
    end)
end

local function generateInstallId()
    math.randomseed(os.time() + (GetGameTimer and GetGameTimer() or 0))
    local parts = {}
    for index = 1, 6 do
        parts[index] = ('%08x'):format(math.random(0, 0x7fffffff))
    end
    return table.concat(parts, '')
end

function RSDiscordLogs.GetInstallId()
    local value = GetResourceKvpString(INSTALL_KVP)
    if value and value ~= '' then
        return value
    end

    value = generateInstallId()
    SetResourceKvp(INSTALL_KVP, value)
    return value
end

function RSDiscordLogs.HasRemoteConfiguration()
    return apiBaseUrl() ~= '' and licenseKey() ~= '' and guildId() ~= ''
end

-- Bepaalt de maker rechtstreeks uit de metadata van het fxmanifest.lua.
-- `author` is de standaard FiveM metadata. Voor enkele third-party resources
-- proberen we als nette fallback ook `creator` en `developer`.
function RSDiscordLogs.GetResourceMaker(resourceName)
    resourceName = trim(resourceName)

    if resourceName == '' or generalResources[resourceName:lower()] then
        return ''
    end

    if makerCache[resourceName] ~= nil then
        return makerCache[resourceName]
    end

    local maker = ''
    local metadataKeys = { 'author', 'creator', 'developer' }

    for _, metadataKey in ipairs(metadataKeys) do
        local ok, value = pcall(GetResourceMetadata, resourceName, metadataKey, 0)
        value = ok and trim(value) or ''

        if value ~= '' then
            maker = value
            break
        end
    end

    makerCache[resourceName] = maker
    return maker
end

function RSDiscordLogs.ClearResourceMakerCache(resourceName)
    if resourceName and resourceName ~= '' then
        makerCache[tostring(resourceName)] = nil
    else
        makerCache = {}
    end
end

local function safeDecode(body)
    return RSDiscordLogs.SafeJsonDecode(body) or {}
end

local function request(path, method, data, callback, options, attempt)
    callback = callback or function() end
    options = options or {}
    attempt = attempt or 1

    local base = apiBaseUrl()
    if base == '' then
        callback(false, { error = 'missing_api_url' }, 0, 'missing_api_url')
        return
    end

    local headers = {
        ['Content-Type'] = 'application/json',
        ['User-Agent'] = 'rs_discordlogs/3.1.0'
    }

    if options.auth ~= false then
        local key = licenseKey()
        if key == '' then
            callback(false, { error = 'missing_license' }, 0, 'missing_license')
            return
        end
        headers['Authorization'] = 'Bearer ' .. key
    end

    local body = ''
    if data ~= nil then
        body = json.encode(data)
    end

    PerformHttpRequest(base .. path, function(statusCode, responseBody)
        local decoded = safeDecode(responseBody)
        local success = statusCode >= 200 and statusCode < 300

        if success then
            callback(true, decoded, statusCode, nil)
            return
        end

        local remote = remoteConfig()
        local maxAttempts = math.max(1, tonumber(remote.RetryAttempts) or 3)

        if statusCode == 429 and attempt < maxAttempts then
            local delay = tonumber(decoded.retryAfterMs) or 1000
            SetTimeout(math.max(250, delay), function()
                request(path, method, data, callback, options, attempt + 1)
            end)
            return
        end

        if (statusCode == 0 or statusCode >= 500) and attempt < maxAttempts then
            local delay = math.max(250, (tonumber(remote.RetryDelayMs) or 750) * attempt)
            SetTimeout(delay, function()
                request(path, method, data, callback, options, attempt + 1)
            end)
            return
        end

        callback(false, decoded, statusCode, decoded.error or ('http_' .. tostring(statusCode)))
    end, method or 'GET', body, headers)
end

local function playerPayload(source)
    local player = RSDiscordLogs.GetPlayerData(source)
    if not player then
        return nil
    end

    local result = {
        source = player.source,
        name = player.name,
        identifiers = {}
    }

    if not Config.Payload or Config.Payload.IncludePlayerIdentifiers ~= false then
        for key, value in pairs(player.identifiers or {}) do
            result.identifiers[key] = value
        end
    end

    return result
end

local function preparePayload(payload)
    payload = type(payload) == 'table' and RSDiscordLogs.CopyTable(payload) or {
        type = 'info',
        title = 'FiveM log',
        description = tostring(payload or '')
    }

    payload.type = payload.type or payload.level or 'info'
    if payload.source then
        payload.player = playerPayload(payload.source)
        payload.source = nil
    end

    if payload.fields then
        payload.fields = RSDiscordLogs.NormalizeFields(payload.fields)
    end

    return payload
end

local function commonBody(resourceName, payload)
    resourceName = tostring(resourceName or 'algemeen')

    return {
        guildId = guildId(),
        installId = RSDiscordLogs.GetInstallId(),
        serverName = serverName(),
        resource = resourceName,
        maker = RSDiscordLogs.GetResourceMaker(resourceName),
        payload = preparePayload(payload)
    }
end

function RSDiscordLogs.Send(resourceName, payload, callback)
    callback = callback or function() end

    request('/v1/log', 'POST', commonBody(resourceName, payload), function(success, decoded, statusCode, reason)
        if success then
            local botName = decoded.bot and decoded.bot.username or ''
            setState('online', botName)
            callback(true, 'official_bot')
            return
        end

        if reason == 'invalid_license' or reason == 'license_disabled' or reason == 'license_expired'
            or reason == 'guild_mismatch' or reason == 'install_mismatch'
        then
            setState('license_error')
            RSDiscordLogs.Warn(('Hosted logging geweigerd: %s.'):format(tostring(reason)))
        elseif reason == 'bot_not_in_guild' then
            setState('bot_not_in_guild')
            if decoded.inviteUrl then
                RSDiscordLogs.Warn('Officiele bot ontbreekt in Discord. Invite: ' .. tostring(decoded.inviteUrl))
            end
        else
            setState('error')
        end

        callback(false, reason or ('http_' .. tostring(statusCode)))
    end)
end

function RSDiscordLogs.InitializeDiscord(callback)
    callback = callback or function() end

    if not RSDiscordLogs.HasRemoteConfiguration() then
        setState('missing_config')
        RSDiscordLogs.Warn('Hosted logging niet compleet ingesteld. Vul rs_discordlogs_api_url, rs_discordlogs_license en rs_discordlogs_guild in.')
        callback(false, 'missing_config')
        return
    end

    setState('connecting')

    request('/v1/register', 'POST', {
        guildId = guildId(),
        installId = RSDiscordLogs.GetInstallId(),
        serverName = serverName()
    }, function(success, decoded, _, reason)
        if success then
            local botName = decoded.bot and decoded.bot.username or 'Rico Scripts bot'
            setState('online', botName)
            RSDiscordLogs.Info(('Hosted logging gereed via officiele bot %s.'):format(botName))
            callback(true, decoded)
            return
        end

        if reason == 'bot_not_in_guild' and decoded.inviteUrl then
            setState('bot_not_in_guild')
            RSDiscordLogs.Warn('Nodig de officiele logging bot uit: ' .. tostring(decoded.inviteUrl))
        else
            setState(reason or 'error')
            RSDiscordLogs.Warn(('Hosted logging initialisatie mislukt: %s.'):format(tostring(reason)))
        end

        callback(false, decoded)
    end)
end

function RSDiscordLogs.GetRemoteStatus(callback)
    callback = callback or function() end
    local query = ('?guildId=%s&installId=%s'):format(
        urlEncode(guildId()),
        urlEncode(RSDiscordLogs.GetInstallId())
    )

    request('/v1/status' .. query, 'GET', nil, function(success, decoded, statusCode, reason)
        if success then
            local botName = decoded.bot and decoded.bot.username or ''
            setState(decoded.botInGuild == false and 'bot_not_in_guild' or 'online', botName)
        end
        callback(success, decoded, statusCode, reason)
    end)
end

function RSDiscordLogs.GetInvite(callback)
    callback = callback or function() end
    request('/v1/info?guildId=' .. urlEncode(guildId()), 'GET', nil, callback, { auth = false })
end

function RSDiscordLogs.GetCachedRemoteStatus()
    return {
        state = GetConvar(STATE_CONVAR, 'starting'),
        user = GetConvar(BOT_CONVAR, '')
    }
end
