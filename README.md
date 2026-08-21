# rs_discordlogs

Universeel **standalone Discord logging-systeem voor FiveM**. Geen ESX-, QBCore-, ox_lib-, Deluxe-Core- of andere frameworkdependency nodig.

`rs_discordlogs` kan automatisch per FiveM-resource een Discord-logkanaal gebruiken of aanmaken, rich embeds versturen, bestaande webhook-URL's herkennen, terugvallen op een centrale webhook en de eigen Discord bot via de Gateway zichtbaar **online** houden.

## Functies

- 100% standalone FiveM-resource
- Discord Bot REST API via eigen bot-token
- Discord Gateway verbinding met online status
- Automatische Gateway heartbeat, reconnect en session resume
- Geen `discord.js`, npm-installatie of apart botproces nodig
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
- Test-, scan-, status- en Gateway commands
- Optionele resource-, connect- en disconnectlogs
- Compatibel met ESX, QBCore, Qbox en standalone scripts

## Installatie

1. Plaats `rs_discordlogs` in je FiveM resources-map.
2. Voeg aan `server.cfg` toe:

```cfg
ensure rs_discordlogs
```

3. Maak een bot aan via de Discord Developer Portal.
4. Voeg de bot toe aan je Discord-server.
5. Geef de bot minimaal:
   - View Channels
   - Manage Channels
   - Send Messages
   - Embed Links
   - Read Message History
6. Vul de Discord Server ID (`GuildId`) en bot-token in.

De resource gebruikt server-side **Node.js 22** voor de Discord Gateway. Dit staat al ingesteld in `fxmanifest.lua`; er is geen losse Node-server of npm package nodig.

## Aanbevolen configuratie via server.cfg

Zet secrets liever niet in een bestand dat je naar GitHub pusht:

```cfg
set rs_discordlogs_token "JOUW_DISCORD_BOT_TOKEN"
set rs_discordlogs_guild "JOUW_DISCORD_SERVER_ID"
set rs_discordlogs_webhook "OPTIONELE_CENTRALE_WEBHOOK"

ensure rs_discordlogs
```

De convars hebben voorrang op waarden in `config.lua`.

### Extra bescherming van de bot-token

FiveM standard convars zijn server-only, maar standaard leesbaar door andere serverresources. Je kunt de token verder beperken:

```cfg
add_convar_permission rs_discordlogs read rs_discordlogs_token
add_convar_permission rs_discordlogs read rs_discordlogs_gateway_token_runtime
```

Plaats die regels vóór `ensure rs_discordlogs`.

## Config.lua

Je kunt de waarden ook rechtstreeks instellen:

```lua
Config.Discord = {
    BotToken = 'BOT_TOKEN',
    GuildId = 'GUILD_ID',

    CategoryName = 'FiveM Logs',
    GeneralChannel = 'algemene-logs',

    CentralWebhook = ''
}
```

> Push nooit een echte bot-token of webhook naar een openbare repository.

## Discord bot online status

De Gateway staat standaard aan:

```lua
Config.Gateway = {
    Enabled = true,
    Status = 'online',
    ActivityType = 3,
    ActivityName = 'FiveM Logs',
    ReconnectDelayMs = 5000,
    Debug = false
}
```

Activity types:

```text
0 = Playing
2 = Listening
3 = Watching
5 = Competing
```

Standaard verschijnt de bot dus ongeveer als:

```text
🟢 RS Discord Logs
Watching FiveM Logs
```

De Gateway gebruikt geen privileged intents; voor alleen aanwezigheid/online status zijn die niet nodig.

### Gateway controle

Gebruik in de serverconsole:

```text
rslogs_status
```

Voorbeeld:

```text
[rs_discordlogs] Gateway status: online | bot: RS Discord Logs
```

Herstart alleen de Gatewayverbinding:

```text
rslogs_gateway_restart
```

De logging via REST/webhooks blijft los van de Gateway werken. Als de Gateway tijdelijk verbreekt, blijft `rs_discordlogs` de normale loggingroutes gebruiken.

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

