import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { sha256 } from '../src/licenses.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const filePath = path.resolve(process.env.LICENSE_FILE || path.resolve(__dirname, '../data/licenses.json'));

function load() {
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    if (!fs.existsSync(filePath)) fs.writeFileSync(filePath, JSON.stringify({ version: 1, licenses: [] }, null, 2) + '\n', { mode: 0o600 });
    const db = JSON.parse(fs.readFileSync(filePath, 'utf8') || '{}');
    db.version = Number(db.version) || 1;
    db.licenses = Array.isArray(db.licenses) ? db.licenses : [];
    return db;
}

function save(db) {
    fs.writeFileSync(filePath, JSON.stringify(db, null, 2) + '\n', { mode: 0o600 });
}

function usage() {
    console.log(`Usage:\n  node scripts/license-admin.js create <label> [guildId]\n  node scripts/license-admin.js list\n  node scripts/license-admin.js rebind <licenseId> [guildId]\n  node scripts/license-admin.js enable <licenseId>\n  node scripts/license-admin.js disable <licenseId>\n  node scripts/license-admin.js expire <licenseId> <ISO-date|clear>`);
}

const [command, ...args] = process.argv.slice(2);
const db = load();

if (command === 'create') {
    const label = args[0];
    if (!label) { usage(); process.exit(1); }
    const rawKey = `RSLOGS_${crypto.randomBytes(32).toString('base64url')}`;
    const record = {
        id: crypto.randomUUID(),
        label: String(label).slice(0, 120),
        keyHash: sha256(rawKey),
        guildId: args[1] ? String(args[1]) : null,
        installIdHash: null,
        enabled: true,
        createdAt: new Date().toISOString(),
        expiresAt: null,
        lastSeenAt: null,
        lastServerName: null
    };
    db.licenses.push(record);
    save(db);
    console.log(`License aangemaakt\nID: ${record.id}\nLabel: ${record.label}\nKey (alleen nu zichtbaar): ${rawKey}`);
} else if (command === 'list') {
    const view = db.licenses.map((record) => ({
        id: record.id,
        label: record.label,
        enabled: record.enabled !== false,
        guildId: record.guildId || '-',
        installBound: !!record.installIdHash,
        expiresAt: record.expiresAt || '-',
        lastSeenAt: record.lastSeenAt || '-'
    }));
    console.table(view);
} else if (['rebind', 'enable', 'disable', 'expire'].includes(command)) {
    const id = args[0];
    const record = db.licenses.find((entry) => entry.id === id);
    if (!record) { console.error('License ID niet gevonden.'); process.exit(1); }

    if (command === 'rebind') {
        record.guildId = args[1] ? String(args[1]) : null;
        record.installIdHash = null;
        record.lastSeenAt = null;
        console.log(`License ${id} is opnieuw vrijgegeven${record.guildId ? ` voor guild ${record.guildId}` : ''}.`);
    } else if (command === 'enable') {
        record.enabled = true;
        console.log(`License ${id} ingeschakeld.`);
    } else if (command === 'disable') {
        record.enabled = false;
        console.log(`License ${id} uitgeschakeld.`);
    } else if (command === 'expire') {
        const value = args[1];
        if (!value) { usage(); process.exit(1); }
        if (value === 'clear') record.expiresAt = null;
        else {
            const date = new Date(value);
            if (Number.isNaN(date.getTime())) { console.error('Ongeldige datum.'); process.exit(1); }
            record.expiresAt = date.toISOString();
        }
        console.log(`License ${id} expiresAt = ${record.expiresAt || 'geen'}.`);
    }
    save(db);
} else {
    usage();
    process.exit(command ? 1 : 0);
}
