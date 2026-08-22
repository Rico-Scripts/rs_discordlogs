# rs_discordlogs

Universele **centrale Discord logger voor FiveM**. De resource is standalone en heeft geen ESX-, QBCore-, Qbox- of Deluxe-Core dependency.

Vanaf v2 is het doel simpel: **Discord maar één keer instellen in `rs_discordlogs`**. Ondersteunde resources sturen hun bestaande webhooklogs automatisch via de centrale bot naar hun eigen Discord-kanaal.

## Wat gebeurt automatisch?

- Discord bot via één bot-token
- Bot zichtbaar online via Discord Gateway
- Automatische category `FiveM Logs`
- Automatisch kanaal per resource
- Bestaande Discord webhook-embeds kunnen centraal worden onderschept en doorgestuurd
- Lege webhook-convars van gekoppelde resources hoeven niet meer ingevuld te worden
- Resourceherkenning gebeurt automatisch
- Spelernaam, server ID en identifiers worden toegevoegd wanneer `source` beschikbaar is
- Centrale webhook als nood-fallback
- Scanner voor bestaande webhooks en loggingexports
- Testcommando voor gevonden webhooks/loggingexports dat kanalen aanmaakt en bevestigt
- Automatische `ox_inventory` adapter voor transfers, aankopen en crafting
- Player connect/disconnect logs
- Rate-limit retry voor Discord REST
- Gateway heartbeat, reconnect en session resume

Voorbeeld:

```text
FiveM Logs
├── #connections
├── #ox-inventory
├── #rs-bikemechanic
├── #rs-dyno
├── #rs-jobscreator
├── #rs-duty
├── #rs-bossmenu
├── #rs-phone
├── #rs-garage
├── #rs-sql-manager
└── #rs-carlift
```

De repo/resource blijft `rs_discordlogs` heten, maar de logger zelf is niet beperkt tot `rs-*` resources.

## Installatie

Zorg dat `rs_discordlogs` vóór gekoppelde scripts start:

```cfg
set rs_discordlogs_token "JOUW_DISCORD_BOT_TOKEN"
set rs_discordlogs_guild "JOUW_DISCORD_SERVER_ID"
set rs_discordlogs_webhook "OPTIONELE_CENTRALE_WEBHOOK"

ensure rs_discordlogs
```

Daarna pas de overige resources:

```cfg
ensure [core]
ensure [ox]
ensure [standalone]
ensure [rs]
```

De bot heeft minimaal nodig:

- View Channels
- Manage Channels
- Send Messages
- Embed Links
- Read Message History

De centrale webhook is optioneel en wordt alleen als fallback gebruikt wanneer de botroute niet werkt.

## Enige Discord-config

Je hoeft normaal alleen deze drie waarden te beheren:

```cfg
set rs_discordlogs_token "BOT_TOKEN"
set rs_discordlogs_guild "GUILD_ID"
set rs_discordlogs_webhook "CENTRALE_WEBHOOK"
```

Of rechtstreeks in `config.lua`:

```lua
Config.Discord = {
    BotToken = '',
    GuildId = '',
    CentralWebhook = ''
}
```

Gebruik bij voorkeur server convars en commit nooit echte tokens/webhooks naar GitHub.

## Transparante legacy webhook bridge

Een gekoppelde resource laadt:

```lua
server_script '@rs_discordlogs/server/intercept.lua'
```

Daarna mag de bestaande code bijvoorbeeld nog steeds dit doen:

```lua
PerformHttpRequest(webhook, function() end, 'POST', json.encode({
    username = 'Mijn script',
    embeds = {{
        title = 'Voertuig gekocht',
        description = 'Een voertuig is gekocht.',
        color = 5763719
    }}
}), {
    ['Content-Type'] = 'application/json'
})
```

De bridge onderschept alleen Discord webhook POSTs. De payload wordt niet naar die losse webhook gestuurd, maar naar:

```text
resource -> rs_discordlogs -> Discord Bot API -> resourcekanaal
```

Als het oude script stopt met loggen wanneer zijn webhook leeg is, levert de bridge intern een dummy-webhookwaarde. Die dummy verlaat de server nooit.

### Reeds gekoppelde Rico-Scripts resources

De volgende repos zijn voorbereid op deze centrale bridge:

- RS-core
- rs-bikemechanic
- rs-dyno
- rs-jobscreator
- rs-duty
- rs-bossmenu
- rs_phone
- rs-garage
- rs_sql_manager
- rs-carlift

Daar hoef je dus geen eigen Discord webhook meer voor te configureren zolang `rs_discordlogs` draait.

## Algemene / third-party scripts

De logger is framework-onafhankelijk. Voor een willekeurige resource zijn er drie manieren:

### 1. Bestaande webhook transparant centraliseren

Voeg in het `server_scripts` gedeelte, **na de config maar vóór de servercode**, toe:

```lua
'@rs_discordlogs/server/intercept.lua',
```

Dit is de beste optie voor scripts die al webhooklogging hebben.

### 2. Universele export

