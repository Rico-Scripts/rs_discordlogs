RSDiscordLogs = RSDiscordLogs or {}

local function trim(value)
    if type(value) ~= 'string' then
        return ''
    end

    return value:match('^%s*(.-)%s*$') or ''
end

function RSDiscordLogs.Debug(message)
    if not Config.Debug then
        return
    end

    print(('[rs_discordlogs] [DEBUG] %s'):format(tostring(message)))
end

function RSDiscordLogs.Info(message)
    print(('[rs_discordlogs] %s'):format(tostring(message)))
end

function RSDiscordLogs.Warn(message)
    print(('[rs_discordlogs] [WAARSCHUWING] %s'):format(tostring(message)))
end

function RSDiscordLogs.GetSecret(configValue, convarName)
    local convarValue = ''

    if convarName and convarName ~= '' then
        convarValue = trim(GetConvar(convarName, ''))
    end

    if convarValue ~= '' then
        return convarValue
    end

    return trim(configValue or '')
end

function RSDiscordLogs.SafeJsonDecode(value)
    if type(value) ~= 'string' or value == '' then
        return nil
    end

    local ok, decoded = pcall(json.decode, value)
    if not ok then
        return nil
    end

    return decoded
end

function RSDiscordLogs.SanitizeChannelName(value)
    value = tostring(value or ''):lower()
    value = value:gsub('_', '-')
    value = value:gsub('%s+', '-')
    value = value:gsub('[^%w%-]', '-')
    value = value:gsub('%-+', '-')
    value = value:gsub('^%-+', '')
    value = value:gsub('%-+$', '')

    if value == '' then
        value = 'algemene-logs'
    end

    if #value > 90 then
        value = value:sub(1, 90):gsub('%-+$', '')
    end

    return value
end

function RSDiscordLogs.Truncate(value, maxLength)
    value = tostring(value or '')
    maxLength = tonumber(maxLength) or #value

    if #value <= maxLength then
        return value
    end

    if maxLength <= 3 then
        return value:sub(1, maxLength)
    end

    return value:sub(1, maxLength - 3) .. '...'
end

function RSDiscordLogs.CopyTable(input)
    if type(input) ~= 'table' then
        return input
    end

    local output = {}

    for key, value in pairs(input) do
        output[key] = RSDiscordLogs.CopyTable(value)
    end

    return output
end

function RSDiscordLogs.GetPlayerData(playerSource)
    playerSource = tonumber(playerSource)

    if not playerSource or playerSource <= 0 or not GetPlayerName(playerSource) then
        return nil
    end

    local data = {
        source = playerSource,
        name = GetPlayerName(playerSource),
        identifiers = {}
    }

    for _, identifier in ipairs(GetPlayerIdentifiers(playerSource)) do
        local identifierType, identifierValue = identifier:match('^([^:]+):(.+)$')

        if identifierType and identifierValue then
            data.identifiers[identifierType] = identifierValue
        end
    end

    return data
end

function RSDiscordLogs.NormalizeFields(fields, maxCount)
    if type(fields) ~= 'table' then
        return {}
    end

    local normalized = {}
    maxCount = math.min(25, math.max(1, tonumber(maxCount) or 25))

    for _, field in ipairs(fields) do
        if #normalized >= maxCount then
            break
        end

        if type(field) == 'table' then
            local name = RSDiscordLogs.Truncate(field.name or 'Info', 256)
            local value = RSDiscordLogs.Truncate(field.value or '-', 1024)

            normalized[#normalized + 1] = {
                name = name,
                value = value ~= '' and value or '-',
                inline = field.inline == true
            }
        end
    end

    return normalized
end

function RSDiscordLogs.TableContains(list, wanted)
    if type(list) ~= 'table' then
        return false
    end

    for _, value in ipairs(list) do
        if value == wanted then
            return true
        end
    end

    return false
end
