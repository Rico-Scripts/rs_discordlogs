RSDiscordLogs = RSDiscordLogs or {}

local API_BASE = 'https://discord.com/api/v10'

local channelCache = {}
local channelPending = {}
local categoryId = nil
local initialized = false

local function botToken()
    return RSDiscordLogs.GetSecret(
        Config.Discord.BotToken,
        Config.Discord.TokenConvar
    )
end

local function guildId()
    return RSDiscordLogs.GetSecret(
        Config.Discord.GuildId,
        Config.Discord.GuildConvar
    )
end

local function centralWebhook()
    return RSDiscordLogs.GetSecret(
        Config.Discord.CentralWebhook,
        Config.Discord.CentralWebhookConvar
    )
end

function RSDiscordLogs.HasBotConfiguration()
    return botToken() ~= '' and guildId() ~= ''
end

local function discordRequest(method, path, body, callback, attempt)
    callback = callback or function() end
    attempt = attempt or 1

    local token = botToken()
    if token == '' then
        callback(false, nil, 0, 'missing_token')
        return
    end

    local headers = {
        ['Authorization'] = 'Bot ' .. token,
        ['Content-Type'] = 'application/json',
        ['User-Agent'] = 'rs_discordlogs/1.0.0'
    }

    local encodedBody = body and json.encode(body) or ''

    PerformHttpRequest(API_BASE .. path, function(statusCode, responseBody, responseHeaders)
        local decoded = RSDiscordLogs.SafeJsonDecode(responseBody)

        if statusCode == 429 and attempt < 4 then
            local retryAfter = decoded and tonumber(decoded.retry_after) or 1
            local delay = math.max(250, math.floor((retryAfter or 1) * 1000))

            RSDiscordLogs.Debug(('Discord rate limit, opnieuw proberen over %sms.'):format(delay))

            SetTimeout(delay, function()
                discordRequest(method, path, body, callback, attempt + 1)
            end)

            return
        end

        if (statusCode == 0 or statusCode >= 500) and attempt < 3 then
            SetTimeout(750 * attempt, function()
                discordRequest(method, path, body, callback, attempt + 1)
            end)

            return
        end

        local success = statusCode >= 200 and statusCode < 300
        callback(success, decoded, statusCode, success and nil or responseBody, responseHeaders)
    end, method, encodedBody, headers)
end

local function webhookRequest(webhookUrl, embed, content, callback)
    callback = callback or function() end

    if not webhookUrl or webhookUrl == '' then
        callback(false, 0)
        return
    end

    local payload = {
        username = Config.Discord.BotName or 'RS Discord Logs',
        avatar_url = Config.Discord.AvatarUrl ~= '' and Config.Discord.AvatarUrl or nil,
        content = content ~= '' and content or nil,
        embeds = { embed }
    }

    PerformHttpRequest(webhookUrl, function(statusCode)
        callback(statusCode >= 200 and statusCode < 300, statusCode)
    end, 'POST', json.encode(payload), {
        ['Content-Type'] = 'application/json'
    })
end

local function channelNameForResource(resourceName)
    if not Config.Routing.UseResourceChannels then
        return RSDiscordLogs.SanitizeChannelName(Config.Discord.GeneralChannel)
    end

    local override = Config.Routing.ChannelOverrides
        and Config.Routing.ChannelOverrides[resourceName]

    local baseName = override or resourceName or Config.Discord.GeneralChannel
    local prefix = Config.Discord.ChannelPrefix or ''

    return RSDiscordLogs.SanitizeChannelName(prefix .. baseName)
end

local function refreshChannels(callback)
    callback = callback or function() end

    local guild = guildId()
    if guild == '' then
        callback(false)
        return
    end

    discordRequest('GET', '/guilds/' .. guild .. '/channels', nil, function(success, channels, statusCode)
        if not success or type(channels) ~= 'table' then
            RSDiscordLogs.Warn(('Discord kanalen ophalen mislukt (HTTP %s).'):format(statusCode))
            callback(false)
            return
        end

        channelCache = {}

        local wantedCategoryName = tostring(Config.Discord.CategoryName or 'FiveM Logs'):lower()
        local configuredCategoryId = tostring(Config.Discord.CategoryId or '')

        if configuredCategoryId ~= '' then
            categoryId = configuredCategoryId
        else
            categoryId = nil
        end

        for _, channel in ipairs(channels) do
            if channel.type == 4 and not categoryId then
                if tostring(channel.name or ''):lower() == wantedCategoryName then
                    categoryId = channel.id
                end
            elseif channel.type == 0 and channel.name then
                channelCache[tostring(channel.name):lower()] = {
                    id = channel.id,
                    parent_id = channel.parent_id
                }
            end
        end

        initialized = true
        callback(true)
    end)
end

