RSDiscordLogs = RSDiscordLogs or {}

local API_BASE = 'https://discord.com/api/v10'
local BOT_TOKEN_CONVAR = 'rs_discordlogs_token'
local FIXED_BOT_KVP = 'rs_discordlogs:fixed_bot_user_id'
local FIXED_BOT_RUNTIME_CONVAR = 'rs_discordlogs_fixed_bot_id_runtime'

local channelCache = {}
local channelPending = {}
local categoryCache = {}
local categoryPending = {}
local initialized = false

local fixedBotState = 'unknown'
local fixedBotUser = nil
local fixedBotPending = nil

local function botToken()
    return GetConvar(BOT_TOKEN_CONVAR, '')
end

local function guildId()
    local configured = Config.Discord and Config.Discord.GuildId or ''
    local convarName = Config.Discord and Config.Discord.GuildConvar or 'rs_discordlogs_guild'
    return RSDiscordLogs.GetSecret(configured, convarName)
end

local function centralWebhook()
    local configured = Config.Discord and Config.Discord.CentralWebhook or ''
    local convarName = Config.Discord and Config.Discord.CentralWebhookConvar or 'rs_discordlogs_webhook'
    return RSDiscordLogs.GetSecret(configured, convarName)
end

function RSDiscordLogs.HasBotConfiguration()
    return botToken() ~= '' and guildId() ~= ''
end

function RSDiscordLogs.GetFixedBotId()
    return GetResourceKvpString(FIXED_BOT_KVP) or ''
end

function RSDiscordLogs.ResetFixedBotValidation()
    fixedBotState = 'unknown'
    fixedBotUser = nil
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
        ['User-Agent'] = 'rs_discordlogs/2.1.0'
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

local function completeFixedBotValidation(success, reason, user)
    local pending = fixedBotPending or {}
    fixedBotPending = nil

    for _, callback in ipairs(pending) do
        callback(success, reason, user)
    end
end

