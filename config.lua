Config = {}

Config.Debug = false

-- =========================================================
-- HOSTED RICO SCRIPTS LOGGING SERVICE
-- =========================================================
-- Er staat bewust GEEN Discord bot-token in deze FiveM resource.
-- Alle Discord-acties lopen via de officiele, centraal gehoste Rico Scripts bot.
--
-- Klant/server configuratie in server.cfg:
--   set rs_discordlogs_api_url "https://logs.jouwdomein.nl"
--   set rs_discordlogs_license "RSLOGS_..."
--   set rs_discordlogs_guild "DISCORD_SERVER_ID"
Config.Remote = {
    ApiBaseUrl = '',
    ApiUrlConvar = 'rs_discordlogs_api_url',

    LicenseKey = '',
    LicenseConvar = 'rs_discordlogs_license',

    GuildId = '',
    GuildConvar = 'rs_discordlogs_guild',

    RetryAttempts = 3,
    RetryDelayMs = 750
}

-- De hosted service bepaalt bot-identiteit, categorieen, kanaalplaatsing en
-- Discord permissies. Resources kunnen die centrale bot niet vervangen.

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

-- Alleen nog aanwezig voor scanner/backwards compatibility. Gescande oude
-- webhooks worden NOOIT als bestemming gebruikt in v3.
Config.Routing = {
    UseDetectedResourceWebhooks = false,
    ResourceWebhooks = {}
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
-- PAYLOAD / PRIVACY
-- =========================================================
Config.Payload = {
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
