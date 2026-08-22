Config = {}

Config.Debug = false

-- =========================================================
-- DISCORD
-- =========================================================
-- Dit zijn normaal de ENIGE Discord-gegevens die je hoeft in te vullen.
-- Voor productie zijn server.cfg convars aanbevolen:
--   set rs_discordlogs_token "BOT_TOKEN"
--   set rs_discordlogs_guild "GUILD_ID"
--   set rs_discordlogs_webhook "CENTRALE_WEBHOOK" -- optioneel fallback
Config.Discord = {
    BotToken = '',
    TokenConvar = 'rs_discordlogs_token',

    GuildId = '',
    GuildConvar = 'rs_discordlogs_guild',

    CategoryName = 'FiveM Logs',
    CategoryId = '', -- Optioneel: ID van een bestaande Discord category.

    GeneralChannel = 'algemene-logs',
    ChannelPrefix = '',
    ChannelTopic = 'Automatisch aangemaakt door de centrale FiveM logger.',

    BotName = 'FiveM Logs',
    AvatarUrl = '',

    -- Alleen een nood-fallback wanneer de bot/API route niet werkt.
    CentralWebhook = '',
    CentralWebhookConvar = 'rs_discordlogs_webhook',

    AlertRoleId = '',
    MentionRoleOnError = false
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
    -- Alles centraal: bot -> centrale webhook fallback.
    -- Losse webhooks uit andere resources zijn standaard GEEN bestemming meer.
    Priority = {
        'bot',
        'central_webhook'
    },

    AutoCreateChannels = true,
    UseResourceChannels = true,

    -- Alleen inschakelen wanneer je bewust oude resource-webhooks als extra
    -- fallback wilt blijven gebruiken.
    UseDetectedResourceWebhooks = false,

    ChannelOverrides = {
        -- ['ox_inventory'] = 'inventory-logs',
        -- ['es_extended'] = 'esx-logs'
    },

    -- Optioneel voor uitzonderingen. Normaal leeg laten.
    ResourceWebhooks = {
        -- ['legacy-resource'] = 'https://discord.com/api/webhooks/...'
    }
}

-- =========================================================
-- RESOURCE SCANNER
-- =========================================================
-- De scanner inventariseert resources en bestaande logging/webhooks.
-- Hij verandert geen third-party bestanden en toont nooit volledige webhook-URL's.
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
-- Geeft scripts meerdere algemene export/event-formaten zonder dat die scripts
-- zelf Discord tokens/webhooks hoeven te kennen.
Config.Compatibility = {
    Enabled = true,
    LocalEvents = true,
    LegacyExports = true
}

-- =========================================================
-- AUTOMATISCHE ADAPTERS
-- =========================================================
-- Deze adapters luisteren rechtstreeks naar ondersteunde resources, zodat je
-- daar niets aan hun Discord-config hoeft te wijzigen.
Config.Adapters = {
    OxInventory = {
        Enabled = true,
        Transfers = true,   -- geven / tussen verschillende inventories
        Purchases = true,
        Crafting = true,
        ItemUse = false,    -- kan veel logs geven
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
    ResourceLifecycle = false, -- zet aan als je iedere start/stop wilt loggen
    PlayerConnecting = true,
    PlayerDropped = true
}
