# rs_discordlogs

Centrale Discord logging voor FiveM via de officiële Rico Scripts loggingservice.

## Features

- Centrale hosted Discord-bot
- Geen bot-token in de FiveM-resource
- Licentie per installatie
- Automatische logkanalen per resource
- Automatische categorieën op basis van `author` uit `fxmanifest.lua`
- Legacy webhook bridge
- Scanner voor bestaande webhook- en loggingcode
- Automatische `ox_inventory` logging
- Test- en statuscommands

## Installatie

Voeg toe aan `server.cfg`:

```cfg
set rs_discordlogs_api_url "https://JOUW-LOGGING-DOMEIN"
set rs_discordlogs_license "RSLOGS_LICENSE_KEY"
set rs_discordlogs_guild "DISCORD_SERVER_ID"

ensure rs_discordlogs
```

Start `rs_discordlogs` vóór resources die de bridge gebruiken.

## Legacy webhook bridge

Voeg bij scripts met bestaande Discord webhooklogging toe aan `server_scripts` in `fxmanifest.lua`:

```lua
'@rs_discordlogs/server/intercept.lua',
```

Plaats deze regel na de config en vóór de eigen servercode.

Voorbeeld:

```lua
server_scripts {
    'config.lua',
    '@rs_discordlogs/server/intercept.lua',
    'server/main.lua'
}
```

## Categorieën

De Discord-categorie wordt automatisch bepaald op basis van de resource metadata:

```lua
author 'Rico-Scripts'
```

Fallback volgorde:

```text
author
creator
developer
Onbekende Scripts
```

Algemene serverlogs worden onder `Algemene Logs` geplaatst.

## Commands

```text
rslogs_status
rslogs_invite
rslogs_test
rslogs_scan
rslogs_test_webhooks
rslogs_test_resource <resource>
```

## Hosted service

De centrale service staat in:

```text
service/
```

Deployment- en beheerinformatie staat in:

```text
service/README.md
```

De officiële Discord bot-token hoort uitsluitend op de centrale server te staan.

## Licentie

Dit project valt onder de **Rico Scripts Proprietary License v1.0**.

Zie `LICENSE` voor de volledige voorwaarden.
