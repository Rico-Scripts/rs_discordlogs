# rs_discordlogs v3

`rs_discordlogs` is een universele centrale Discord logger voor FiveM. Vanaf v3 gebruikt iedere gelicentieerde installatie **de officiële centraal gehoste Rico Scripts Discord bot**.

## Belangrijk verschil met v2

De downloadbare FiveM resource bevat geen bot-token, webhook-token of Discord bot-login meer.

```text
FiveM resource
    -> HTTPS + license key
Rico Scripts Logging API
    -> officiele bot-token (alleen op Rico VPS)
Discord
```

Daardoor kan iemand die de resource downloadt jouw bot-token niet uitlezen of overnemen.

## Klantinstallatie

In `server.cfg` zijn nog maar drie waarden nodig:

```cfg
set rs_discordlogs_api_url "https://JOUW-LOGGING-DOMEIN"
set rs_discordlogs_license "RSLOGS_KLANT_LICENSE_KEY"
set rs_discordlogs_guild "DISCORD_SERVER_ID"

ensure rs_discordlogs
```

Er hoort **geen** `rs_discordlogs_token` meer op een klantserver te staan.

Start `rs_discordlogs` vóór resources die de bridge gebruiken.

## Officiële bot uitnodigen

Voer in de FiveM serverconsole uit:

```text
rslogs_invite
```

De API geeft de invite van de officiële Rico Scripts logging bot terug, al ingevuld voor de geconfigureerde Discord guild.

Daarna:

```text
restart rs_discordlogs
rslogs_status
rslogs_test
```

## Automatische categorieën

Categorieën worden door de centrale service beheerd, niet door klantresources. Standaard:

```text
RS Logs
ESX Logs
OX Logs
Admin Logs
Algemene Logs
Overige Logs
```

Voorbeelden:

```text
RS Logs
├── #rs-bikemechanic
├── #rs-phone
└── #rs-garage

OX Logs
├── #ox-inventory
└── #ox-doorlock

Algemene Logs
└── #connections
```

Bestaande kanalen met dezelfde naam kunnen automatisch naar de correcte categorie worden verplaatst.

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

De aanroepende resource wordt automatisch herkend.

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

`rslogs_test_webhooks` scant gestarte resources op webhookcode, webhook-URL's, loggingexports en de manifest-bridge. Voor iedere gevonden resource wordt via de hosted API en officiële bot een kanaal/testbericht aangemaakt.

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

Item use en open-inventory logs staan standaard uit vanwege spam.

## Server-side hosted service

De officiële service staat in [`service/`](service/) en is bedoeld om op de Rico Scripts VPS te draaien. Zie `service/README.md` voor deployment, systemd, Nginx en licensebeheer.

De bot-token hoort uitsluitend in de VPS environment van die service te staan.

## Migratie van v2 naar v3

Verwijder op klantservers:

```cfg
set rs_discordlogs_token "..."
set rs_discordlogs_webhook "..."
```

Gebruik in plaats daarvan:

```cfg
set rs_discordlogs_api_url "https://JOUW-LOGGING-DOMEIN"
set rs_discordlogs_license "RSLOGS_..."
set rs_discordlogs_guild "DISCORD_SERVER_ID"
```

## Licentie

Dit project is **niet meer MIT**. Het valt onder de `Rico Scripts Proprietary License v1.0` in [`LICENSE`](LICENSE). Herdistributie, resale, key sharing en het omzeilen van license/servicebeveiliging zijn zonder schriftelijke toestemming niet toegestaan.
