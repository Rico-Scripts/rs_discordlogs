RSDiscordLogs = RSDiscordLogs or {}
RSDiscordLogs.ResourceInfo = RSDiscordLogs.ResourceInfo or {}

local function uniqueInsert(list, lookup, value)
    if not value or value == '' or lookup[value] then
        return
    end

    lookup[value] = true
    list[#list + 1] = value
end

local function literalMetadataFiles(resourceName, metadataKey)
    local files = {}
    local lookup = {}
    local count = GetNumResourceMetadata(resourceName, metadataKey) or 0

    for index = 0, count - 1 do
        local value = GetResourceMetadata(resourceName, metadataKey, index)

        if value
            and value ~= ''
            and not value:find('*', 1, true)
            and not value:find('@', 1, true)
        then
            uniqueInsert(files, lookup, value)
        end
    end

    return files, lookup
end

local function collectCandidateFiles(resourceName)
    local files, lookup = literalMetadataFiles(resourceName, 'server_script')

    local sharedFiles = literalMetadataFiles(resourceName, 'shared_script')
    for _, fileName in ipairs(sharedFiles) do
        uniqueInsert(files, lookup, fileName)
    end

    uniqueInsert(files, lookup, 'fxmanifest.lua')
    uniqueInsert(files, lookup, '__resource.lua')

    for _, fileName in ipairs(Config.Scanner.CommonFiles or {}) do
        uniqueInsert(files, lookup, fileName)
    end

    return files
end

local function scanWebhook(content)
    if not Config.Scanner.DetectWebhookUrls then
        return nil
    end

    -- Discord en legacy discordapp webhook-URL's.
    return content:match('(https://discord%.com/api/webhooks/%d+/[%w%-%._]+)')
        or content:match('(https://discordapp%.com/api/webhooks/%d+/[%w%-%._]+)')
end

local function scanLoggingExports(content, foundExports, exportLookup)
    if not Config.Scanner.DetectLoggingExports then
        return
    end

    local known = {}
    for _, exportName in ipairs(Config.Scanner.KnownLogExports or {}) do
        known[exportName:lower()] = true
    end

    -- Runtime Lua exports: exports('SendLog', function(...) ... end)
    for exportName in content:gmatch("exports%s*%(%s*['\"]([^'\"]+)['\"]") do
        if known[exportName:lower()] then
            uniqueInsert(foundExports, exportLookup, exportName)
        end
    end

    -- Legacy manifest: server_export 'SendLog'
    for exportName in content:gmatch("server_export%s+['\"]([^'\"]+)['\"]") do
        if known[exportName:lower()] then
            uniqueInsert(foundExports, exportLookup, exportName)
        end
    end

    -- server_exports { 'SendLog', 'DiscordLog' }
    for block in content:gmatch('server_exports%s*(%b{})') do
        for exportName in block:gmatch("['\"]([^'\"]+)['\"]") do
            if known[exportName:lower()] then
                uniqueInsert(foundExports, exportLookup, exportName)
            end
        end
    end
end

function RSDiscordLogs.ScanResource(resourceName)
    if not Config.Scanner.Enabled then
        return nil
    end

    if not resourceName or resourceName == '' then
        return nil
    end

    if Config.Scanner.IgnoreResources and Config.Scanner.IgnoreResources[resourceName] then
        return nil
    end

    local state = GetResourceState(resourceName)
    if state ~= 'started' and state ~= 'starting' then
        return nil
    end

    local result = {
        resource = resourceName,
        webhook = nil,
        exports = {},
        scannedFiles = 0
    }

    local exportLookup = {}
    local candidateFiles = collectCandidateFiles(resourceName)

    for _, fileName in ipairs(candidateFiles) do
        local content = LoadResourceFile(resourceName, fileName)

        if content and content ~= '' and #content <= (Config.Scanner.MaxFileBytes or 512000) then
            result.scannedFiles = result.scannedFiles + 1

            if not result.webhook then
                result.webhook = scanWebhook(content)
            end

            scanLoggingExports(content, result.exports, exportLookup)
        end
    end

    local configuredWebhook = Config.Routing.ResourceWebhooks
        and Config.Routing.ResourceWebhooks[resourceName]

    if configuredWebhook and configuredWebhook ~= '' then
        result.webhook = configuredWebhook
        result.webhookSource = 'config'
    elseif result.webhook then
        result.webhookSource = 'scanner'
    end

    RSDiscordLogs.ResourceInfo[resourceName] = result

    if Config.Debug then
        local webhookText = result.webhook and 'ja' or 'nee'
        local exportText = #result.exports > 0 and table.concat(result.exports, ', ') or 'geen'

        RSDiscordLogs.Debug(('%s: webhook=%s, logging exports=%s, bestanden=%s')
            :format(resourceName, webhookText, exportText, result.scannedFiles))
    end

    return result
end

function RSDiscordLogs.ScanAllResources()
    if not Config.Scanner.Enabled then
        return {
            scanned = 0,
            webhooks = 0,
            exports = 0
        }
    end

    local stats = {
        scanned = 0,
        webhooks = 0,
        exports = 0
    }

    local total = GetNumResources()

    for index = 0, total - 1 do
        local resourceName = GetResourceByFindIndex(index)

        if resourceName and not (Config.Scanner.IgnoreResources and Config.Scanner.IgnoreResources[resourceName]) then
            local info = RSDiscordLogs.ScanResource(resourceName)

            if info then
                stats.scanned = stats.scanned + 1

                if info.webhook then
                    stats.webhooks = stats.webhooks + 1
                end

                if #info.exports > 0 then
                    stats.exports = stats.exports + 1
                end
            end
        end
    end

    RSDiscordLogs.Info(('Scanner klaar: %s resources, %s webhook(s), %s resource(s) met logging-export(s).')
        :format(stats.scanned, stats.webhooks, stats.exports))

    return stats
end

function RSDiscordLogs.GetResourceWebhook(resourceName)
    local configured = Config.Routing.ResourceWebhooks
        and Config.Routing.ResourceWebhooks[resourceName]

    if configured and configured ~= '' then
        return configured
    end

    local info = RSDiscordLogs.ResourceInfo[resourceName]
    return info and info.webhook or nil
end
