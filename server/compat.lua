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

local function webhookEmbedToPayload(embed, content)
    embed = type(embed) == 'table' and embed or {}

    local description = embed.description
    if (not description or description == '') and content and content ~= '' then
        description = tostring(content)
    elseif content and content ~= '' then
        description = ('%s\n\n%s'):format(tostring(content), tostring(description))
    end

    return {
        type = 'info',
        title = embed.title or 'FiveM log',
        description = description,
        color = tonumber(embed.color),
        fields = normalizeFields(embed.fields),
        footer = embed.footer and embed.footer.text or nil,
        thumbnail = embed.thumbnail and embed.thumbnail.url or nil,
        image = embed.image and embed.image.url or nil
    }
end

exports('LegacyWebhook', function(...)
    return send(nil, ...)
end)

exports('Webhook', function(...)
    return send(nil, ...)
end)

-- Gebruikt door @rs_discordlogs/server/intercept.lua. Een bestaand script mag
-- zijn oude webhook-payload blijven bouwen; rs_discordlogs routeert hem daarna
-- via de centrale bot naar het kanaal van de aanroepende resource.
exports('ForwardWebhook', function(webhookPayload)
    if type(webhookPayload) ~= 'table' then
        return false
    end

    local resourceName = callingResource(nil)
    local embeds = type(webhookPayload.embeds) == 'table' and webhookPayload.embeds or {}

    if #embeds == 0 then
        RSDiscordLogs.Send(resourceName, webhookEmbedToPayload({}, webhookPayload.content))
        return true
    end

    local sent = 0
    for index = 1, math.min(#embeds, 10) do
        local embed = embeds[index]
        if type(embed) == 'table' then
            RSDiscordLogs.Send(resourceName, webhookEmbedToPayload(embed, index == 1 and webhookPayload.content or nil))
            sent = sent + 1
        end
    end

    return sent > 0
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
    AddEventHandler('discordlogs:log', function(payload, resourceName)
        send(resourceName, payload)
    end)

    AddEventHandler('fivem:discordlog', function(payload, resourceName)
        send(resourceName, payload)
    end)
end
