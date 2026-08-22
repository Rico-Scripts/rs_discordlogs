# fxmanifest patcher

`patch_fxmanifests.py` is een host-side tool die alle `fxmanifest.lua` bestanden onder je FiveM `resources`-map kan nalopen en de centrale logging bridge toevoegt:

```lua
'@rs_discordlogs/server/intercept.lua',
```

## Waarom niet als FiveM command?

De Cfx/FiveM sandbox blokkeert schrijven naar bestanden van andere resources. Daarom moet deze tool buiten FXServer worden uitgevoerd, bijvoorbeeld via SSH/terminal op de host of lokaal op een kopie van je `resources`-map.

## Linux / Pterodactyl host

Eerst alleen controleren (dry-run):

```bash
python3 tools/patch_fxmanifests.py /home/container/resources
```

Werkelijk aanpassen:

```bash
python3 tools/patch_fxmanifests.py /home/container/resources --apply
```

Als je de tool vanuit de map van `rs_discordlogs` uitvoert, blijft het eerste argument altijd het pad naar de volledige `resources`-map.

## Windows

Dry-run:

```powershell
py tools\patch_fxmanifests.py "D:\server\resources"
```

Aanpassen:

```powershell
py tools\patch_fxmanifests.py "D:\server\resources" --apply
```

## Wat doet de tool?

- zoekt recursief alle `fxmanifest.lua` bestanden;
- slaat `rs_discordlogs` zelf over;
- wijzigt nooit hetzelfde manifest twee keer;
- zet de bridge na een server-side `config.lua` / `settings.lua` als die bestaat;
- anders zet hij de bridge vóór de overige server scripts;
- manifests zonder server scripts worden standaard overgeslagen;
- maakt vóór iedere wijziging een volledige backup;
- schrijft via een tijdelijk bestand en vervangt daarna atomisch het manifest;
- maakt een `report.json` in de backup-map;
- toont per resource `[PATCH]`, `[OK]`, `[SKIP]` of `[FOUT]`.

## Backups

Backups komen onder:

```text
resources/.rs_discordlogs_backups/<timestamp>/
```

De originele mappenstructuur wordt behouden.

Na `--apply` toont de tool automatisch het restore-commando. Handmatig kan het ook:

```bash
python3 tools/patch_fxmanifests.py /home/container/resources --restore /home/container/resources/.rs_discordlogs_backups/20260822T120000Z
```

## Extra opties

Resource overslaan:

```bash
python3 tools/patch_fxmanifests.py /home/container/resources --apply --exclude monitor --exclude hardcap
```

Ook client-only manifests een server bridge geven:

```bash
python3 tools/patch_fxmanifests.py /home/container/resources --apply --include-client-only
```

Dit is normaal niet nodig en staat daarom standaard uit.

Geen backup maken:

```bash
python3 tools/patch_fxmanifests.py /home/container/resources --apply --no-backup
```

Dit wordt niet aanbevolen.

## Na het patchen

Voer in FXServer uit:

```text
refresh
restart rs_discordlogs
rslogs_scan
rslogs_test_webhooks
```

Zorg dat `rs_discordlogs` vóór je overige resources wordt gestart in `server.cfg`, zodat de bridge beschikbaar is wanneer die resources laden.