local function ensureCategory(callback)
    callback = callback or function() end

    if categoryId and categoryId ~= '' then
        callback(true, categoryId)
        return
    end

    if not Config.Routing.AutoCreateChannels then
        callback(false, nil)
        return
    end

    local guild = guildId()
    if guild == '' then
        callback(false, nil)
        return
    end

    discordRequest('POST', '/guilds/' .. guild .. '/channels', {
        name = Config.Discord.CategoryName or 'FiveM Logs',
        type = 4
    }, function(success, created, statusCode)
        if not success or type(created) ~= 'table' or not created.id then
            RSDiscordLogs.Warn(('Discord categorie aanmaken mislukt (HTTP %s).'):format(statusCode))
            callback(false, nil)
            return
        end

        categoryId = created.id
        RSDiscordLogs.Info(('Discord categorie aangemaakt: %s'):format(Config.Discord.CategoryName or 'FiveM Logs'))
        callback(true, categoryId)
    end)
end

local function flushPending(channelName, success, channelId)
    local pending = channelPending[channelName] or {}
    channelPending[channelName] = nil

    for _, callback in ipairs(pending) do
        callback(success, channelId)
    end
end

local function ensureChannel(resourceName, callback)
    callback = callback or function() end

    if not RSDiscordLogs.HasBotConfiguration() then
        callback(false, nil)
        return
    end

    local wantedName = channelNameForResource(resourceName)
    local cached = channelCache[wantedName]

    if cached and cached.id then
        callback(true, cached.id)
        return
    end

    if channelPending[wantedName] then
        channelPending[wantedName][#channelPending[wantedName] + 1] = callback
        return
    end

    channelPending[wantedName] = { callback }

    local function createOrResolve()
        local existing = channelCache[wantedName]
        if existing and existing.id then
            flushPending(wantedName, true, existing.id)
            return
        end

        if not Config.Routing.AutoCreateChannels then
            flushPending(wantedName, false, nil)
            return
        end

        ensureCategory(function(categorySuccess, parentId)
            if not categorySuccess then
                flushPending(wantedName, false, nil)
                return
            end

            local guild = guildId()

            discordRequest('POST', '/guilds/' .. guild .. '/channels', {
                name = wantedName,
                type = 0,
                parent_id = parentId,
                topic = Config.Discord.ChannelTopic or 'Automatisch aangemaakt door rs_discordlogs.'
            }, function(success, created, statusCode)
                if not success or type(created) ~= 'table' or not created.id then
                    RSDiscordLogs.Warn(('Kanaal #%s aanmaken mislukt (HTTP %s).')
                        :format(wantedName, statusCode))
                    flushPending(wantedName, false, nil)
                    return
                end

                channelCache[wantedName] = {
                    id = created.id,
                    parent_id = created.parent_id
                }

                RSDiscordLogs.Info(('Discord kanaal aangemaakt: #%s'):format(wantedName))
                flushPending(wantedName, true, created.id)
            end)
        end)
    end

    if not initialized then
        refreshChannels(function()
            createOrResolve()
        end)
    else
        createOrResolve()
    end
end

local function alertContent(logLevel)
    if not Config.Discord.MentionRoleOnError then
        return ''
    end

    if logLevel ~= 'error' and logLevel ~= 'security' then
        return ''
    end

    local roleId = tostring(Config.Discord.AlertRoleId or '')
    if roleId == '' then
        return ''
    end

    return '<@&' .. roleId .. '>'
end

function RSDiscordLogs.BuildEmbed(resourceName, payload)
    payload = type(payload) == 'table' and payload or {}

    local logType = tostring(payload.type or payload.level or 'info'):lower()
    local color = tonumber(payload.color)
        or (Config.Embed.Colors and Config.Embed.Colors[logType])
        or Config.Embed.DefaultColor
        or 3447003

    local fields = RSDiscordLogs.NormalizeFields(payload.fields, 17)

    local player = RSDiscordLogs.GetPlayerData(payload.source)
    if player then
        table.insert(fields, 1, {
            name = 'Speler',
            value = ('%s (`%s`)'):format(player.name or 'Onbekend', player.source),
            inline = true
        })

        if Config.Embed.IncludePlayerIdentifiers then
            local identifiers = player.identifiers or {}

            if identifiers.discord then
                fields[#fields + 1] = {
                    name = 'Discord',
                    value = '<@' .. identifiers.discord .. '>',
                    inline = true
                }
            end

            if identifiers.license then
                fields[#fields + 1] = {
                    name = 'License',
                    value = '`license:' .. RSDiscordLogs.Truncate(identifiers.license, 64) .. '`',
                    inline = false
                }
            end

            if identifiers.fivem then
                fields[#fields + 1] = {
                    name = 'FiveM',
                    value = '`fivem:' .. RSDiscordLogs.Truncate(identifiers.fivem, 64) .. '`',
                    inline = true
                }
            end
        end
    end

    if Config.Embed.IncludeResource then
        fields[#fields + 1] = {
            name = 'Resource',
            value = '`' .. RSDiscordLogs.Truncate(resourceName or 'unknown', 90) .. '`',
            inline = true
        }
    end

    fields[#fields + 1] = {
        name = 'Type',
        value = '`' .. RSDiscordLogs.Truncate(logType, 50) .. '`',
        inline = true
    }

    fields = RSDiscordLogs.NormalizeFields(fields)

    local footerText = Config.Embed.Footer or 'RS Discord Logs'
    if payload.footer and payload.footer ~= '' then
        footerText = tostring(payload.footer)
    end

    local embed = {
        title = RSDiscordLogs.Truncate(payload.title or 'FiveM log', 256),
        description = payload.description and RSDiscordLogs.Truncate(payload.description, 4096) or nil,
        color = color,
        fields = fields,
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        footer = {
            text = RSDiscordLogs.Truncate(footerText, 2048)
        }
    }

    if payload.thumbnail and payload.thumbnail ~= '' then
        embed.thumbnail = { url = tostring(payload.thumbnail) }
    end

    if payload.image and payload.image ~= '' then
        embed.image = { url = tostring(payload.image) }
    end

    return embed, logType
end

local function sendViaBot(resourceName, embed, logLevel, callback)
    callback = callback or function() end

    if not RSDiscordLogs.HasBotConfiguration() then
        callback(false, 'bot_not_configured')
        return
    end

    ensureChannel(resourceName, function(channelSuccess, channelId)
        if not channelSuccess or not channelId then
            callback(false, 'channel_unavailable')
            return
        end

        local content = alertContent(logLevel)

        discordRequest('POST', '/channels/' .. channelId .. '/messages', {
            content = content ~= '' and content or nil,
            embeds = { embed }
        }, function(success, _, statusCode)
            if success then
                callback(true, 'bot')
                return
            end

            -- Cache kan stale zijn als een kanaal handmatig is verwijderd.
            if statusCode == 404 then
                channelCache[channelNameForResource(resourceName)] = nil
                initialized = false
            end

            callback(false, 'bot_http_' .. tostring(statusCode))
        end)
    end)
end

local function sendViaResourceWebhook(resourceName, embed, logLevel, callback)
    local webhook = RSDiscordLogs.GetResourceWebhook(resourceName)

    if not webhook or webhook == '' then
        callback(false, 'resource_webhook_missing')
        return
    end

    webhookRequest(webhook, embed, alertContent(logLevel), function(success, statusCode)
        callback(success, success and 'resource_webhook' or ('resource_webhook_http_' .. tostring(statusCode)))
    end)
end

local function sendViaCentralWebhook(_, embed, logLevel, callback)
    local webhook = centralWebhook()

    if webhook == '' then
        callback(false, 'central_webhook_missing')
        return
    end

    webhookRequest(webhook, embed, alertContent(logLevel), function(success, statusCode)
        callback(success, success and 'central_webhook' or ('central_webhook_http_' .. tostring(statusCode)))
    end)
end

local routes = {
    bot = sendViaBot,
    resource_webhook = sendViaResourceWebhook,
    central_webhook = sendViaCentralWebhook
}

function RSDiscordLogs.Send(resourceName, payload, callback)
    callback = callback or function() end
    resourceName = resourceName or 'unknown'

    local embed, logLevel = RSDiscordLogs.BuildEmbed(resourceName, payload)
    local priority = Config.Routing.Priority or {
        'bot',
        'resource_webhook',
        'central_webhook'
    }

    local index = 1
    local failures = {}

    local function tryNext()
        local routeName = priority[index]
        index = index + 1

        if not routeName then
            RSDiscordLogs.Warn(('Log van %s kon niet worden verstuurd (%s).')
                :format(resourceName, table.concat(failures, ', ')))
            callback(false, failures)
            return
        end

        local route = routes[routeName]

        if not route then
            failures[#failures + 1] = routeName .. ':unknown_route'
            tryNext()
            return
        end

        route(resourceName, embed, logLevel, function(success, result)
            if success then
                RSDiscordLogs.Debug(('Log van %s verstuurd via %s.'):format(resourceName, result))
                callback(true, result)
                return
            end

            failures[#failures + 1] = routeName .. ':' .. tostring(result)
            tryNext()
        end)
    end

    tryNext()
end

function RSDiscordLogs.InitializeDiscord(callback)
    callback = callback or function() end

    if not RSDiscordLogs.HasBotConfiguration() then
        RSDiscordLogs.Warn('Geen Discord BotToken/GuildId ingesteld; bot-route wordt overgeslagen.')
        callback(false)
        return
    end

    refreshChannels(function(success)
        if not success then
            callback(false)
            return
        end

        ensureCategory(function(categorySuccess)
            if categorySuccess then
                RSDiscordLogs.Info('Discord botverbinding gereed.')
            end

            callback(categorySuccess)
        end)
    end)
end
