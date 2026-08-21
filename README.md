# rs_discordlogs

Universeel **standalone Discord logging-systeem voor FiveM**. De resource heeft geen ESX-, QBCore-, ox_lib- of andere frameworkdependency nodig.

`rs_discordlogs` kan automatisch per FiveM-resource een Discord-logkanaal gebruiken of aanmaken, rich embeds versturen, bestaande webhook-URL's herkennen en terugvallen op een centrale webhook wanneer de Discord Bot API niet beschikbaar is.

## Functies

- 100% standalone FiveM-resource
- Discord Bot API via een eigen bot-token
- Automatische Discord category
- Automatisch één logkanaal per resource
- Handmatige kanaal-overrides
- Nette Discord embeds
- Automatische spelerinformatie en identifiers
- Scanner voor bestaande Discord-webhooks
- Scanner voor bekende logging-exports
- Resource-specifieke webhookrouting
- Centrale webhook fallback
- Rate-limit retry voor de Discord API
- Server-only loggingevent tegen client spoofing
- Test- en scancommands
- Optionele resource-, connect- en disconnectlogs
- Compatibel met ESX, QBCore, Qbox en standalone scripts

## Installatie

1. Plaats `rs_discordlogs` in je FiveM resources-map.
2. Voeg aan `server.cfg` toe:

```cfg
ensure rs_discordlogs
```

3. Maak een Discord bot aan via de Discord Developer Portal.
4. Voeg de bot toe aan je Discord-server.
5. Geef de bot minimaal:
   - View Channels
   - Manage Channels
   - Send Messages
   - Embed Links
   - Read Message History
6. Vul je `GuildId` en bot-token in.

### Aanbevolen: token via server.cfg

Zet secrets liever niet in een bestand dat je naar GitHub pusht:

```cfg
set rs_discordlogs_token "JOUW_DISCORD_BOT_TOKEN"
set rs_discordlogs_guild "JOUW_DISCORD_SERVER_ID"
set rs_discordlogs_webhook "OPTIONELE_CENTRALE_WEBHOOK"
```

De convars hebben voorrang op de waarden in `config.lua`.

### Config.lua

Je kunt ze ook rechtstreeks instellen:

```lua
Config.Discord = {
    BotToken = 'BOT_TOKEN',
    GuildId = 'GUILD_ID',

    CategoryName = 'FiveM Logs',
    GeneralChannel = 'algemene-logs',

    CentralWebhook = ''
}
```

> Push nooit een echte bot-token of webhook naar een openbare GitHub-repository.

## Routing

Standaard probeert de logger:

1. Discord Bot API
2. webhook die bij de resource is gevonden of ingesteld
3. centrale webhook

```lua
Config.Routing.Priority = {
    'bot',
    'resource_webhook',
    'central_webhook'
}
```

De volgorde is vrij aanpasbaar.

## Automatische Discord-kanalen

Een log vanuit:

```text
jg-advancedgarages
```

gaat standaard naar:

```text
FiveM Logs
└── #jg-advancedgarages
```

Bestaat de category of het kanaal nog niet, dan kan `rs_discordlogs` die automatisch aanmaken.

Voor overrides:

```lua
Config.Routing.ChannelOverrides = {
    ['ox_inventory'] = 'inventory-logs',
    ['es_extended'] = 'esx-logs'
}
```

## Universele export

Vanuit ieder **server script**:

```lua
exports['rs_discordlogs']:Log({
    type = 'success',
    title = 'Voertuig gekocht',
    description = 'Een speler heeft een voertuig gekocht.',
    source = source,
    fields = {
        {
            name = 'Kenteken',
            value = plate,
            inline = true
        },
        {
            name = 'Prijs',
            value = ('€%s'):format(price),
            inline = true
        }
    }
})
```

De aanroepende resource wordt automatisch herkend. Je hoeft dus niet zelf `jg-advancedgarages`, `rs-bikemechanic`, enz. mee te sturen.

### Compacte export

```lua
exports['rs_discordlogs']:SendLog(
    'warning',
    'Voertuig uit garage',
    'Een voertuig is uit de garage gehaald.',
    {
        { name = 'Kenteken', value = plate, inline = true }
    },
    source
)
```

