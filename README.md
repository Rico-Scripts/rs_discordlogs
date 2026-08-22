# rs_discordlogs

Universele centrale Discord logger voor FiveM. Standalone en framework-onafhankelijk.

Vanaf v2.1 hoef je Discord maar één keer centraal in te stellen. De logger gebruikt één vaste Discord-bot, detecteert logging/webhooks in resources, maakt logkanalen automatisch aan en sorteert die kanalen automatisch in meerdere Discord-categorieën.

## Installatie

Zet de geheimen in `server.cfg` en start `rs_discordlogs` vóór de scripts die de bridge gebruiken:

```cfg
set rs_discordlogs_token "JOUW_DISCORD_BOT_TOKEN"
set rs_discordlogs_guild "JOUW_DISCORD_SERVER_ID"
set rs_discordlogs_webhook "OPTIONELE_CENTRALE_WEBHOOK"

ensure rs_discordlogs
```

Daarna kunnen de overige groepen/resources starten.

De bot heeft minimaal nodig:

- View Channels
- Manage Channels
- Send Messages
- Embed Links
- Read Message History

## Vaste centrale bot

De botnaam en avatar zijn niet instelbaar in `config.lua`. Berichten via de Bot API gebruiken altijd de echte naam en avatar van jouw Discord-botaccount.

Bij de eerste succesvolle verbinding slaat `rs_discordlogs` het echte Discord bot-user-ID lokaal op in de resource KVP-opslag. Vanaf dat moment hoort deze installatie bij die bot. Wanneer later een token van een andere bot wordt ingevuld, weigeren zowel de REST-logging als de Discord Gateway die andere bot.

Er is bewust geen normaal configveld waarmee scripts of resources naar een andere bot kunnen wisselen.

De token zelf wordt nooit hardcoded of naar GitHub geschreven; die blijft uitsluitend in `server.cfg` via:

```cfg
set rs_discordlogs_token "BOT_TOKEN"
```

## Automatische categorieën

Standaard maakt de bot deze structuur automatisch aan:

```text
RS Logs
├── #rs-bikemechanic
├── #rs-phone
├── #rs-garage
└── #rs-duty

ESX Logs
├── #es-extended
└── #esx-...

OX Logs
├── #ox-inventory
├── #ox-lib
├── #ox-target
└── #ox-doorlock

Algemene Logs
└── #connections

Overige Logs
└── #onbekende-third-party-resource
```

De regels staan in `Config.Categories`:

```lua
Config.Categories = {
    Enabled = true,
    AutoCreate = true,
    AutoMoveExisting = true,

    Default = 'Overige Logs',

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

    PrefixRules = {
        { prefix = 'rs-', category = 'RS Logs' },
        { prefix = 'rs_', category = 'RS Logs' },
        { prefix = 'esx_', category = 'ESX Logs' },
        { prefix = 'es_', category = 'ESX Logs' },
        { prefix = 'ox_', category = 'OX Logs' }
    }
}
```

`AutoMoveExisting = true` zorgt ervoor dat een al bestaand logkanaal met dezelfde naam naar de juiste categorie wordt verplaatst wanneer het nog verkeerd staat.

Exacte `Overrides` hebben voorrang op `PrefixRules`. Alles wat nergens onder valt gaat naar `Overige Logs`.

## Bestaande webhooklogging centraliseren

Voor een resource die al `PerformHttpRequest` naar een Discord webhook gebruikt voeg je in het `server_scripts` gedeelte, na de config en vóór de eigen servercode, toe:

```lua
'@rs_discordlogs/server/intercept.lua',
```

Voorbeeld:

```lua
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'config.lua',

    '@rs_discordlogs/server/intercept.lua',

    'server/main.lua'
}
```

De bestaande webhookpayload wordt dan onderschept en via de centrale bot naar het kanaal van de aanroepende resource gestuurd. Een lege webhookconfig in het andere script hoeft daardoor niet meer handmatig gevuld te worden.

## Universele export

Nieuwe scripts kunnen rechtstreeks centraal loggen:

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

De aanroepende resource wordt automatisch herkend, waarna categorie en kanaal automatisch worden bepaald.

## ox_inventory

De ingebouwde adapter kan standaard loggen:

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

Hierdoor komen `ox_inventory` logs automatisch onder `OX Logs` terecht.

## Scanner en testen

Beschikbare commands:

```text
rslogs_test
rslogs_scan
rslogs_test_webhooks
rslogs_test_resource <resource>
rslogs_status
rslogs_gateway_restart
```

Na een update kun je het beste uitvoeren:

```text
restart rs_discordlogs
rslogs_scan
rslogs_test_webhooks
```

`rslogs_test_webhooks`:

1. scant alle gestarte resources;
2. detecteert webhookcode, webhook-URL's, loggingexports en de fxmanifest bridge;
3. bepaalt automatisch de categorie;
4. maakt de categorie aan wanneer die ontbreekt;
5. maakt het resourcekanaal aan of verplaatst een bestaand kanaal;
6. stuurt een bevestigingsembed in het juiste kanaal.

Eén resource testen:

```text
rslogs_test_resource rs-garage
```

## Routing

Standaard gebruikt logging:

```lua
Config.Routing.Priority = {
    'bot',
    'central_webhook'
}
```

Gevonden oude resource-webhooks worden standaard alleen gedetecteerd en niet als bestemming gebruikt. De centrale webhook is uitsluitend een optionele noodfallback.

## Gateway status

De vaste bot blijft via Discord Gateway online. De presence kan nog wel worden ingesteld:

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

De identiteit van de bot zelf verandert hierdoor niet.

## Beveiliging

- Commit nooit bot-tokens of webhooktokens naar GitHub.
- De centrale bot wordt op Discord user-ID vastgezet.
- Een token van een andere bot wordt geweigerd.
- Loggingevents zijn server-only.
- De webhookbridge onderschept alleen Discord webhook POSTs.
- De dummy webhook uit de compatibility bridge verlaat de server niet.
- Onbekende exports worden niet blind uitgevoerd.
- Third-party resourcebestanden worden niet automatisch aangepast.

## Licentie

MIT License.
