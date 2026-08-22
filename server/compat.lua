RSDiscordLogs = RSDiscordLogs or {}

local function callingResource(explicit)
    if explicit and explicit ~= '' then
        return tostring(explicit)
    end

    local invoking = GetInvokingResource()
    if invoking and invoking ~= '' then
        return invoking
    end

    return 'algemeen'
end

local function normalizeFields(fields)
    if type(fields) ~= 'table' then
        return nil
    end

    local result = {}
    for _, field in ipairs(fields) do
        if type(field) == 'table' and field.name then
            result[#result + 1] = {
                name = tostring(field.name),
                value = tostring(field.value or '-'),
                inline = field.inline == true
            }
        end
    end

    return result
end

local function payloadFromArgs(...)
    local args = { ... }

    if type(args[1]) == 'table' then
        local payload = args[1]
        payload.type = payload.type or payload.level or 'info'
        return payload
    end

    -- Universeel legacy formaat:
    -- title, description, color, fields, playerSource, logType
    return {
        title = args[1] or 'FiveM log',
        description = args[2],
        color = tonumber(args[3]),
        fields = normalizeFields(args[4]),
        source = tonumber(args[5]),
        type = args[6] or 'info'
    }
end

local function send(explicitResource, ...)
    if not Config.Compatibility or Config.Compatibility.Enabled == false then
        return false
    end

    local resourceName = callingResource(explicitResource)
    local payload = payloadFromArgs(...)

    RSDiscordLogs.Send(resourceName, payload)
    return true
end

-- Expliciete helper voor scripts die vroeger rechtstreeks een webhook stuurden.
exports('LegacyWebhook', function(...)
    return send(nil, ...)
end)

exports('Webhook', function(...)
    return send(nil, ...)
end)

if not Config.Compatibility or Config.Compatibility.LegacyExports ~= false then
    exports('DiscordLog', function(...)
        return send(nil, ...)
    end)

    exports('SendDiscordLog', function(...)
        return send(nil, ...)
    end)

    exports('CreateLog', function(...)
        return send(nil, ...)
    end)

    exports('WebhookLog', function(...)
        return send(nil, ...)
    end)

    exports('SendWebhook', function(...)
        return send(nil, ...)
    end)

    exports('Logger', function(...)
        return send(nil, ...)
    end)
end

exports('IsAvailable', function()
    return true
end)

if not Config.Compatibility or Config.Compatibility.LocalEvents ~= false then
    -- Bewust alleen lokale server-events; geen RegisterNetEvent.
    AddEventHandler('discordlogs:log', function(payload, resourceName)
        send(resourceName, payload)
    end)

    AddEventHandler('fivem:discordlog', function(payload, resourceName)
        send(resourceName, payload)
    end)
end
