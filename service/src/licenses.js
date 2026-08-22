import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

export class LicenseError extends Error {
    constructor(code, status = 403, message = code) {
        super(message);
        this.name = 'LicenseError';
        this.code = code;
        this.status = status;
    }
}

export function sha256(value) {
    return crypto.createHash('sha256').update(String(value || ''), 'utf8').digest('hex');
}

function normalizeDatabase(input) {
    const db = input && typeof input === 'object' ? input : {};
    db.version = Number(db.version) || 1;
    db.licenses = Array.isArray(db.licenses) ? db.licenses : [];
    return db;
}

export class LicenseStore {
    constructor(filePath) {
        this.filePath = path.resolve(filePath);
        this.db = { version: 1, licenses: [] };
        this.mtimeMs = 0;
        this.ensureFile();
        this.reload(true);
    }

    ensureFile() {
        fs.mkdirSync(path.dirname(this.filePath), { recursive: true });
        if (!fs.existsSync(this.filePath)) {
            fs.writeFileSync(this.filePath, JSON.stringify({ version: 1, licenses: [] }, null, 2) + '\n', {
                mode: 0o600
            });
        }
    }

    reload(force = false) {
        const stat = fs.statSync(this.filePath);
        if (!force && stat.mtimeMs <= this.mtimeMs) return;

        const raw = fs.readFileSync(this.filePath, 'utf8');
        this.db = normalizeDatabase(JSON.parse(raw || '{}'));
        this.mtimeMs = stat.mtimeMs;
    }

    save() {
        const temp = `${this.filePath}.${process.pid}.tmp`;
        fs.writeFileSync(temp, JSON.stringify(this.db, null, 2) + '\n', { mode: 0o600 });
        fs.renameSync(temp, this.filePath);
        this.mtimeMs = fs.statSync(this.filePath).mtimeMs;
    }

    findByKey(key) {
        this.reload();
        const keyHash = sha256(key);
        return this.db.licenses.find((entry) => entry && entry.keyHash === keyHash) || null;
    }

    authenticate({ key, guildId, installId, serverName }) {
        if (!key) throw new LicenseError('missing_license', 401, 'License key ontbreekt.');
        if (!guildId) throw new LicenseError('missing_guild', 400, 'Discord guild ID ontbreekt.');
        if (!installId) throw new LicenseError('missing_install_id', 400, 'Installatie-ID ontbreekt.');

        const record = this.findByKey(key);
        if (!record) throw new LicenseError('invalid_license', 401, 'Ongeldige license key.');
        if (record.enabled === false) throw new LicenseError('license_disabled', 403, 'License is uitgeschakeld.');

        if (record.expiresAt) {
            const expiresAt = Date.parse(record.expiresAt);
            if (Number.isFinite(expiresAt) && Date.now() >= expiresAt) {
                throw new LicenseError('license_expired', 403, 'License is verlopen.');
            }
        }

        const wantedGuild = String(guildId);
        const wantedInstallHash = sha256(installId);
        let changed = false;

        if (!record.guildId) {
            record.guildId = wantedGuild;
            changed = true;
        } else if (String(record.guildId) !== wantedGuild) {
            throw new LicenseError('guild_mismatch', 403, 'Deze license is aan een andere Discord-server gekoppeld.');
        }

        if (!record.installIdHash) {
            record.installIdHash = wantedInstallHash;
            changed = true;
        } else if (record.installIdHash !== wantedInstallHash) {
            throw new LicenseError('install_mismatch', 403, 'Deze license is aan een andere FiveM-installatie gekoppeld.');
        }

        const now = new Date().toISOString();
        record.lastSeenAt = now;
        changed = true;

        if (serverName && record.lastServerName !== String(serverName).slice(0, 200)) {
            record.lastServerName = String(serverName).slice(0, 200);
        }

        if (changed) this.save();
        return record;
    }
}