function RSDiscordLogs.EnsureFixedBot(callback)
    callback = callback or function() end

    if fixedBotState == 'valid' and fixedBotUser then
        callback(true, 'fixed_bot', fixedBotUser)
        return
    end

    if fixedBotState == 'invalid' then
        callback(false, 'wrong_bot')
        return
    end

    if fixedBotPending then
        fixedBotPending[#fixedBotPending + 1] = callback
        return
    end

    fixedBotPending = { callback }

    if botToken() == '' then
        completeFixedBotValidation(false, 'missing_token')
        return
    end

    discordRequest('GET', '/users/@me', nil, function(success, user, statusCode)
        if not success or type(user) ~= 'table' or not user.id then
            fixedBotState = 'unknown'
            completeFixedBotValidation(false, 'bot_identity_http_' .. tostring(statusCode))
            return
        end

        if user.bot ~= true then
            fixedBotState = 'invalid'
            RSDiscordLogs.Warn('De ingestelde Discord-token hoort niet bij een bot-account.')
            completeFixedBotValidation(false, 'not_a_bot')
            return
        end

        local currentId = tostring(user.id)
        local pinnedId = GetResourceKvpString(FIXED_BOT_KVP) or ''

        if pinnedId == '' then
            SetResourceKvp(FIXED_BOT_KVP, currentId)
            pinnedId = currentId

            RSDiscordLogs.Info(('Centrale Discord bot permanent vastgezet: %s (ID %s).')
                :format(tostring(user.username or 'Discord bot'), currentId))
        elseif pinnedId ~= currentId then
            fixedBotState = 'invalid'
            SetConvar(FIXED_BOT_RUNTIME_CONVAR, pinnedId)

            RSDiscordLogs.Warn(('Andere Discord bot geweigerd. Vastgezette bot-ID: %s, aangeboden bot-ID: %s.')
                :format(pinnedId, currentId))

            completeFixedBotValidation(false, 'wrong_bot')
            return
        end

        SetConvar(FIXED_BOT_RUNTIME_CONVAR, pinnedId)
        fixedBotState = 'valid'
        fixedBotUser = user
        completeFixedBotValidation(true, 'fixed_bot', user)
    end)
end

local function webhookRequest(webhookUrl, embed, content, callback)
    callback = callback or function() end

    if not webhookUrl or webhookUrl == '' then
        callback(false, 0)
        return
    end

    local payload = {
        username = 'FiveM Logs',
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

local function categoryNameForResource(resourceName)
    local categories = Config.Categories or {}

    if categories.Enabled == false then
        return 'FiveM Logs'
    end

    local name = tostring(resourceName or '')
    local lowerName = name:lower()
    local overrides = categories.Overrides or {}
    local override = overrides[name] or overrides[lowerName]

    if override and tostring(override) ~= '' then
        return tostring(override)
    end

    for _, rule in ipairs(categories.PrefixRules or {}) do
        if type(rule) == 'table' then
            local prefix = tostring(rule.prefix or ''):lower()
            local category = tostring(rule.category or '')

            if prefix ~= '' and category ~= '' and lowerName:sub(1, #prefix) == prefix then
                return category
            end
        end
    end

    return tostring(categories.Default or 'Overige Logs')
end

function RSDiscordLogs.GetCategoryForResource(resourceName)
    return categoryNameForResource(resourceName)
end

local function cacheTextChannel(channel)
    if type(channel) ~= 'table' or not channel.id or not channel.name then
        return
    end

    local key = tostring(channel.name):lower()
    channelCache[key] = channelCache[key] or {}
    channelCache[key][#channelCache[key] + 1] = {
        id = tostring(channel.id),
        parent_id = channel.parent_id and tostring(channel.parent_id) or nil,
        name = tostring(channel.name)
    }
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
        categoryCache = {}

        for _, channel in ipairs(channels) do
            if channel.type == 4 and channel.name and channel.id then
                categoryCache[tostring(channel.name):lower()] = tostring(channel.id)
            elseif channel.type == 0 then
                cacheTextChannel(channel)
            end
        end

        initialized = true
        callback(true)
    end)
end

local function flushCategoryPending(key, success, categoryId)
    local pending = categoryPending[key] or {}
    categoryPending[key] = nil

    for _, callback in ipairs(pending) do
        callback(success, categoryId)
    end
end

local function ensureCategory(categoryName, callback)
    callback = callback or function() end

    categoryName = tostring(categoryName or 'Overige Logs')
    local key = categoryName:lower()
    local cached = categoryCache[key]

    if cached and cached ~= '' then
        callback(true, cached)
        return
    end

    if categoryPending[key] then
        categoryPending[key][#categoryPending[key] + 1] = callback
        return
    end

    categoryPending[key] = { callback }

    local categories = Config.Categories or {}
    if categories.AutoCreate == false or not Config.Routing.AutoCreateChannels then
        flushCategoryPending(key, false, nil)
        return
    end

    local guild = guildId()
    if guild == '' then
        flushCategoryPending(key, false, nil)
        return
    end

    discordRequest('POST', '/guilds/' .. guild .. '/channels', {
        name = categoryName,
        type = 4
    }, function(success, created, statusCode)
        if not success or type(created) ~= 'table' or not created.id then
            RSDiscordLogs.Warn(('Discord categorie `%s` aanmaken mislukt (HTTP %s).')
                :format(categoryName, statusCode))
            flushCategoryPending(key, false, nil)
            return
        end

        local id = tostring(created.id)
        categoryCache[key] = id
        RSDiscordLogs.Info(('Discord categorie aangemaakt: %s'):format(categoryName))
        flushCategoryPending(key, true, id)
    end)
end

local function configuredCategoryNames()
    local categories = Config.Categories or {}
    local result = {}
    local lookup = {}

    local function add(value)
        value = tostring(value or '')
        local key = value:lower()
        if value == '' or lookup[key] then
            return
        end
        lookup[key] = true
        result[#result + 1] = value
    end

    if categories.Enabled == false then
        add('FiveM Logs')
        return result
    end

    add(categories.Default or 'Overige Logs')

    for _, value in pairs(categories.Overrides or {}) do
        add(value)
    end

    for _, rule in ipairs(categories.PrefixRules or {}) do
        if type(rule) == 'table' then
            add(rule.category)
        end
    end

    table.sort(result)
    return result
end

local function ensureConfiguredCategories(callback)
    callback = callback or function() end
    local names = configuredCategoryNames()
    local index = 1

    local function nextCategory()
        local name = names[index]
        if not name then
            callback(true)
            return
        end

        index = index + 1
        ensureCategory(name, function(success)
            if not success then
                callback(false)
                return
            end
            nextCategory()
        end)
    end

    nextCategory()
end

local function findChannel(channelName, parentId)
    local channels = channelCache[tostring(channelName):lower()] or {}
    local fallback = nil

    for _, channel in ipairs(channels) do
        if tostring(channel.parent_id or '') == tostring(parentId or '') then
            return channel, channel
        end

        fallback = fallback or channel
    end

    return nil, fallback
end

local function flushChannelPending(key, success, channelId)
    local pending = channelPending[key] or {}
    channelPending[key] = nil

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
    local wantedCategory = categoryNameForResource(resourceName)
    local pendingKey = wantedCategory:lower() .. '|' .. wantedName:lower()

    if channelPending[pendingKey] then
        channelPending[pendingKey][#channelPending[pendingKey] + 1] = callback
        return
    end

    channelPending[pendingKey] = { callback }

    local function createOrResolve()
        ensureCategory(wantedCategory, function(categorySuccess, parentId)
            if not categorySuccess or not parentId then
                flushChannelPending(pendingKey, false, nil)
                return
            end

            local exact, fallback = findChannel(wantedName, parentId)
            if exact and exact.id then
                flushChannelPending(pendingKey, true, exact.id)
                return
            end

            local autoMove = not Config.Categories or Config.Categories.AutoMoveExisting ~= false
            if fallback and fallback.id and autoMove then
                discordRequest('PATCH', '/channels/' .. fallback.id, {
                    parent_id = parentId
                }, function(success, moved, statusCode)
                    if not success then
                        RSDiscordLogs.Warn(('Kanaal #%s verplaatsen naar `%s` mislukt (HTTP %s).')
                            :format(wantedName, wantedCategory, statusCode))
                        flushChannelPending(pendingKey, false, nil)
                        return
                    end

                    fallback.parent_id = parentId
                    RSDiscordLogs.Info(('Discord kanaal #%s verplaatst naar categorie %s.')
                        :format(wantedName, wantedCategory))
                    flushChannelPending(pendingKey, true, fallback.id)
                end)
                return
            end

            if not Config.Routing.AutoCreateChannels then
                flushChannelPending(pendingKey, false, nil)
                return
            end

            local guild = guildId()
            discordRequest('POST', '/guilds/' .. guild .. '/channels', {
                name = wantedName,
                type = 0,
                parent_id = parentId,
                topic = Config.Discord.ChannelTopic or 'Automatisch aangemaakt door de centrale FiveM logger.'
            }, function(success, created, statusCode)
                if not success or type(created) ~= 'table' or not created.id then
                    RSDiscordLogs.Warn(('Kanaal #%s aanmaken mislukt (HTTP %s).')
                        :format(wantedName, statusCode))
                    flushChannelPending(pendingKey, false, nil)
                    return
                end

                cacheTextChannel(created)
                RSDiscordLogs.Info(('Discord kanaal aangemaakt: #%s -> %s')
                    :format(wantedName, wantedCategory))
                flushChannelPending(pendingKey, true, tostring(created.id))
            end)
        end)
    end

    if not initialized then
        refreshChannels(function(success)
            if not success then
                flushChannelPending(pendingKey, false, nil)
                return
            end
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
        name = 'Categorie',
        value = '`' .. RSDiscordLogs.Truncate(categoryNameForResource(resourceName), 90) .. '`',
        inline = true
    }

    fields[#fields + 1] = {
        name = 'Type',
        value = '`' .. RSDiscordLogs.Truncate(logType, 50) .. '`',
        inline = true
    }

    fields = RSDiscordLogs.NormalizeFields(fields)

    local footerText = Config.Embed.Footer or 'FiveM Logs'
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

    RSDiscordLogs.EnsureFixedBot(function(botSuccess, botResult)
        if not botSuccess then
            callback(false, botResult or 'wrong_bot')
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

                if statusCode == 404 then
                    initialized = false
                    channelCache = {}
                end

                callback(false, 'bot_http_' .. tostring(statusCode))
            end)
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
        RSDiscordLogs.Warn('Geen rs_discordlogs_token/rs_discordlogs_guild ingesteld; bot-route wordt overgeslagen.')
        callback(false)
        return
    end

    RSDiscordLogs.EnsureFixedBot(function(botSuccess, botResult, user)
        if not botSuccess then
            RSDiscordLogs.Warn(('Vaste Discord bot validatie mislukt: %s.'):format(tostring(botResult)))
            callback(false)
            return
        end

        refreshChannels(function(success)
            if not success then
                callback(false)
                return
            end

            ensureConfiguredCategories(function(categorySuccess)
                if categorySuccess then
                    RSDiscordLogs.Info(('Discord gereed met vaste bot %s en automatische categorieen.')
                        :format(tostring(user and user.username or 'Discord bot')))
                end

                callback(categorySuccess)
            end)
        end)
    end)
end
