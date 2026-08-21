Config = {}

Config.Debug = false

-- De Discord bot-token kan hier worden ingevuld.
-- Voor productie is een server.cfg convar veiliger:
--   set rs_discordlogs_token "BOT_TOKEN"
--   set rs_discordlogs_guild "GUILD_ID"
--   set rs_discordlogs_webhook "CENTRALE_WEBHOOK"
Config.Discord = {
    BotToken = '',
    TokenConvar = 'rs_discordlogs_token',

    GuildId = '',
    GuildConvar = 'rs_discordlogs_guild',

    CategoryName = 'FiveM Logs',
    CategoryId = '', -- Optioneel: bestaande Discord category ID.

    GeneralChannel = 'algemene-logs',
    ChannelPrefix = '',
    ChannelTopic = 'Automatisch aangemaakt door rs_discordlogs.',

    BotName = 'RS Discord Logs',
    AvatarUrl = '',

    CentralWebhook = '',
    CentralWebhookConvar = 'rs_discordlogs_webhook',

    -- Optioneel. Wordt alleen gebruikt wanneer MentionRoleOnError = true.
    AlertRoleId = '',
    MentionRoleOnError = false
}

Config.Routing = {
    -- Ondersteunde routes: 'bot', 'resource_webhook', 'central_webhook'
    -- De eerst werkende route wordt gebruikt.
    Priority = {
        'bot',
        'resource_webhook',
        'central_webhook'
    },

    AutoCreateChannels = true,
    UseResourceChannels = true,

    -- Handmatige kanaalnamen per resource.
    ChannelOverrides = {
        -- ['ox_inventory'] = 'inventory-logs',
        -- ['es_extended'] = 'esx-logs'
    },

    -- Handmatige webhooks per resource hebben voorrang op gescande webhooks.
    ResourceWebhooks = {
        -- ['some-resource'] = 'https://discord.com/api/webhooks/...'
    }
}

Config.Scanner = {
    Enabled = true,
    ScanOnStart = true,
    ScanOnResourceStart = true,

    DetectWebhookUrls = true,
    DetectLoggingExports = true,

    -- Webhooks worden alleen in het servergeheugen bewaard en nooit volledig
    -- naar de console geschreven.
    MaxFileBytes = 512000,

    -- Bestanden die bij willekeurige resources vaak loggingconfig bevatten.
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

    -- Namen die als mogelijke logging-export worden gemarkeerd.
    KnownLogExports = {
        'Log',
        'Logger',
        'SendLog',
        'SendDiscordLog',
        'DiscordLog',
        'CreateLog',
        'WebhookLog',
        'SendWebhook'
    },

    IgnoreResources = {
        ['rs_discordlogs'] = true
    }
}

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

    Footer = 'RS Discord Logs',
    IncludeResource = true,
    IncludePlayerIdentifiers = true
}

Config.AutomaticLogs = {
    ResourceLifecycle = false,
    PlayerConnecting = false,
    PlayerDropped = false
}