```lua
exports['rs_discordlogs']:Log({
    type = 'success',
    title = 'Voertuig gekocht',
    description = 'Een voertuig is gekocht.',
    source = source,
    fields = {
        { name = 'Kenteken', value = plate, inline = true },
        { name = 'Prijs', value = ('€%s'):format(price), inline = true }
    }
})
```

De aanroepende resource wordt automatisch herkend.

### 3. Compatibility exports

Beschikbaar voor eenvoudige migraties:

```lua
exports['rs_discordlogs']:LegacyWebhook(title, description, color, fields, source, logType)
exports['rs_discordlogs']:Webhook(...)
exports['rs_discordlogs']:DiscordLog(...)
exports['rs_discordlogs']:SendDiscordLog(...)
exports['rs_discordlogs']:CreateLog(...)
exports['rs_discordlogs']:WebhookLog(...)
exports['rs_discordlogs']:SendWebhook(...)
```

## Belangrijke technische grens

FiveM staat een resource niet toe bestanden van andere resources te wijzigen. Daardoor kan `rs_discordlogs` niet veilig zelfstandig het `fxmanifest.lua` van ieder willekeurig third-party script aanpassen.

Ook kan een centrale resource niet achteraf de globale `PerformHttpRequest` van een onaangepaste andere resource vervangen. Daarom moet een onbekend third-party script óf de bridge-regel laden, óf een export/event gebruiken, óf een ingebouwde adapter hebben.

De scanner kan zulke webhooks wel detecteren en rapporteren, maar voert geen gevaarlijke automatische bestandswijzigingen uit.

## ox_inventory adapter

Wanneer `ox_inventory` draait, registreert `rs_discordlogs` automatisch hooks. Standaard:

```lua
Config.Adapters.OxInventory = {
    Enabled = true,
    Transfers = true,
    Purchases = true,
    Crafting = true,
    ItemUse = false,
    OpenInventory = false
}
```

Slotverplaatsingen binnen dezelfde inventory worden bewust overgeslagen om spam te voorkomen.

## Routing

Standaard:

```lua
Config.Routing.Priority = {
    'bot',
    'central_webhook'
}
```

Bestaande resource-webhooks die de scanner aantreft worden dus **niet** gebruikt als bestemming.

Wil je dat voor een legacy server toch:

```lua
Config.Routing.UseDetectedResourceWebhooks = true

Config.Routing.Priority = {
    'bot',
    'resource_webhook',
    'central_webhook'
}
```

## Kanaalnamen

Een resource `jg-advancedgarages` wordt automatisch:

```text
FiveM Logs
└── #jg-advancedgarages
```

Override:

```lua
Config.Routing.ChannelOverrides = {
    ['ox_inventory'] = 'inventory-logs',
    ['es_extended'] = 'esx-logs'
}
```

## Bot online status

Standaard:

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

De bot verschijnt bijvoorbeeld als:

```text
🟢 RS-bot
Watching FiveM Logs
```

## Commands

```text
rslogs_test
rslogs_scan
rslogs_test_webhooks
rslogs_test_resource <resource>
rslogs_status
rslogs_gateway_restart
```

### Gevonden logging testen en kanalen aanmaken

Voer uit:

```text
rslogs_test_webhooks
```

De logger scant alle gestarte resources op bestaande Discord-webhooks en bekende loggingexports. Voor iedere gevonden resource wordt via de centrale bot het resourcekanaal aangemaakt of gecontroleerd. Daarna komt er direct een bevestigingsembed in dat kanaal.

De gevonden webhook-URL wordt hierbij **niet** naar de console geschreven en wordt ook niet rechtstreeks aangeroepen. De test loopt volledig via de centrale botconfig.

Voorbeeld console-output:

```text
[rs_discordlogs] [OK] rs-bikemechanic -> kanaal bevestigd via bot
[rs_discordlogs] [OK] rs_phone -> kanaal bevestigd via bot
[rs_discordlogs] [OK] rs-garage -> kanaal bevestigd via bot
[rs_discordlogs] Test klaar: 3 OK, 0 fout.
```

Eén resource apart testen:

```text
rslogs_test_resource rs-garage
```

Ook hierbij wordt het kanaal automatisch aangemaakt als het nog niet bestaat en wordt een bevestigingsbericht gestuurd.

## Universele lokale server-events

Niet vanaf clients geregistreerd:

```lua
TriggerEvent('rs_discordlogs:log', {
    type = 'admin',
    title = 'Adminactie',
    description = 'Een adminactie is uitgevoerd.',
    source = source
})
```

Compatibility aliases:

```lua
TriggerEvent('discordlogs:log', payload)
TriggerEvent('fivem:discordlog', payload)
```

## Beveiliging

- Bot-token nooit naar GitHub pushen.
- Gebruik bij voorkeur server convars.
- De bridge onderschept uitsluitend Discord webhook POSTs.
- De dummy webhook wordt nooit extern aangeroepen.
- Loggingevents zijn server-only.
- Onbekende exports worden niet blind uitgevoerd.
- Third-party resourcebestanden worden niet automatisch aangepast.

## Licentie

MIT License.
