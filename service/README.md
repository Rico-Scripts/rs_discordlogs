# Rico Scripts Official Logging Service

Dit is de server-side service achter `rs_discordlogs` v3. De Discord bot-token staat **alleen hier op de VPS** en nooit in de downloadbare FiveM resource.

## Benodigd

- Node.js 22+
- een Discord bot van Rico Scripts
- HTTPS reverse proxy (Nginx/Caddy aanbevolen)
- write access op `service/data/`

Er zijn geen npm dependencies nodig.

## Starten

```bash
cd service
cp .env.example .env
cp data/licenses.example.json data/licenses.json
chmod 600 .env data/licenses.json
```

Vul minimaal in:

```env
DISCORD_BOT_TOKEN=...
DISCORD_APPLICATION_ID=...
HOST=127.0.0.1
PORT=3099
```

Start voor een test:

```bash
set -a
. ./.env
set +a
node src/server.js
```

Controle:

```bash
curl http://127.0.0.1:3099/health
```

## License maken

```bash
node scripts/license-admin.js create "Klantnaam"
```

De key wordt maar één keer volledig getoond. In `licenses.json` wordt alleen de SHA-256 hash opgeslagen.

Andere beheercommando's:

```bash
node scripts/license-admin.js list
node scripts/license-admin.js rebind <license-id> [guild-id]
node scripts/license-admin.js disable <license-id>
node scripts/license-admin.js enable <license-id>
node scripts/license-admin.js expire <license-id> 2027-01-01
node scripts/license-admin.js expire <license-id> clear
```

Bij eerste geldig gebruik bindt de license automatisch aan zowel de Discord guild als een lokale FiveM installatie-ID. `rebind` wist de installatiebinding zodat een verhuizing mogelijk is.

## Discord categorieën per scriptmaker

Vanaf v3.1 krijgt ieder script automatisch een categorie op basis van de maker die de FiveM-resource meestuurt uit zijn `fxmanifest.lua`.

Voorbeeld:

```lua
author 'Rico-Scripts'
```

wordt:

```text
Rico-Scripts
└── #resource-naam
```

Er zijn geen vaste `RS Logs`, `ESX Logs` of `OX Logs` categorieën meer. Maker-categorieën worden pas aangemaakt zodra de eerste log van die maker binnenkomt.

Fallbacks:

- geen `author`/maker -> `Onbekende Scripts`
- algemene serverlogs zoals `connections` -> `Algemene Logs`

Bestaande kanalen met dezelfde naam worden automatisch naar de gevonden makercategorie verplaatst.

## Discord permissies

De invite die de API genereert bevat:

- View Channels
- Manage Channels
- Send Messages
- Embed Links
- Read Message History

De API accepteert geen klant-bot-token. Er bestaat maar één `DISCORD_BOT_TOKEN`: die van de officiële centraal gehoste bot.

## Systemd

Gebruik `rs-discordlogs.service.example` als basis. Pas gebruiker en paden aan en plaats de echte `.env` alleen op de VPS.

## HTTPS

Publiceer de API uitsluitend via HTTPS. `nginx.example.conf` bevat een basis reverse-proxyconfig. Vervang `logs.example.com` door je echte domein en configureer een geldig certificaat.

## Endpoints

- `GET /health` - publieke healthcheck
- `GET /v1/info?guildId=...` - officiële botgegevens + invite
- `POST /v1/register` - license/installatie registreren
- `GET /v1/status` - status voor een gelicentieerde installatie
- `POST /v1/log` - log via de officiële bot; accepteert `resource`, `maker` en `payload`
- `POST /v1/test` - testbericht via de officiële bot

Alle gelicentieerde endpoints gebruiken `Authorization: Bearer <license-key>`.

## Validatie

```bash
npm run check
```

Dit controleert de JavaScript-syntax en test ook expliciet de categorie-routing op basis van scriptmaker.