## Server-only event

Een resource kan ook lokaal op de server een event triggeren:

```lua
TriggerEvent('rs_discordlogs:log', {
    type = 'admin',
    title = 'Adminactie',
    description = 'Een adminactie is uitgevoerd.',
    source = source
})
```

Dit event is bewust **niet** als netwerk-event geregistreerd. Clients kunnen het daardoor niet rechtstreeks als loggingevent misbruiken.

## Logtypes en kleuren

Standaard:

```text
info
success
warning
error
security
admin
money
```

Je kunt de kleuren wijzigen in:

```lua
Config.Embed.Colors
```

Of per log:

```lua
exports['rs_discordlogs']:Log({
    title = 'Custom log',
    color = 16711680
})
```

## Automatische scanner

De scanner controleert gestarte resources op veelgebruikte server/configbestanden.

Hij kan herkennen:

- Discord webhook-URL's
- `server_export`
- runtime Lua `exports('Naam', ...)`
- bekende loggingexportnamen zoals `SendLog`, `DiscordLog`, `CreateLog` en `WebhookLog`

Voorbeeld console bij `Config.Debug = true`:

```text
[rs_discordlogs] [DEBUG] jg-advancedgarages: webhook=ja, logging exports=SendLog, bestanden=4
```

De volledige webhook-URL wordt nooit naar de console geschreven.

### Belangrijke beperking

FiveM biedt geen veilige universele manier om de betekenis/signature van iedere willekeurige export uit ieder third-party script automatisch te bepalen.

Daarom **roept `rs_discordlogs` onbekende gevonden exports niet blind aan**. De scanner gebruikt de informatie voor detectie, maar willekeurige third-party acties moeten via de universele `rs_discordlogs` export/event worden gekoppeld.

Dit voorkomt dat een export met dezelfde naam maar andere parameters onverwacht fouten of side-effects veroorzaakt.

## Resource-specifieke webhooks

Handmatig:

```lua
Config.Routing.ResourceWebhooks = {
    ['some-resource'] = 'https://discord.com/api/webhooks/...'
}
```

Of laat de scanner een bestaande webhook herkennen.

## Fallback

Wanneer de bot-token ontbreekt, Discord niet bereikbaar is of kanaalbeheer mislukt, probeert de logger de volgende route uit `Config.Routing.Priority`.

Een centrale webhook stel je in met:

```cfg
set rs_discordlogs_webhook "https://discord.com/api/webhooks/..."
```

## Automatische logs

Standaard staan extra lifecyclelogs uit om spam te voorkomen:

```lua
Config.AutomaticLogs = {
    ResourceLifecycle = false,
    PlayerConnecting = false,
    PlayerDropped = false
}
```

Zet ze naar wens op `true`.

## Commands

Console of ACE-gerechtigde gebruiker:

```text
rslogs_test
rslogs_scan
```

Voor ingame gebruik kun je bijvoorbeeld ACE toevoegen:

```cfg
add_ace group.admin command.rslogs_test allow
add_ace group.admin command.rslogs_scan allow
```

## Exports

```lua
exports['rs_discordlogs']:Log(payload)
exports['rs_discordlogs']:SendLog(type, title, description, fields, source)
exports['rs_discordlogs']:LogForResource(resourceName, payload)
exports['rs_discordlogs']:GetResourceInfo(resourceName)
exports['rs_discordlogs']:RescanResource(resourceName)
```

## Startvolgorde

Zet `rs_discordlogs` bij voorkeur vóór scripts die de export gebruiken:

```cfg
ensure rs_discordlogs
ensure [standalone]
ensure [rs]
```

## Beveiliging

- Commit nooit een echte bot-token.
- Gebruik bij voorkeur server convars.
- Geef de Discord bot alleen de permissions die nodig zijn.
- Gebruik loggingexports alleen server-side.
- Laat clients niet zelf resource- of logkanaalnamen bepalen.
- De ingebouwde loggingevent is server-only.

## Licentie

MIT License.