Bestaat de category of het kanaal nog niet, dan maakt `rs_discordlogs` die automatisch aan wanneer `AutoCreateChannels = true`.

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

De aanroepende resource wordt automatisch herkend.

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

```lua
TriggerEvent('rs_discordlogs:log', {
    type = 'admin',
    title = 'Adminactie',
    description = 'Een adminactie is uitgevoerd.',
    source = source
})
```

Dit event is bewust **niet** als netwerk-event geregistreerd. Clients kunnen het daardoor niet rechtstreeks spoofen.

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

Je kunt kleuren wijzigen via `Config.Embed.Colors` of per log een `color` meegeven.

## Automatische scanner

De scanner controleert gestarte resources op veelgebruikte server/configbestanden en kan herkennen:

- Discord webhook-URL's
- `server_export`
- runtime Lua `exports('Naam', ...)`
- bekende loggingexportnamen zoals `SendLog`, `DiscordLog`, `CreateLog` en `WebhookLog`

Bij `Config.Debug = true` kan bijvoorbeeld verschijnen:

```text
[rs_discordlogs] [DEBUG] jg-advancedgarages: webhook=ja, logging exports=SendLog, bestanden=4
```

De volledige webhook-URL wordt niet naar de console geschreven.

### Beperking van willekeurige exports

FiveM biedt geen veilige universele manier om de signature van iedere third-party export automatisch te bepalen. Daarom worden onbekende gevonden exports **niet blind uitgevoerd**. Gebruik daarvoor de universele `rs_discordlogs` export/event of een specifieke adapter.

## Resource-specifieke webhooks

```lua
Config.Routing.ResourceWebhooks = {
    ['some-resource'] = 'https://discord.com/api/webhooks/...'
}
```

Of laat de scanner een bestaande webhook herkennen.

## Centrale webhook fallback

Maak in Discord een webhook voor bijvoorbeeld `#algemene-logs` en stel hem in:

```cfg
set rs_discordlogs_webhook "https://discord.com/api/webhooks/..."
```

Wanneer de botroute mislukt, kan deze centrale webhook als laatste fallback worden gebruikt.

## Automatische logs

Standaard staan extra lifecyclelogs uit om spam te voorkomen:

```lua
Config.AutomaticLogs = {
    ResourceLifecycle = false,
    PlayerConnecting = false,
    PlayerDropped = false
}
```

## Commands

```text
rslogs_test
rslogs_scan
rslogs_status
rslogs_gateway_restart
```

Voor ingame gebruik kun je ACE toevoegen:

```cfg
add_ace group.admin command.rslogs_test allow
add_ace group.admin command.rslogs_scan allow
add_ace group.admin command.rslogs_status allow
add_ace group.admin command.rslogs_gateway_restart allow
```

## Exports

```lua
exports['rs_discordlogs']:Log(payload)
exports['rs_discordlogs']:SendLog(type, title, description, fields, source)
exports['rs_discordlogs']:LogForResource(resourceName, payload)
exports['rs_discordlogs']:GetResourceInfo(resourceName)
exports['rs_discordlogs']:RescanResource(resourceName)
exports['rs_discordlogs']:GetGatewayStatus()
```

## Startvolgorde

Zet `rs_discordlogs` vóór scripts die de export gebruiken:

```cfg
ensure rs_discordlogs
ensure [standalone]
ensure [rs]
```

## Beveiliging

- Commit nooit een echte bot-token.
- Gebruik bij voorkeur server convars.
- Beperk token-convars met `add_convar_permission` als je third-party serverresources niet volledig vertrouwt.
- Geef de Discord bot alleen de permissions die nodig zijn.
- Gebruik loggingexports alleen server-side.
- Laat clients niet zelf resource- of logkanaalnamen bepalen.
- De ingebouwde loggingevent is server-only.
- De Gateway gebruikt `intents: 0`; privileged intents hoeven niet aan.

## Licentie

MIT License.
