Config = {}

Config.Debug = false

-- =========================================================
-- DISCORD
-- =========================================================
-- De centrale bot is bewust NIET instelbaar in deze config.
-- rs_discordlogs gebruikt altijd de bot-token uit:
--   set rs_discordlogs_token "BOT_TOKEN"
--
-- Bij de eerste succesvolle verbinding wordt het Discord bot-user-ID lokaal
-- vastgezet in de resource KVP-opslag. Een andere bot-token wordt daarna
-- geweigerd. Er is bewust geen normale config/resetoptie voor die bot-lock.
--
-- De Discord server en optionele fallback-webhook blijven wel instelbaar:
--   set rs_discordlogs_guild "GUILD_ID"
--   set rs_discordlogs_webhook "CENTRALE_WEBHOOK"
Config.Discord = {
    GuildId = '',
    GuildConvar = 'rs_discordlogs_guild',

    GeneralChannel = 'algemene-logs',
    ChannelPrefix = '',
    ChannelTopic = 'Automatisch aangemaakt door de centrale FiveM logger.',

    -- Alleen een nood-fallback wanneer de vaste bot/API route niet werkt.
    CentralWebhook = '',
    CentralWebhookConvar = 'rs_discordlogs_webhook',

    AlertRoleId = '',
    MentionRoleOnError = false
}

-- =========================================================
-- AUTOMATISCHE DISCORD CATEGORIEEN
-- =========================================================
-- Kanalen worden automatisch onder de juiste categorie geplaatst. Bestaande
-- kanalen met dezelfde naam worden desgewenst naar de juiste categorie verplaatst.
Config.Categories = {
    Enabled = true,
    AutoCreate = true,
    AutoMoveExisting = true,

    Default = 'Overige Logs',

    -- Exacte resource overrides hebben voorrang op prefixregels.
    Overrides = {
        ['connections'] = 'Algemene Logs',
        ['rs_discordlogs'] = 'Algemene Logs',
        ['es_extended'] = 'ESX Logs',
        ['ox_inventory'] = 'OX Logs',
        ['ox_lib'] = 'OX Logs',
        ['ox_target'] = 'OX Logs',
        ['ox_doorlock'] = 'OX Logs',
        ['oxmysql'] = 'OX Logs'
    },

    -- Prefixregels worden van boven naar beneden uitgevoerd.
    PrefixRules = {
        { prefix = 'rs-', category = 'RS Logs' },
        { prefix = 'rs_', category = 'RS Logs' },
        { prefix = 'esx_', category = 'ESX Logs' },
        { prefix = 'es_', category = 'ESX Logs' },
        { prefix = 'ox_', category = 'OX Logs' }
    }
}

-- =========================================================
-- BOT ONLINE STATUS
-- =========================================================
Config.Gateway = {
    Enabled = true,
    Status = 'online', -- online, idle, dnd, invisible
    ActivityType = 3,  -- 0 Playing, 2 Listening, 3 Watching, 5 Competing
    ActivityName = 'FiveM Logs',
    ReconnectDelayMs = 5000,
    Debug = false
}

-- =========================================================
-- ROUTING
-- =========================================================
Config.Routing = {
    -- Alles centraal: vaste bot -> centrale webhook fallback.
    Priority = {
        'bot',
        'central_webhook'
    },

    AutoCreateChannels = true,
    UseResourceChannels = true,

    -- Oude resource-webhooks worden alleen gedetecteerd en niet gebruikt.
    UseDetectedResourceWebhooks = false,

    ChannelOverrides = {
        -- ['ox_inventory'] = 'inventory-logs',
        -- ['es_extended'] = 'esx-logs'
    },

    -- Alleen voor uitzonderlijke legacy situaties. Normaal leeg laten.
    ResourceWebhooks = {
        -- ['legacy-resource'] = 'https://discord.com/api/webhooks/...'
    }
}

-- =========================================================
-- RESOURCE SCANNER
-- =========================================================
Config.Scanner = {
    Enabled = true,
    ScanOnStart = true,
    ScanOnResourceStart = true,
    DetectWebhookUrls = true,
    DetectLoggingExports = true,
    MaxFileBytes = 512000,

    CommonFiles = {
        'config.lua',
        'shared/config.lua',
        'server/config.lua',
        'config/server.lua',
        'server/main.lua',
        'server.lua',
        'settings.lua',
        'shared.lua'
    },

    KnownLogExports = {
        'Log',
        'Logger',
        'SendLog',
        'SendDiscordLog',
        'DiscordLog',
        'CreateLog',
        'WebhookLog',
        'SendWebhook',
        'LegacyWebhook'
    },

    IgnoreResources = {
        ['rs_discordlogs'] = true
    }
}

-- =========================================================
-- COMPATIBILITY
-- =========================================================
Config.Compatibility = {
    Enabled = true,
    LocalEvents = true,
    LegacyExports = true
}

-- =========================================================
-- AUTOMATISCHE ADAPTERS
-- =========================================================
Config.Adapters = {
    OxInventory = {
        Enabled = true,
        Transfers = true,
        Purchases = true,
        Crafting = true,
        ItemUse = false,
        OpenInventory = false
    }
}

-- =========================================================
-- EMBEDS
-- =========================================================
Config.Embed = {
    DefaultColor = 3447003,

    Colors = {
        info = 3447003,
        success = 5763719,
        warning = 16776960,
        error = 15548997,
        security = 15158332,
        admin = 10181046,
        money = 15844367
    },

    Footer = 'FiveM Logs',
    IncludeResource = true,
    IncludePlayerIdentifiers = true
}

-- =========================================================
-- ALGEMENE SERVERLOGS
-- =========================================================
Config.AutomaticLogs = {
    ResourceLifecycle = false,
    PlayerConnecting = true,
    PlayerDropped = true
}
