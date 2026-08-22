# rs_discordlogs v3.1

`rs_discordlogs` is een universele centrale Discord logger voor FiveM. Iedere gelicentieerde installatie gebruikt **de officiële centraal gehoste Rico Scripts Discord bot**.

## Architectuur

De downloadbare FiveM resource bevat geen bot-token, webhook-token of Discord bot-login.

```text
FiveM resource
    -> HTTPS + license key
Rico Scripts Logging API
    -> officiele bot-token (alleen op Rico VPS)
Discord
```

Daardoor kan iemand die de resource downloadt jouw bot-token niet uitlezen of overnemen.

## Klantinstallatie

In `server.cfg` zijn drie waarden nodig:

```cfg
set rs_discordlogs_api_url "https://JOUW-LOGGING-DOMEIN"
set rs_discordlogs_license "RSLOGS_KLANT_LICENSE_KEY"
set rs_discordlogs_guild "DISCORD_SERVER_ID"

ensure rs_discordlogs
```

Er hoort **geen** `rs_discordlogs_token` op een klantserver te staan.

Start `rs_discordlogs` vóór resources die de bridge gebruiken.

## Officiële bot uitnodigen

```text
rslogs_invite
```

De API geeft de invite van de officiële Rico Scripts logging bot terug voor de ingestelde Discord guild.

Daarna:

```text
restart rs_discordlogs
rslogs_status
rslogs_test
```

## Categorieën automatisch op scriptmaker

Vanaf v3.1 gebruikt de bot **geen vaste RS/ESX/OX-prefixcategorieën meer**.

Bij iedere log leest de FiveM-resource de maker rechtstreeks uit de metadata van het `fxmanifest.lua`:

```lua
author 'Rico-Scripts'
```

Die `author` wordt de Discord-categorie. Voor resources die geen `author` hebben worden ook `creator` en `developer` als fallback geprobeerd.

Voorbeeld:

```text
Rico-Scripts
├── #rs-bikemechanic
├── #rs-phone
├── #rs-garage
└── #rs-duty

Overextended
├── #ox-inventory
├── #ox-lib
└── #ox-target

jaksam1074
└── #jobs-creator

Onbekende Scripts
└── #script-zonder-author

Algemene Logs
└── #connections
```

Er worden bij het registreren **geen standaard scriptcategorieën vooraf aangemaakt**. Een makercategorie ontstaat pas wanneer voor het eerst een resource van die maker wordt gelogd of getest.

Als een bestaand logkanaal nog onder een oude categorie staat, verplaatst de bot het automatisch naar de categorie van de gevonden maker.

Oude lege categorieën zoals `RS Logs`, `ESX Logs` en `OX Logs` worden niet automatisch verwijderd; die kun je na de migratie handmatig verwijderen wanneer ze leeg zijn.

## Legacy webhook bridge

Scripts die al Discord webhooklogging gebruiken kunnen centraal worden doorgestuurd met:

```lua
'@rs_discordlogs/server/intercept.lua',
```

Plaats hem in `server_scripts` **na de config en vóór de eigen servercode**:

```lua
server_scripts {
    'config.lua',
    '@rs_discordlogs/server/intercept.lua',
    'server/main.lua'
}
```

Het oude script mag zijn bestaande `PerformHttpRequest(webhook, ...)` blijven uitvoeren. De bridge onderschept Discord webhook-POSTs en zet ze om naar een hosted logrequest. De losse webhook wordt niet gebruikt als bestemming.

## Universele export

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

De aanroepende resource wordt automatisch herkend. De maker wordt vervolgens uit het `fxmanifest.lua` van die resource gehaald.

Compatibility exports blijven beschikbaar:

```text
LegacyWebhook
Webhook
DiscordLog
SendDiscordLog
CreateLog
WebhookLog
SendWebhook
Logger
```

## Scanner en testen

```text
rslogs_scan
rslogs_test_webhooks
rslogs_test_resource <resource>
```

`rslogs_test_webhooks` scant gestarte resources op webhookcode, webhook-URL's, loggingexports en de manifest-bridge. Voor iedere gevonden resource:

1. wordt de `fxmanifest` maker gelezen;
2. wordt de makercategorie aangemaakt wanneer die ontbreekt;
3. wordt het logkanaal aangemaakt of verplaatst;
4. wordt een bevestigingsembed gestuurd.

In de console zie je ook de maker:

```text
[OK] rs_phone -> maker=Rico-Scripts | hosted kanaal + bridge bevestigd via official_bot
```

## Statuscommands

```text
rslogs_status
rslogs_invite
rslogs_test
```

`rslogs_status` controleert de license, installatiebinding, Discord guild en aanwezigheid van de officiële bot.

## Licensebeveiliging

Elke klant krijgt een unieke `RSLOGS_...` key. De hosted service:

- slaat alleen een SHA-256 hash van de key op;
- bindt de key bij eerste gebruik aan één Discord guild;
- bindt hem ook aan één FiveM installatie-ID;
- kan keys uitschakelen, laten verlopen of opnieuw binden;
- rate-limitt logrequests per license;
- accepteert nooit een klant-bot-token;
- stuurt geen willekeurige Discord mentions door.

## ox_inventory

De bestaande adapter blijft werken voor onder andere:

- transfers;
- aankopen;
- crafting.

Omdat de maker uit het manifest wordt gelezen, komt `ox_inventory` automatisch onder de categorie die in zijn eigen `author` metadata staat.

## Server-side hosted service

De officiële service staat in `service/` en is bedoeld om op de Rico Scripts VPS te draaien. Zie `service/README.md` voor deployment, systemd, Nginx en licensebeheer.

De bot-token hoort uitsluitend in de VPS environment van die service te staan.

## Migratie vanaf v3.0

Na update naar v3.1:

```text
restart rs_discordlogs
rslogs_scan
rslogs_test_webhooks
```

Hiermee worden bestaande resourcekanalen naar hun nieuwe makercategorie verplaatst. Eventuele oude lege `RS Logs`, `ESX Logs`, `OX Logs` of `Overige Logs` categorieën kun je daarna verwijderen.

## Licentie

Dit project valt onder de `Rico Scripts Proprietary License v1.0` in `LICENSE`. Herdistributie, resale, key sharing en het omzeilen van license/servicebeveiliging zijn zonder schriftelijke toestemming niet toegestaan.
