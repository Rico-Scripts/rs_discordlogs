-- Deze file is bedoeld om vanuit andere resources te laden met:
-- server_script '@rs_discordlogs/server/intercept.lua'
--
-- Hij onderschept uitsluitend Discord webhook POSTs binnen DIE resource en
-- stuurt de bestaande embed/payload door naar de centrale rs_discordlogs bot.

local CURRENT_RESOURCE = GetCurrentResourceName()
local LOGGER_RESOURCE = 'rs_discordlogs'
local DUMMY_WEBHOOK = 'https://discord.com/api/webhooks/0/rs_discordlogs_central'

if CURRENT_RESOURCE == LOGGER_RESOURCE then
    return
end

if rawget(_G, '__rs_discordlogs_interceptor_loaded') then
    return
end

_G.__rs_discordlogs_interceptor_loaded = true

local originalPerformHttpRequest = PerformHttpRequest
local originalGetConvar = GetConvar

local function loggerStarted()
    local state = GetResourceState(LOGGER_RESOURCE)
    return state == 'started' or state == 'starting'
end

local function isDiscordWebhook(url)
    if type(url) ~= 'string' then
        return false
    end

    return url:match('^https://discord%.com/api/webhooks/%d+/') ~= nil
        or url:match('^https://discordapp%.com/api/webhooks/%d+/') ~= nil
end

local function isWebhookConvar(name)
    return type(name) == 'string'
        and name:lower():find('webhook', 1, true) ~= nil
end

GetConvar = function(name, defaultValue)
    local value = originalGetConvar(name, defaultValue)

    if loggerStarted()
        and isWebhookConvar(name)
        and (value == nil or value == '')
    then
        return DUMMY_WEBHOOK
    end

    return value
end

local function fillEmptyWebhookConfig(tbl, depth, visited, webhookContext)
    if type(tbl) ~= 'table' or depth > 6 then
        return
    end

    visited = visited or {}
    if visited[tbl] then
        return
    end
    visited[tbl] = true

    for key, value in pairs(tbl) do
        local keyIsWebhook = type(key) == 'string'
            and key:lower():find('webhook', 1, true) ~= nil
        local insideWebhook = webhookContext == true or keyIsWebhook

        if type(value) == 'string' then
            if insideWebhook and value == '' then
                tbl[key] = DUMMY_WEBHOOK
            end
        elseif type(value) == 'table' then
            fillEmptyWebhookConfig(value, depth + 1, visited, insideWebhook)
        end
    end
end

if loggerStarted() then
    if type(Config) == 'table' then
        fillEmptyWebhookConfig(Config, 0, {}, false)
    end

    if type(RSConfig) == 'table' then
        fillEmptyWebhookConfig(RSConfig, 0, {}, false)
    end
end

PerformHttpRequest = function(url, callback, method, data, headers, options)
    local requestMethod = tostring(method or 'GET'):upper()

    if loggerStarted()
        and requestMethod == 'POST'
        and isDiscordWebhook(url)
    then
        local payload = nil

        if type(data) == 'table' then
            payload = data
        elseif type(data) == 'string' and data ~= '' then
            local ok, decoded = pcall(json.decode, data)
            if ok and type(decoded) == 'table' then
                payload = decoded
            end
        end

        if type(payload) == 'table' then
            local ok, forwarded = pcall(function()
                return exports[LOGGER_RESOURCE]:ForwardWebhook(payload)
            end)

            if ok and forwarded then
                if type(callback) == 'function' then
                    SetTimeout(0, function()
                        callback(204, '', {})
                    end)
                end
                return
            end
        end

        if url == DUMMY_WEBHOOK then
            if type(callback) == 'function' then
                SetTimeout(0, function()
                    callback(503, 'central_logger_unavailable', {})
                end)
            end
            return
        end
    end

    return originalPerformHttpRequest(url, callback, method, data, headers, options)
end
